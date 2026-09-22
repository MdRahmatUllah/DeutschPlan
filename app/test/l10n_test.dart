import 'dart:convert';
import 'dart:io';

import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// docs/05-dev-guide/coding-standards.md: "Copy lives in ARB files."
/// German course text comes from content.db, never from ARB; fixed German UI
/// copy is an ARB key and says so in its @-description.
void main() {
  test('every ARB key in the template has a description', () {
    final arb = jsonDecode(
      File('lib/l10n/app_en.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    final keys = arb.keys.where((k) => !k.startsWith('@')).toList();

    expect(keys, isNotEmpty, reason: 'app_en.arb has no messages');
    for (final key in keys) {
      final meta = arb['@$key'];
      expect(
        meta,
        isA<Map<String, dynamic>>(),
        reason: '"$key" has no @$key metadata block',
      );
      expect(
        (meta as Map<String, dynamic>)['description'],
        isA<String>().having((d) => d.trim(), 'description', isNotEmpty),
        reason: '"$key" has no description',
      );
    }
  });

  test('every key in the template is translated in every other ARB', () {
    // gen_l10n falls back to English for a key a locale lacks, silently —
    // `splashPreparing` shipped that way, and the splash read English under
    // Bangla with nothing failing. Reading the files is the only place the
    // gap is visible; the generated class has already papered over it.
    Set<String> keysOf(File file) =>
        (jsonDecode(file.readAsStringSync()) as Map<String, Object?>).keys
            .where((key) => !key.startsWith('@'))
            .toSet();

    final template = keysOf(File('lib/l10n/app_en.arb'));
    for (final arb
        in Directory('lib/l10n')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.arb'))
            .where((f) => !f.path.endsWith('app_en.arb'))) {
      expect(
        template.difference(keysOf(arb)),
        isEmpty,
        reason: '${arb.path} is missing these keys, so they show in English',
      );
    }
  });

  test('every supported locale resolves every key', () async {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = await AppLocalizations.delegate.load(locale);
      expect(l10n.appTitle, isNotEmpty, reason: 'appTitle missing for $locale');
      expect(
        l10n.loadingCourse,
        isNotEmpty,
        reason: 'loadingCourse missing for $locale',
      );
      expect(l10n.retry, isNotEmpty, reason: 'retry missing for $locale');
      expect(l10n.undo, isNotEmpty, reason: 'undo missing for $locale');
    }
  });

  test('no user-facing string is hard-coded under lib/', () {
    // Matches Text('literal') / Text("literal") and tooltip:/semanticsLabel:
    // string literals — the two ways copy usually leaks past ARB. A literal that
    // is genuinely not copy (an asset key, a route name) belongs in a const, not
    // in one of these positions.
    final patterns = <RegExp>[
      RegExp(r'''\bText\(\s*(['"])(?!\s*\1)[^'"]*\1'''),
      RegExp(
        r'''\b(?:tooltip|semanticsLabel|label|hintText)\s*:\s*(['"])(?!\s*\1)[^'"]*\1''',
      ),
    ];

    final offenders = <String>[];
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      if (file.path.contains('l10n')) continue; // generated localisations
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (line.contains('ponytail: allow-literal')) continue;
        for (final p in patterns) {
          if (p.hasMatch(line)) {
            final path = file.path.split(Platform.pathSeparator).join('/');
            offenders.add('$path:${i + 1}: ${line.trim()}');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Move this copy into lib/l10n/app_en.arb and app_bn.arb:\n'
          '${offenders.join('\n')}',
    );
  });
}
