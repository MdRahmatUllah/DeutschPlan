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
