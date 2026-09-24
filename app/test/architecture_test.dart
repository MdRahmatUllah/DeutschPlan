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
    ];

    final domain = Directory('lib/domain');

    test(
      'imports nothing from Flutter, drift or any plugin',
      () {
        final offenders = <String>[];
        for (final file in _dartFilesIn('lib/domain')) {
          final source = file.readAsStringSync();
          for (final package in forbidden) {
            if (_imports(source, package, prefix: true)) {
              offenders.add('${_rel(file)}: imports $package');
            }
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
      'FilledButton': 'DpButton',
      'ElevatedButton': 'DpButton',
      'OutlinedButton': 'DpButton(kind: secondary)',
      'TextButton(': 'DpButton(kind: text)',
      'Chip(': 'DpChip',
      'FilterChip(': 'DpChip(kind: filter)',
      'ActionChip(': 'DpChip',
      'CupertinoDatePicker(': 'Adaptive.showTimePickerFor',
    };

    final offenders = <String>[];
    for (final file in _dartFilesIn('lib')) {
      final path = _rel(file);
      // The wrappers themselves, and main.dart's root MaterialApp.
      if (path.startsWith('lib/core/adaptive/')) continue;
      if (path == 'lib/main.dart') continue;

      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (line.contains('ponytail: allow-chrome')) continue;
        for (final entry in chrome.entries) {
          // , or `DpChip(` matches `Chip(` and `AdaptiveSwitch(` matches
          // and `AdaptiveSwitch(` matches `Switch(`. Built from a RAW string —
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
    ];
    final write = RegExp(
      r'\b(INSERT\s+INTO|UPDATE|DELETE\s+FROM|REPLACE\s+INTO)\s+'
      r'(c\.)?"?(\w+)"?',
      caseSensitive: false,
    );

    final offenders = <String>[];
    for (final file in _dartFilesIn('lib')) {
      for (final match in write.allMatches(file.readAsStringSync())) {
        final table = match.group(3);
        if (contentTables.contains(table)) {
          offenders.add('${_rel(file)}: ${match.group(0)}');
        }
      }
    }

    // The .drift files hold the SQL drift compiles, so they are checked too.
    for (final name in <String>['content.drift', 'content_schema.drift']) {
      final file = File('lib/data/db/$name');
      if (!file.existsSync()) continue;
      for (final match in write.allMatches(file.readAsStringSync())) {
        if (contentTables.contains(match.group(3))) {
          offenders.add('$name: ${match.group(0)}');
        }
      }
    }

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

    /// The `@Riverpod(keepAlive: true)` names in the source.
    ///
    /// Two shapes, and the first version of this got both wrong: a function
    /// provider is `DateTime Function() clock(Ref ref)`, where a regex that
    /// took the word before the parenthesis captured `Function`; and a
    /// notifier is `class Theme extends _$Theme`, which has no parenthesis
    /// at all. Matched on what each one really looks like instead.
    Set<String> declaredKeepAlive() {
      final source = File('lib/core/providers/app_providers.dart')
          .readAsStringSync();

      final names = <String>{};
      for (final match in RegExp(
        r'@Riverpod\(keepAlive: true\)',
      ).allMatches(source)) {
        // Everything up to the end of the declaration's first line.
        final rest = source.substring(match.end);
        final declaration = rest
            .split('\n')
            .skipWhile((line) => line.trim().isEmpty)
            .first;

        final notifier = RegExp(r'class\s+(\w+)').firstMatch(declaration);
        if (notifier != null) {
          names.add(_lowerFirst(notifier.group(1)!));
          continue;
        }

        final function = RegExp(r'(\w+)\s*\(Ref \w+\)').firstMatch(declaration);
        if (function != null) names.add(function.group(1)!);
      }
      return names;
    }

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

    test('the four the doc names are all there', () {
      // #71's criterion: "the keep-alive set is exactly the one
      // state-management.md allows". The doc lists more than this file owns —
      // `studySession`, `examAttempt`, `tts` and `modelManager` belong to
      // their own screens — so this is the part of it that is #71's.
      expect(
        declaredKeepAlive(),
        containsAll(<String>['appDatabase', 'settings', 'clock', 'theme']),
      );
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
    final patterns = <String, RegExp>{
      'a path written inline — use the typed route or a named constant': RegExp(
        r"\b(?:go|push|replace)\(\s*['"
        "]/",
      ),
      'a typed route opened directly — use context.jumpToTab(...)': RegExp(
        r"\)\.(?:go|push)\(\s*(?:context|this)\b",
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
    // Three files are allowed one, and each says why on the line.
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
      // The time picker's initial value comes from the platform's own clock.
      'lib/core/adaptive/adaptive.dart',
    };

    final offenders = <String>[];
    for (final file in _dartFilesIn('lib')) {
      final path = _rel(file);
      if (allowed.contains(path)) continue;
      if (file.readAsStringSync().contains('DateTime.now(')) {
        offenders.add(path);
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
        // A gesture by name, or any handler: `DpSurface(onTap: …)` is as
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
}

/// Every `Semantics(…)` call in [source]: its own arguments (up to its
/// top-level `child:`), the child, and the line it starts on. Bracket-matched,
/// so a nested call's `child:` is not mistaken for this one's.
Iterable<({String args, String child, int line})> _semanticsCalls(
  String source,
) sync* {
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
      // Generated code is rebuilt by `make gen`; its imports are not ours to fix.
      .where((f) => !f.path.endsWith('.g.dart'))
      .where((f) => !f.path.endsWith('.freezed.dart'))
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
