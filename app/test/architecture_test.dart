import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Architectural guards from docs/01-architecture/project-structure.md
/// ("Layering rules") and docs/05-dev-guide/coding-standards.md.
///
/// These rules are cheap to state and expensive to retrofit, so they are
/// enforced mechanically rather than in review.
void main() {
  test(
    'no file under lib/ imports the in-SDK Material or Cupertino libraries',
    () {
      const banned = <String, String>{
        'package:flutter/material.dart': 'package:material_ui/material_ui.dart',
        'package:flutter/cupertino.dart':
            'package:cupertino_ui/cupertino_ui.dart',
      };

      final offenders = <String>[];
      for (final file in _dartFilesIn('lib')) {
        final source = file.readAsStringSync();
        for (final entry in banned.entries) {
          if (_imports(source, entry.key)) {
            offenders.add(
              '${_rel(file)}: imports ${entry.key} — use ${entry.value}',
            );
          }
        }
      }

      expect(offenders, isEmpty, reason: offenders.join('\n'));
    },
  );

  group('layering rule 1 — lib/domain/ is pure Dart', () {
    // "domain/ imports nothing from Flutter or drift. Everything there is
    // unit-testable with plain Dart." — project-structure.md
    const forbidden = <String>[
      'package:flutter/',
      'package:flutter_test/',
      'package:material_ui/',
      'package:cupertino_ui/',
      'package:flutter_riverpod/',
      'package:riverpod_annotation/',
      'package:drift/',
      'package:drift_flutter/',
      'package:sqlite3/',
      'package:go_router/',
      'dart:ui',
      // No disk either: a store in data/ reads it (#695 TS-4).
      'dart:io',
    ];
    // Nor the app's other layers, which build on domain/, not under it: a
    // package import outside lib/domain/, or a relative one out of it.
    final app = RegExp(
      r'''^\s*(?:import|export)\s+['"](?:package:sogda/(?!domain/)|\.\./)''',
      multiLine: true,
    );

    final domain = Directory('lib/domain');

    test(
      'imports nothing from Flutter, drift, any plugin, dart:io or the '
      "app's other layers",
      () {
        final offenders = <String>[];
        for (final file in _dartFilesIn('lib/domain')) {
          final source = file.readAsStringSync();
          for (final package in forbidden) {
            if (_imports(source, package, prefix: true)) {
              offenders.add('${_rel(file)}: imports $package');
            }
          }
          for (final match in app.allMatches(source)) {
            offenders.add('${_rel(file)}: ${match.group(0)!.trim()}');
          }
        }

        expect(
          offenders,
          isEmpty,
          reason:
              'lib/domain/ must stay plain Dart so it is unit-testable without a '
              'Flutter binding. Move the dependency to data/, services/ or features/:\n'
              '${offenders.join('\n')}',
        );
      },
      skip: domain.existsSync()
          ? false
          : 'lib/domain/ does not exist yet — the first '
                'engine lands in #56 (text_norm.dart). This guard activates automatically then.',
    );
  });

  test('only lib/core/theme/ names a raw colour', () {
    // docs/01-architecture/theming.md: "Widgets read tokens, never hex values."
    // A Color(0x…) or Colors.red anywhere else is a value that cannot follow the
    // theme into dark or glass.
    // \b so `genderColors.die` is not mistaken for `Colors.die`.
    final rawColor = RegExp(r'Color\(\s*0x|\bColors\.[a-zA-Z]');

    final offenders = <String>[];
    for (final file in _dartFilesIn('lib')) {
      if (_rel(file).startsWith('lib/core/theme/')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (line.contains('ponytail: allow-raw-colour')) continue;
        if (rawColor.hasMatch(line)) {
          offenders.add('${_rel(file)}:${i + 1}: ${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Read the value from context.tokens instead, so it follows the theme '
          'into dark and glass:\n${offenders.join('\n')}',
    );
  });

  test('screens reach for chrome only through the Adaptive wrappers', () {
    // theming.md: "Chrome follows the platform through Adaptive* wrappers".
    // A screen that builds a Scaffold or a Switch itself is a screen that has
    // to be edited again for the other platform, which is the cost the wrappers
    // exist to avoid. lib/core/adaptive/ is where the platform branch lives.
    const chrome = <String, String>{
      'Scaffold(': 'AdaptiveScaffold',
      'AppBar(': 'AdaptiveScaffold',
      'CupertinoPageScaffold(': 'AdaptiveScaffold',
      'CupertinoNavigationBar(': 'AdaptiveScaffold',
      'Switch(': 'AdaptiveSwitch',
      'CupertinoSwitch(': 'AdaptiveSwitch',
      'SegmentedButton': 'AdaptiveSegmented',
      'TabBar(': 'AdaptiveTabBar',
      'CupertinoSegmentedControl': 'AdaptiveSegmented',
      'CupertinoSlidingSegmentedControl': 'AdaptiveSegmented',
      'showModalBottomSheet(': 'Adaptive.showSheet',
      'showCupertinoModalPopup(': 'Adaptive.showSheet',
      'AlertDialog(': 'Adaptive.showConfirm',
      'CupertinoAlertDialog(': 'Adaptive.showConfirm',
      'showTimePicker(': 'Adaptive.showTimePickerFor',
      // Buttons and chips carry the Paper & Ink treatment — the 2 px ink
      // border and the hard offset shadow — which no Material default has.
      'FilledButton': 'SgButton',
      'ElevatedButton': 'SgButton',
      'OutlinedButton': 'SgButton(kind: secondary)',
      'TextButton(': 'SgButton(kind: text)',
      'TextButton.icon(': 'SgButton(kind: text)',
      'Chip(': 'SgChip',
      'FilterChip(': 'SgChip(kind: filter)',
      'ActionChip(': 'SgChip',
      'CupertinoDatePicker(': 'Adaptive.showTimePickerFor',
      // #695 TS-4. A TextField isn't here: the SDK's own follows the platform
      // (its cursor, handles and menu), and each of ours is drawn from the
      // tokens, the same on both, as a content component is.
      'showDialog(': 'Adaptive.showConfirm or Adaptive.showPane',
      'showCupertinoDialog(': 'Adaptive.showConfirm or Adaptive.showPane',
      'showGeneralDialog(': 'Adaptive.showConfirm or Adaptive.showPane',
      'Dialog(': 'Adaptive.showConfirm or Adaptive.showPane',
      'Dialog.fullscreen(': 'Adaptive.showConfirm or Adaptive.showPane',
      'SimpleDialog(': 'Adaptive.showConfirm or Adaptive.showPane',
      // No `(`: `IconButton.filled(` and `.outlined(` are the same button.
      'IconButton': 'an Adaptive or Sg control',
      'SnackBar(': 'SgToast',
    };

    final offenders = <String>[];
    for (final file in _dartFilesIn('lib')) {
      final path = _rel(file);
      // The wrappers themselves. main.dart is read too: its MaterialApp is
      // the root, not chrome, and anything else there is (#695 TS-4).
      if (path.startsWith('lib/core/adaptive/')) continue;

      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        // On the line, or ending the comment above it (#695 TS-4).
        if (_marked(lines, i, 'ponytail: allow-chrome')) continue;
        for (final entry in chrome.entries) {
          // `\b` first, or `SgChip(` matches `Chip(` and `AdaptiveSwitch(`
          // matches `Switch(`. Built from a RAW string —
          // '\b' in an ordinary Dart string is the backspace character, and
          // the pattern then silently matches nothing at all.
          if (RegExp(r'\b' + RegExp.escape(entry.key)).hasMatch(line)) {
            offenders.add('$path:${i + 1}: ${entry.key} — use ${entry.value}');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'chrome belongs behind lib/core/adaptive/:\n'
          '${offenders.join('\n')}',
    );
  });

  test('#695 TS-4 text is SgText, never a raw Text', () {
    // A raw Text (or RichText) has no role, no Bangla fallback, no German
    // voice and no syllable breaks: what SgText, SgOneLine, SgHeadword and
    // SgRuns add.
    // lib/core/typography/ builds those from Text; lib/core/adaptive/'s
    // Material and Cupertino chrome takes the platform's text.
    final raw = RegExp(r'\b(?:Rich)?Text(?:\.rich)?\(');

    final offenders = <String>[];
    for (final file in _dartFilesIn('lib')) {
      final path = _rel(file);
      if (path.startsWith('lib/core/typography/')) continue;
      if (path.startsWith('lib/core/adaptive/')) continue;

      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (_marked(lines, i, 'ponytail: allow-raw-text')) continue;
        if (raw.hasMatch(line)) {
          offenders.add('$path:${i + 1}: ${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'use SgText (SgOneLine, SgHeadword, SgRuns), or say why not with '
          '// ponytail: allow-raw-text on the line or the comment above '
          'it:\n${offenders.join('\n')}',
    );
  });

  test('layering rule 2 — only lib/data/ touches drift', () {
    // "data/ ... is the only layer that touches drift." — project-structure.md
    final offenders = <String>[];
    for (final file in _dartFilesIn('lib')) {
      if (_rel(file).startsWith('lib/data/')) continue;
      final source = file.readAsStringSync();
      if (_imports(source, 'package:drift/', prefix: true) ||
          _imports(source, 'package:drift_flutter/', prefix: true)) {
        offenders.add('${_rel(file)}: imports drift outside lib/data/');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Go through a repository in lib/data/ instead:\n${offenders.join('\n')}',
    );
  });
  test('layering rule 3 — nothing writes to the attached course', () {
    // content.db is read-only by construction, not by a flag: SQLite only
    // honours a `?mode=ro` attach when the main connection was opened with
    // SQLITE_OPEN_URI, and drift_flutter's is not (ADR 26). This is what
    // keeps the promise instead — a write to a content table is a build
    // failure rather than a corrupted course on one learner's phone.
    const contentTables = <String>[
      'words',
      'word_examples',
      'grammar_topics',
      'skill_prompts',
      'interference_tips',
      'levels',
      'sublevels',
      'categories',
      'words_fts',
      'words_trigram',
      'examples_fts',
      'meta',
    ];
    // SQL, `OR IGNORE` and the other conflict clauses included, in any
    // schema (#695 TS-4).
    final write = RegExp(
      r'\b(INSERT(?:\s+OR\s+\w+)?\s+INTO|UPDATE(?:\s+OR\s+\w+)?|'
      r'DELETE\s+FROM|REPLACE\s+INTO)\s+'
      r'(\w+\.)?"?(\w+)"?',
      caseSensitive: false,
    );
    // drift's own API, by the tables' Dart names: `into(db.words)`,
    // `update(words)`, `batch.insertAll(wordExamples, …)`.
    final dartNames = <String>{
      for (final table in contentTables)
        table.replaceAllMapped(
          RegExp('_([a-z])'),
          (m) => m.group(1)!.toUpperCase(),
        ),
    };
    final api = RegExp(
      r'\b(?:into|update|delete|insert|insertAll|insertOnConflictUpdate|'
      r'insertAllOnConflictUpdate|replace|replaceAll|deleteWhere|deleteAll)'
      r'\(\s*(?:[\w.]+\.)?(\w+)\s*[,)]',
    );

    final offenders = <String>[];
    for (final file in _dartFilesIn('lib')) {
      final source = file.readAsStringSync();
      for (final match in write.allMatches(source)) {
        final table = match.group(3);
        if (contentTables.contains(table)) {
          offenders.add('${_rel(file)}: ${match.group(0)}');
        }
      }
      for (final match in api.allMatches(source)) {
        if (dartNames.contains(match.group(1))) {
          offenders.add('${_rel(file)}: ${match.group(0)}');
        }
      }
    }

    // The .drift files hold the SQL drift compiles, so they are checked too:
    // every one, the *_queries.drift files included.
    final drift = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.drift'));
    for (final file in drift) {
      for (final match in write.allMatches(file.readAsStringSync())) {
        if (contentTables.contains(match.group(3))) {
          offenders.add('${_rel(file)}: ${match.group(0)}');
        }
      }
    }
    expect(drift, isNotEmpty);

    expect(
      offenders,
      isEmpty,
      reason:
          'the course is attached read-only by construction; these would '
          'modify it:\n${offenders.join('\n')}',
    );
  });

  test('FR-S1-01 — no I/O inside a widget build()', () {
    // "Keep all I/O in bootstrap() before runApp" — splash.md, and the
    // acceptance criterion on #66. A disk read inside build() runs on every
    // rebuild, on the UI isolate, behind a frame that is already being laid
    // out — and it is invisible until a device is slow enough to show it.
    //
    // Matched on the text of each build() body rather than on an import,
    // because a file may legitimately import dart:io for something that is
    // not in build().
    final io = RegExp(
      r'\b('
      r'File\s*\(|Directory\s*\(|rootBundle\b|'
      r'getApplication\w*Directory|getTemporaryDirectory|'
      r'readAsString|readAsBytes|writeAsString|writeAsBytes|'
      r'existsSync|listSync|deleteSync'
      r')',
    );

    final offenders = <String>[];
    for (final file in _dartFilesIn('lib')) {
      for (final body in _buildBodies(file.readAsStringSync())) {
        for (final match in io.allMatches(body)) {
          offenders.add('${_rel(file)}: ${match.group(0)} inside build()');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'move it into bootstrap() or a provider that resolves before the '
          'frame:\n${offenders.join('\n')}',
    );
  });

  group('state-management.md — the provider policy', () {
    /// The provider map's keepAlive rows, read out of the doc.
    ///
    /// The doc is the source: a provider promoted to `keepAlive` in code and
    /// not in the table, or the reverse, is the drift this catches. A list
    /// restated here would only ever agree with itself.
    Set<String> documentedKeepAlive() {
      final doc = File('../docs/01-architecture/state-management.md')
          .readAsStringSync();

      final table = doc.substring(
        doc.indexOf('## Provider map'),
        doc.indexOf('## Patterns'),
      );

      return <String>{
        for (final line in table.split('\n'))
          if (line.startsWith('| `') && line.contains('keepAlive'))
            RegExp(r'^\| `(\w+)').firstMatch(line)!.group(1)!,
      };
    }

    /// The `@Riverpod(keepAlive: true)` names in the source: every file under
    /// lib/, where reading only app_providers.dart let a keepAlive in a
    /// feature file pass unseen (#695 TS-3).
    Set<String> declaredKeepAlive() => <String>{
      for (final file in _dartFilesIn('lib'))
        ..._keepAliveIn(file.readAsStringSync()),
    };

    test('the doc really does list some', () {
      // Both checks below are set comparisons, and two empty sets are equal.
      expect(documentedKeepAlive(), isNotEmpty);
      expect(declaredKeepAlive(), isNotEmpty);
    });

    test('nothing is kept alive that the doc does not allow', () {
      final extra = declaredKeepAlive().difference(documentedKeepAlive());

      expect(
        extra,
        isEmpty,
        reason:
            'keepAlive is the exception, not the default. These are marked in '
            'code and not in state-management.md:\n${extra.join(', ')}',
      );
    });

    test('#695 TS-3 everything the doc keeps alive is kept alive in code', () {
      // #71's criterion, "the keep-alive set is exactly the one
      // state-management.md allows", both ways now that every file is read:
      // a row for a provider that is gone, or no longer kept alive, is drift
      // too.
      final missing = documentedKeepAlive().difference(declaredKeepAlive());
      expect(
        missing,
        isEmpty,
        reason:
            'state-management.md keeps these alive, and the code does not:\n'
            '${missing.join(', ')}',
      );
    });

    test('#695 TS-3 a keepAlive in a feature file is seen, by its provider '
        'name', () {
      expect(
        declaredKeepAlive(),
        containsAll(<String>['onboarding', 'studySession', 'theme']),
      );
      expect(
        _keepAliveIn(
          '@Riverpod(keepAlive: true)\n'
          r'class PlanDraftNotifier extends _$PlanDraftNotifier {',
        ),
        <String>{'planDraft'},
      );
      expect(
        _keepAliveIn(
          '@Riverpod(keepAlive: true)\n'
          'Stream<int> wordCount(Ref ref, String code) => ref',
        ),
        <String>{'wordCount'},
      );
      // #886: with other arguments, over several lines.
      expect(
        _keepAliveIn(
          '@Riverpod(keepAlive: true, dependencies: [clock])\n'
          'int dayCount(Ref ref) => 1;\n'
          '@Riverpod(\n  dependencies: [clock],\n  keepAlive: true,\n)\n'
          'int weekCount(Ref ref) => 7;\n'
          '@Riverpod(keepAlive: false)\n'
          'int yearCount(Ref ref) => 365;',
        ),
        <String>{'dayCount', 'weekCount'},
      );
    });

    test('#886 no provider is written by hand, so the keepAlive guard, which '
        'reads the annotations, sees every one', () {
      // Riverpod keeps a hand-written provider alive unless it says
      // autoDispose, and nothing above would see it (state-management.md:
      // codegen everywhere).
      final byHand = RegExp(
        r'\b(Provider|StateProvider|FutureProvider|StreamProvider|'
        r'NotifierProvider|AsyncNotifierProvider|StreamNotifierProvider|'
        r'ChangeNotifierProvider|StateNotifierProvider)'
        r'(\.autoDispose)?(\.family)?\s*(<[^;]*>)?\s*\(',
      );
      final offenders = <String>[
        for (final file in _dartFilesIn('lib'))
          for (final (i, line) in file.readAsLinesSync().indexed)
            if (byHand.hasMatch(line)) '${_rel(file)}:${i + 1}: ${line.trim()}',
      ];
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('the repositories are not kept alive', () {
      // They hold no state of their own; the database they wrap is the thing
      // that is expensive, and it is the one that is kept.
      expect(
        declaredKeepAlive(),
        isNot(anyOf(contains('wordRepository'), contains('planRepository'))),
      );
    });
  });

  test('navigation goes through the typed routes and the helper', () {
    // Two ways to get this wrong, and both are silent.
    //
    // A `context.go('/learn/step/A1.1')` compiles for ever, including after
    // the path moves — and a string matching no route lands on Today through
    // `onException`, which reads as an empty screen rather than a broken
    // link. Named constants are fine; a path written inline is not.
    //
    // `SomeRoute().go(context)` is worse, because it looks right: it skips
    // `jumpToTab` and its check that the destination is inside a tab, which
    // is #72's "a single helper performs branch-switch-then-push". The
    // router's own files are where both are allowed.
    //
    // Matched against the whole file rather than line by line: `dart format`
    // wraps a long call, and a regex needing the quote on the same line as
    // the parenthesis would miss exactly the longest paths.
    //
    // In either quote, by any of go_router's verbs, and by name too: a
    // route's name is as unchecked as its path (#695 TS-4).
    final patterns = <String, RegExp>{
      'a path written inline — use the typed route or a named constant': RegExp(
        r'''\b(?:go|push|replace|pushReplacement)\(\s*['"]/''',
      ),
      'a route opened by name — use the typed route': RegExp(
        r'\b(?:go|push|replace|pushReplacement)Named\(',
      ),
      'a typed route opened directly — use context.jumpToTab(...)': RegExp(
        r'\)\.(?:go|push|replace|pushReplacement)\(\s*(?:context|this)\b',
      ),
    };

    final offenders = <String>[];
    for (final file in _dartFilesIn('lib')) {
      final path = _rel(file);
      if (path.startsWith('lib/router/')) continue;

      final source = file.readAsStringSync();
      for (final entry in patterns.entries) {
        for (final match in entry.value.allMatches(source)) {
          final line =
              '\n'.allMatches(source.substring(0, match.start)).length + 1;
          offenders.add('$path:$line: ${entry.key}');
        }
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('runApp is handed a ProviderScope', () {
    // riverpod_lint's `missing_provider_scope` already says this — but only
    // under a path-less `dart analyze`. `flutter analyze` skips the plugin
    // (ADR 18) and so does `dart analyze lib test`, and both of those are what
    // someone reaches for when they want a quick check. This holds however
    // the analyzer is invoked.
    //
    // It is load-bearing rather than tidy: S1 now renders before bootstrap
    // has produced a container, so without a scope at the root the first
    // screen that reads a provider during the splash throws.
    final source = File('lib/main.dart').readAsStringSync();

    expect(
      RegExp(r'runApp\(\s*const\s+ProviderScope').hasMatch(source),
      isTrue,
      reason:
          'lib/main.dart must hand runApp a ProviderScope — riverpod_lint '
          'only catches this under `dart analyze` with no path arguments',
    );
  });

  test('every MaterialApp takes the app delegates, not the generated ones', () {
    // gen_l10n's `AppLocalizations.localizationsDelegates` names
    // flutter_localizations' Material and Cupertino delegates, which localise
    // the SDK's widgets. This app draws material_ui's, so under Bangla those
    // found nothing and the nav bar threw. `appLocalizationsDelegates` in
    // main.dart is the list that works; this keeps anyone from reaching past
    // it for the one the generator advertises.
    final offenders = <String>[];
    for (final file in _dartFilesIn('lib')) {
      final path = _rel(file);
      if (path.startsWith('lib/l10n/generated/')) continue;

      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (lines[i].contains('AppLocalizations.localizationsDelegates')) {
          offenders.add('$path:${i + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Use appLocalizationsDelegates from main.dart:\n'
          '${offenders.join('\n')}',
    );
  });

  test('the clock is the only source of now', () {
    // state-management.md: "`DateTime Function()`; overridden in tests for
    // date logic." A study day is a local day, and the plan engine, the
    // streak and the scheduler all turn on which day it is — a second clock
    // means two answers to "is this due", and only one of them is testable.
    //
    // Four files are allowed one, and each says why above it. `DateTime.now`
    // torn off, and `DateTime.timestamp()`, are the same clock (#695 TS-4).
    const allowed = <String>{
      // The clock itself.
      'lib/core/providers/app_providers.dart',
      // `exported_at` and `recorded_at` are "when this actually happened on
      // this device", not "which study day is it" — a test clock moved to
      // 2019 must not make an export claim to have been written then.
      'lib/data/repositories/backup_repository.dart',
      'lib/data/db/content_update.dart',
      // A file's modification time, for the cache's eviction order. Not a
      // date the learner ever sees.
      'lib/data/repositories/synthesis_cache.dart',
    };

    final now = RegExp(r'\bDateTime\.(?:now|timestamp)\b');

    final offenders = <String>[];
    for (final file in _dartFilesIn('lib')) {
      final path = _rel(file);
      if (allowed.contains(path)) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (now.hasMatch(lines[i])) offenders.add('$path:${i + 1}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'read the clock provider instead, or add the file to `allowed` '
          'above with a line saying why it is not a study day:\n'
          '${offenders.join('\n')}',
    );
  });

  test('#312 a Semantics button that hides its gesture carries the tap', () {
    // ONBOARDING §6: every tappable thing is a button in semantics. A
    // `Semantics(button: …)` over `ExcludeSemantics`, or with
    // `excludeSemantics: true`, drops the tap action the GestureDetector
    // below would add: the node says "button", and a screen reader cannot
    // press it. It has to carry `onTap:` itself.
    final offenders = <String>[];
    for (final file in _dartFilesIn('lib')) {
      final source = file.readAsStringSync();
      for (final call in _semanticsCalls(source)) {
        final button = RegExp(r'\bbutton:\s*(?!false\b)').hasMatch(call.args);
        final hides =
            call.args.contains('excludeSemantics: true') ||
            call.child.trimLeft().startsWith('ExcludeSemantics(');
        // A gesture by name, or any handler: `SgSurface(onTap: …)` is as
        // dead behind an excluded subtree as a GestureDetector is.
        final gesture = RegExp(
          r'\b(?:GestureDetector|InkWell)\(|onTap:|onPressed:|onLongPress:',
        ).hasMatch(call.child);
        final longPress =
            call.child.contains('onLongPress:') &&
            !call.args.contains('onLongPress:');
        if (button &&
            hides &&
            gesture &&
            (!call.args.contains('onTap:') || longPress)) {
          offenders.add('${_rel(file)}:${call.line}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          "give the Semantics the gesture's onTap (and onLongPress):\n"
          '${offenders.join('\n')}',
    );
  });

  test('#912 a card button is its own semantics node', () {
    // accessibility-performance.md: a `Semantics(button: …)` over a card (an
    // `SgSurface` or a `GestureDetector`) with no `container` merges its
    // flag, label and tap up into whatever node holds it. T1's grammar card
    // became a button over the whole card list that way (#749). Right under
    // `AdaptiveTapTarget` or `MergeSemantics` it is a node already.
    final card = RegExp(r'^\s*(?:SgSurface|GestureDetector)\(');
    // One single-child wrapper may stand between: L12's navigator cell is
    // `AdaptiveTapTarget(child: SizedBox(width: …, child: Semantics(…)))`,
    // and the target, grown to 48 dp, is its node.
    final held = RegExp(
      r'(?:AdaptiveTapTarget|MergeSemantics)\([^()]*child:\s*'
      r'(?:\w+\([^()]*child:\s*)?$',
    );
    final offenders = <String>[];
    for (final file in _dartFilesIn('lib')) {
      final source = file.readAsStringSync();
      for (final call in _semanticsCalls(source)) {
        // Hiding its child's semantics doesn't make it a node: L4's
        // next-topic link merged up over the whole rule that way.
        final button = RegExp(r'\bbutton:\s*(?!false\b)').hasMatch(call.args);
        if (button &&
            card.hasMatch(call.child) &&
            !call.args.contains('container: true') &&
            !held.hasMatch(call.before)) {
          offenders.add('${_rel(file)}:${call.line}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'give the card button `container: true`:\n${offenders.join('\n')}',
    );
  });

  test('#437 no text colour is a token faded on the screen', () {
    // theming.md, Contrast: text contrast is measured over the tokens by
    // contrast_test.dart. `ink.withValues(alpha: 0.9)` is a colour that test
    // never meets — M1's subtitle was 4.49:1 that way. Use a token as it is.
    final text = RegExp(
      r'(?<![A-Za-z])(?:SgText|SgOneLine|SgHeadword|TextStyle)\(',
    );
    final faded = RegExp(
      r'\bcolor:\s*[^,]*\.(?:withValues\(\s*alpha|withOpacity\(|withAlpha\()',
    );
    final offenders = <String>[];
    for (final file in _dartFilesIn('lib')) {
      final source = file.readAsStringSync();
      for (final match in text.allMatches(source)) {
        var depth = 0;
        for (var i = match.end - 1; i < source.length; i++) {
          if (source[i] == '(') depth++;
          if (source[i] == ')' && --depth == 0) {
            if (faded.hasMatch(source.substring(match.end, i))) {
              final line = '\n'.allMatches(source.substring(0, match.start));
              offenders.add('${_rel(file)}:${line.length + 1}');
            }
            break;
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'give the text a token contrast_test measures, not a faded one:\n'
          '${offenders.join('\n')}',
    );
  });

  test('#706 every business rule is named by a test', () {
    // testing.md: test names carry FR/BR ids. Not every name can (an issue
    // number serves where no rule applies), but no rule goes untested by
    // name. The pipeline's rules are tested in tools/tests, named
    // `test_BR_COURSE_02_…`.
    final rules = RegExp(r'\*\*(BR-[A-Z]+-\d+)\*\*')
        .allMatches(
          File('../docs/00-product/business-rules.md').readAsStringSync(),
        )
        .map((m) => m.group(1)!)
        .toSet();
    final dartName = RegExp(
      r'''\b(?:test|testWidgets|group|goldenTest)\(\s*((?:(?:'[^']*'|"[^"]*")\s*)+)''',
    );
    final pythonName = RegExp(
      r'^\s*(?:def|class) (Test\w+|test_\w+)',
      multiLine: true,
    );
    final names = <String>[
      for (final file in [
        ..._dartFilesIn('test'),
        ..._dartFilesIn('integration_test'),
      ])
        for (final m in dartName.allMatches(file.readAsStringSync())) m[1]!,
      for (final file in Directory(
        '../tools/tests',
      ).listSync().whereType<File>())
        if (file.path.endsWith('.py'))
          for (final m in pythonName.allMatches(file.readAsStringSync()))
            m[1]!.replaceAll('_', '-'),
    ].join('\n');

    expect(rules, isNotEmpty, reason: 'business-rules.md read as no rules');
    expect(
      <String>[
        for (final rule in rules)
          if (!RegExp('${RegExp.escape(rule)}(?!\\d)').hasMatch(names)) rule,
      ],
      isEmpty,
      reason: 'put the rule id in the name of a test that checks it',
    );
  });
}

/// Every `Semantics(…)` call in [source]: its own arguments (up to its
/// top-level `child:`), the child, the line it starts on, and the source
/// before it. Bracket-matched, so a nested call's `child:` is not mistaken for
/// this one's.
Iterable<({String args, String child, int line, String before})>
_semanticsCalls(String source) sync* {
  for (final match in RegExp(r'(?<![A-Za-z])Semantics\(').allMatches(source)) {
    var depth = 0;
    var childAt = -1;
    for (var i = match.end - 1; i < source.length; i++) {
      final char = source[i];
      if (char == '(' || char == '[' || char == '{') depth++;
      if (char == ')' || char == ']' || char == '}') {
        depth--;
        if (depth == 0) {
          yield (
            args: source.substring(match.end, childAt == -1 ? i : childAt),
            child: childAt == -1 ? '' : source.substring(childAt + 6, i),
            line: '\n'.allMatches(source.substring(0, match.start)).length + 1,
            before: source.substring(0, match.start),
          );
          break;
        }
      }
      if (depth == 1 && childAt == -1 && source.startsWith('child:', i)) {
        childAt = i;
      }
    }
  }
}

/// The source of every `build(BuildContext …)` body in [source].
///
/// Brace-matched rather than regex-matched: a regex cannot find the end of a
/// method, and stopping at the next blank line would skip exactly the long
/// build methods worth checking.
Iterable<String> _buildBodies(String source) sync* {
  final signature = RegExp(r'\bbuild\s*\(\s*BuildContext\b');
  for (final match in signature.allMatches(source)) {
    final open = source.indexOf('{', match.end);
    final arrow = source.indexOf('=>', match.end);

    // An expression body: up to the statement's semicolon at depth zero.
    if (arrow != -1 && (open == -1 || arrow < open)) {
      final end = _endOfExpression(source, arrow);
      if (end != -1) yield source.substring(arrow, end);
      continue;
    }
    if (open == -1) continue;

    var depth = 0;
    for (var i = open; i < source.length; i++) {
      if (source[i] == '{') depth++;
      if (source[i] == '}') {
        depth--;
        if (depth == 0) {
          yield source.substring(open, i + 1);
          break;
        }
      }
    }
  }
}

int _endOfExpression(String source, int arrow) {
  var depth = 0;
  for (var i = arrow; i < source.length; i++) {
    final char = source[i];
    if (char == '(' || char == '[' || char == '{') depth++;
    if (char == ')' || char == ']' || char == '}') depth--;
    if (char == ';' && depth == 0) return i;
  }
  return -1;
}

/// `AppDatabase` -> `appDatabase`.
String _lowerFirst(String name) => name[0].toLowerCase() + name.substring(1);

/// The provider names that `@Riverpod(keepAlive: true)` declares in
/// [source].
///
/// Two shapes, and the first version of this got both wrong: a function
/// provider is `DateTime Function() clock(Ref ref)`, where a regex that took
/// the word before the parenthesis captured `Function`; and a notifier is
/// `class ThemeNotifier extends _$ThemeNotifier`, which has no parenthesis
/// at all. Matched on what each one really looks like instead. A notifier's
/// provider drops a `Notifier` suffix, as riverpod_generator names it
/// (`OnboardingNotifier` → `onboardingProvider`).
Set<String> _keepAliveIn(String source) {
  final names = <String>{};
  // Any argument list, over several lines too, with keepAlive among
  // `dependencies:` and the rest (#886).
  for (final match in RegExp(r'@Riverpod\(([^)]*)\)').allMatches(source)) {
    if (!RegExp(r'keepAlive:\s*true').hasMatch(match.group(1)!)) continue;
    // Everything up to the end of the declaration's first line.
    final declaration = source
        .substring(match.end)
        .split('\n')
        .skipWhile((line) => line.trim().isEmpty)
        .first;

    final notifier = RegExp(r'class\s+(\w+)').firstMatch(declaration);
    if (notifier != null) {
      final name = _lowerFirst(notifier.group(1)!);
      names.add(
        name.endsWith('Notifier') && name != 'Notifier'
            ? name.substring(0, name.length - 'Notifier'.length)
            : name,
      );
      continue;
    }

    // A family's parameters follow the ref: `stepWords(Ref ref, String code)`.
    final function = RegExp(r'(\w+)\s*\(Ref \w+[,)]').firstMatch(declaration);
    if (function != null) names.add(function.group(1)!);
  }
  return names;
}

/// True when line [i] of [lines] carries [marker], or the comment line just
/// above it does: `dart format` moves a comment after an opening bracket to
/// the next line.
bool _marked(List<String> lines, int i, String marker) =>
    lines[i].contains(marker) ||
    (i > 0 &&
        lines[i - 1].trimLeft().startsWith('//') &&
        lines[i - 1].contains(marker));

/// Repo-relative path with forward slashes on every platform.
///
/// Built by splitting on the platform separator rather than by escaping a
/// backslash in a string literal — that escape is easy to lose in a patch, and
/// when it goes the comparisons below silently stop matching anything.
String _rel(File f) => f.path.split(Platform.pathSeparator).join('/');

Iterable<File> _dartFilesIn(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) return const <File>[];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      // Generated code is rebuilt by build_runner (`getting-started.md`);
      // its imports are not ours to fix.
      .where((f) => !f.path.endsWith('.g.dart'))
      .where((f) => !f.path.endsWith('.drift.dart'))
      .where((f) => !_rel(f).contains('lib/l10n/generated/'));
}

/// True when [source] has an `import`/`export` directive for [package].
/// Matching the directive rather than the bare string keeps a mention inside a
/// comment or a string literal from failing the build.
bool _imports(String source, String package, {bool prefix = false}) {
  final quoted = RegExp.escape(package);
  final tail = prefix ? "[^'\"]*" : '';
  final pattern =
      r'^\s*(?:import|export)\s+'
      "['\"]"
      '$quoted$tail'
      "['\"]";
  return RegExp(pattern, multiLine: true).hasMatch(source);
}
