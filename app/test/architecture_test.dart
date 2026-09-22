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
