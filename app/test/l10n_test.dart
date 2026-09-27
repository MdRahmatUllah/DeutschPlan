import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/l10n/ui_digits.dart';
import 'package:sogda/features/today/today_view.dart' show germanDate;
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

  group('#695 TS-5 every translation matches the template', () {
    Map<String, Object?> arb(String name) =>
        jsonDecode(File('lib/l10n/$name').readAsStringSync())
            as Map<String, Object?>;
    final en = arb('app_en.arb');
    final others = <String, Map<String, Object?>>{
      for (final file
          in Directory('lib/l10n')
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.arb'))
              .where((f) => !f.path.endsWith('app_en.arb')))
        file.uri.pathSegments.last:
            jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
    };

    test('no key the template lacks', () {
      // The other direction of "every key is translated": a key only a
      // translation has is never shown, and is usually a rename half done.
      for (final MapEntry(key: name, value: other) in others.entries) {
        final extra = other.keys
            .where((key) => !key.startsWith('@') && !en.containsKey(key))
            .toList();
        expect(extra, isEmpty, reason: '$name has keys app_en.arb lacks');
      }
    });

    test('every placeholder the template declares', () {
      // A dropped {count} reads fine in the file and wrong on the screen.
      for (final MapEntry(key: name, value: other) in others.entries) {
        final missing = <String>[];
        for (final key in en.keys.where((key) => !key.startsWith('@'))) {
          final meta = en['@$key'] as Map<String, Object?>?;
          final placeholders =
              (meta?['placeholders'] as Map<String, Object?>?)?.keys ??
              const <String>[];
          final text = other[key] as String?;
          if (text == null) continue;
          for (final placeholder in placeholders) {
            if (!RegExp('\\{$placeholder\\s*[,}]').hasMatch(text)) {
              missing.add('$key: {$placeholder}');
            }
          }
        }
        expect(missing, isEmpty, reason: '$name drops placeholders');
      }
    });

    test("the same select cases as the template's", () {
      // A select case a translation lacks falls through to its `other`, a
      // case it adds is never chosen: either way the text is the wrong one.
      Set<String> cases(String text) => <String>{
        for (final match in RegExp(
          r'(?<![\w-])([A-Za-z]\w*)\{',
        ).allMatches(text))
          match.group(1)!,
      };
      for (final MapEntry(key: name, value: other) in others.entries) {
        final differ = <String>[];
        for (final key in en.keys.where((key) => !key.startsWith('@'))) {
          final template = en[key]! as String;
          final text = other[key] as String?;
          if (text == null || !template.contains(', select,')) continue;
          final (want, have) = (cases(template), cases(text));
          if (want.length != have.length || !want.containsAll(have)) {
            differ.add('$key: ${cases(template)} vs ${cases(text)}');
          }
        }
        expect(differ, isEmpty, reason: '$name select cases differ');
      }
    });
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
      'modelsSizeMb',
      'modelsSizeGb',
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
        .replaceAll('Hy-MT 1.5', '')
        .replaceAll('Supertonic 3', '');
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
            if (placeholder is Map<String, dynamic> &&
                placeholder['format'] == null &&
                (const <String>{
                      'int',
                      'double',
                      'num',
                    }.contains(placeholder['type']) ||
                    (placeholder['type'] == null &&
                        (en[key.substring(1)] as String).contains(
                          '{$name, plural,',
                        ))))
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

  test('#425 a number is never written straight into text: it goes through '
      'l10n.digits', () {
    // SgText('$count'), or a pill's `label: streak.toString()`, prints 0–9 in
    // the Bangla UI; T1's streak pill did.
    // An SgText literal that is only numbers once its interpolations go
    // ("$n", "${a} / ${b}"), and a label that is a number's toString.
    final text = RegExp(r"SgText\(\s*'([^'\n]*\$[^'\n]*)'");
    final label = RegExp(r'\blabel:\s*[\w.]+\.toString\(\)');
    // A literal that is words, not a number (a headword and a step code),
    // is marked `// ponytail: allow-literal` on the line above it, which
    // takes it out of [text]'s match.
    bool wordless(String literal) =>
        !RegExp('[A-Za-zঀ-৿]')
            .hasMatch(literal.replaceAll(RegExp(r'\$\{[^}]*\}|\$\w+'), ''));
    final offenders = <String>[
      for (final file in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart') && !file.path.contains('generated'))
          for (final source in <String>[file.readAsStringSync()]) ...<String>[
            for (final match in text.allMatches(source))
              if (wordless(match[1]!)) '${file.path}: ${match[0]}',
            for (final match in label.allMatches(source))
              '${file.path}: ${match[0]}',
          ],
    ];
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('every supported locale resolves every key', () async {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = await AppLocalizations.delegate.load(locale);
      expect(l10n.appTitle, isNotEmpty, reason: 'appTitle missing for $locale');
      expect(l10n.retry, isNotEmpty, reason: 'retry missing for $locale');
      expect(l10n.undo, isNotEmpty, reason: 'undo missing for $locale');
    }
  });

  test('#640 every ARB key is read somewhere under lib/', () {
    final arb = jsonDecode(
      File('lib/l10n/app_en.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    final source = [
      for (final file in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart') && !file.path.contains('generated'))
          file.readAsStringSync(),
    ].join('\n');
    final unused = [
      for (final key in arb.keys.where((k) => !k.startsWith('@')))
        if (!_reads(source, key)) key,
    ];
    expect(
      unused,
      isEmpty,
      reason:
          'Nothing in lib/ reads these: delete them from app_en.arb and '
          'app_bn.arb',
    );
  });

  test('#825 a key is read through the localizations, not by any member '
      'of its name', () {
    expect(_reads('final l10n = x; l10n.done;', 'done'), isTrue);
    expect(_reads('AppLocalizations.of(context)\n    .undo', 'undo'), isTrue);
    // `revise.done` is not the ARB's `done`, nor `l10n.doneAll` it.
    expect(_reads('revise.done + newToday.done', 'done'), isFalse);
    expect(_reads('l10n.doneAll', 'done'), isFalse);
  });

  test('#681 no user-facing string is hard-coded under lib/', () {
    // A string literal where copy goes: the text widgets (`Text`, and the
    // `SgText`, `SgOneLine` and `SgHeadword` the screens use: `\bText` never
    // matched inside `SgText`) and tooltip:/semanticsLabel:/label:/hintText:.
    // Matched over the whole file, not line by line: `dart format` puts a
    // long literal on the line after its call (#681). A literal that is
    // genuinely not copy (an asset key, a route name) belongs in a const, or
    // carries `ponytail: allow-literal` on its line.
    final patterns = <RegExp>[
      RegExp(
        r'''(?<![A-Za-z])(?:Sg)?(?:Text|OneLine|Headword)\(\s*(['"])(?!\s*\1)''',
      ),
      RegExp(
        r'''\b(?:tooltip|semanticsLabel|label|hintText)\s*:\s*(['"])(?!\s*\1)''',
      ),
    ];

    final offenders = <String>[];
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      if (file.path.contains('l10n')) continue; // generated localisations
      final source = file.readAsStringSync().replaceAll('\r\n', '\n');
      final lines = source.split('\n');
      for (final p in patterns) {
        for (final match in p.allMatches(source)) {
          final at = '\n'.allMatches(source.substring(0, match.start)).length;
          final line = lines[at];
          if (line.trimLeft().startsWith('//')) continue;
          if (line.contains('ponytail: allow-literal')) continue;
          final path = file.path.split(Platform.pathSeparator).join('/');
          offenders.add('$path:${at + 1}: ${line.trim()}');
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
    // SgProgressRing's "$completed of $total" was a screen-reader label no
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
        // Not copy: a key, an assert's message, a debug toString, a pattern.
        if (RegExp(r'\bKey\(|\bassert\(|toString\(\)|RegExp\(')
            .hasMatch(line)) {
          continue;
        }
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

/// Whether [source] reads the ARB's [key] (#640): through the localizations,
/// `l10n.key` or `AppLocalizations.of(context).key`. Any `.key` would count
/// `revise.done` as a read of `done` (#816, #825).
bool _reads(String source, String key) =>
    RegExp('(?:\\bl10n|AppLocalizations\\.of\\(\\w+\\))\\s*\\.\\s*$key\\b')
        .hasMatch(source);
