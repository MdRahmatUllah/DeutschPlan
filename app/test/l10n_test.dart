import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/l10n/ui_digits.dart';
import 'package:deutschplan/features/today/today_view.dart' show germanDate;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show Intl;

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

  test('#166 a string Bangla leaves as English is German on purpose, a name '
      'or a unit; any other one is untranslated', () {
    // German the learner is looking at stays German in every UI language:
    // the greeting, the banners, the parts of speech, the exam verdicts
    // (accessibility-performance.md). Names and units stay as they are.
    const onPurpose = <String>{
      'appTitle',
      'onboardingMeaningEnglish',
      'settingsEnglish',
      'settingsVoiceSupertonic',
      'exportImportSizeKb',
      'exportImportSizeMb',
      'onboardingVoiceSample',
      'todayGreetingMorning',
      'todayGreetingDay',
      'todayGreetingEvening',
      'todayGreetingDone',
      'todayRestFree',
      'studyBannerRevise',
      'studyBannerNew',
      'studyBannerNewCategory',
      'studyBannerGrammar',
      'studyBannerBacklog',
      'studyPosNoun',
      'studyPosVerb',
      'studyPosAdjective',
      'studyPosAdverb',
      'studyPosPreposition',
      'studyPosConjunction',
      'studyPosPronoun',
      'studyPosNumber',
      'studyPosParticle',
      'studyPosArticle',
      'studyPosPhrase',
      'summaryTitle',
      'dayCompleteTitle',
      'examResultPassed',
      'examResultFailed',
      'widgetWordOfDay',
    };
    Map<String, Object?> read(String path) =>
        jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
    final en = read('lib/l10n/app_en.arb');
    final bn = read('lib/l10n/app_bn.arb');
    // What is left of a message once its placeholders and ICU syntax are
    // gone: a template like "{done} / {total}" is the same in every
    // language, but a plural's branches are words to translate.
    String words(String message) => message
        .replaceAll(RegExp(r'{\w+(,\s*\w+)?}'), '')
        .replaceAll(RegExp(r'{\w+,\s*\w+,'), '')
        .replaceAll(RegExp(r'(=\d+|\w+)\s*{'), '')
        .replaceAll(RegExp('[{}]'), '');

    final untranslated = <String>[
      for (final key in en.keys)
        if (!key.startsWith('@') &&
            !onPurpose.contains(key) &&
            bn[key] == en[key] &&
            RegExp('[A-Za-zÄÖÜäöüß]').hasMatch(words(en[key]! as String)))
          key,
    ];
    expect(
      untranslated,
      isEmpty,
      reason:
          'the same in Bangla as in English: translate them, or add them '
          'to onPurpose if they are German content, a name or a unit',
    );
  });

  test('#166 Bangla numerals never reach German content: Today\'s German date '
      'keeps its digits under a Bangla UI', () {
    final before = Intl.defaultLocale;
    addTearDown(() => Intl.defaultLocale = before);
    Intl.defaultLocale = 'bn';
    final date = germanDate('2026-09-25');
    expect(date, 'Freitag, 25. September');
    expect(
      RegExp('[০-৯]').hasMatch(date),
      isFalse,
      reason: 'a Bengali digit in German',
    );
  });

  test('#425 one digit system per Bangla string: Bangla digits, in the '
      'text and in every number placeholder', () async {
    final bn = jsonDecode(
      File('lib/l10n/app_bn.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    // What a Bangla message writes itself: not its placeholders, the case
    // names of a plural or select ("=1{", "A1{", "60{"), a step's code
    // ("A1.1", "B2+"), nor a product's name.
    String written(String message) => message
        .replaceAll(RegExp(r'\{\w+(,\s*\w+,)?\}?'), '')
        .replaceAll(RegExp(r'=?\w+\{'), '')
        .replaceAll(RegExp(r'\b[ABC][12](\.[12])?\+?'), '')
        .replaceAll('Hy-MT 1.5', '');
    final latin = <String>[
      for (final MapEntry(:key, :value) in bn.entries)
        if (!key.startsWith('@') &&
            value is String &&
            RegExp('[0-9]').hasMatch(written(value)))
          '$key: $value',
    ];
    expect(latin, isEmpty, reason: latin.join('\n'));

    // A number placeholder is formatted for the locale, which in Bangla is
    // its digits; a bare int would print 0–9.
    final en = jsonDecode(
      File('lib/l10n/app_en.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    final unformatted = <String>[
      for (final MapEntry(:key, :value) in en.entries)
        if (key.startsWith('@') && value is Map<String, dynamic>)
          for (final MapEntry(key: name, value: placeholder)
              in ((value['placeholders'] as Map<String, dynamic>?) ??
                      const <String, dynamic>{})
                  .entries)
            if ((placeholder as Map<String, dynamic>)['type'] == 'int' &&
                placeholder['format'] == null)
              '${key.substring(1)}.$name',
    ];
    expect(unformatted, isEmpty, reason: unformatted.join('\n'));

    final bangla = await AppLocalizations.delegate.load(const Locale('bn'));
    expect(bangla.quizLocked(3), contains('৩'));
    expect(bangla.quizLocked(3), isNot(contains('3')));
    expect(bangla.digits('12:05'), '১২:০৫');
    final english = await AppLocalizations.delegate.load(const Locale('en'));
    expect(english.digits('12:05'), '12:05');
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

  test('#425 a component words nothing itself: an interpolated literal in '
      'core/components has no letter outside its placeholders', () {
    // DpProgressRing's "$completed of $total" was a screen-reader label no
    // ARB check could see, so a Bangla learner heard English.
    final literals = <RegExp>[
      RegExp(r"'([^'\n]*\$[^'\n]*)'"),
      RegExp(r'"([^"\n]*\$[^"\n]*)"'),
    ];
    final offenders = <String>[];
    for (final file in Directory(
      'lib/core/components',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        for (final literal in literals) {
          for (final match in literal.allMatches(line)) {
            final words = match
                .group(1)!
                .replaceAll(RegExp(r'\$\{[^}]*\}|\$\w+'), '');
            if (RegExp('[A-Za-z]').hasMatch(words)) {
              offenders.add('${file.path}:${i + 1}: ${line.trim()}');
            }
          }
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
