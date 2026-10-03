import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/data/repositories/model_repository.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/translation_repository.dart';
import 'package:sogda/services/translation/outside_meanings.dart';

import '../../features/model_manager_fixtures.dart' show translationEntry;
import '../../features/settings_fixtures.dart';

/// The translator through its cache, faked: what it was asked, and what it
/// answers for a word in its sentence and for the bare word.
class _Translations extends Fake implements TranslationRepository {
  _Translations({this.inSentence, this.bare});

  final String? Function(String to)? inSentence;
  final String? Function(String to)? bare;
  final List<(String, String, String?)> asked = <(String, String, String?)>[];
  final List<Future<void>?> abandoned = <Future<void>?>[];

  @override
  Future<String?> translate(
    String text, {
    required String from,
    required String to,
    String? context,
    Future<void>? abandoned,
  }) async {
    asked.add((text, to, context));
    this.abandoned.add(abandoned);
    return context == null ? bare?.call(to) : inSentence?.call(to);
  }
}

void main() {
  const sentence = 'Die Eltern saßen auf den Bänken am Fluss.';

  test("#1278 the bare word's meaning first, then the sentence's as «here» "
      'when it differs, into each meaning language in turn', () async {
    final translations = _Translations(
      bare: (to) => <String, String>{'bn': 'বেঞ্চ', 'en': 'bench'}[to],
      inSentence: (to) =>
          <String, String>{'bn': 'বেঞ্চগুলোতে', 'en': 'benches'}[to],
    );
    final seen = await OutsideMeanings(translations)
        .of('Bänken', sentence, <String>['bn', 'en'])
        .toList();
    expect(
      seen,
      <Map<String, List<MeaningSuggestion>>>[
        <String, List<MeaningSuggestion>>{
          'bn': <MeaningSuggestion>[(meaning: 'বেঞ্চ', here: false)],
        },
        <String, List<MeaningSuggestion>>{
          'bn': <MeaningSuggestion>[
            (meaning: 'বেঞ্চ', here: false),
            (meaning: 'বেঞ্চগুলোতে', here: true),
          ],
        },
        <String, List<MeaningSuggestion>>{
          'bn': <MeaningSuggestion>[
            (meaning: 'বেঞ্চ', here: false),
            (meaning: 'বেঞ্চগুলোতে', here: true),
          ],
          'en': <MeaningSuggestion>[(meaning: 'bench', here: false)],
        },
        <String, List<MeaningSuggestion>>{
          'bn': <MeaningSuggestion>[
            (meaning: 'বেঞ্চ', here: false),
            (meaning: 'বেঞ্চগুলোতে', here: true),
          ],
          'en': <MeaningSuggestion>[
            (meaning: 'bench', here: false),
            (meaning: 'benches', here: true),
          ],
        },
      ],
      reason:
          "the bare word's at once, then the sentence's, a language at "
          'a time',
    );
    expect(translations.asked, <(String, String, String?)>[
      ('Bänken', 'bn', null),
      ('Bänken', 'bn', sentence),
      ('Bänken', 'en', null),
      ('Bänken', 'en', sentence),
    ]);
  });

  test("#1278 the same answer twice is one suggestion; the sentence's that "
      'is the sentence translated, or none, is left out', () async {
    final translations = _Translations(
      bare: (to) => <String, String>{'en': 'bench', 'pl': 'ławka'}[to],
      inSentence: (to) => switch (to) {
        'en' => 'Bench',
        'pl' => 'Rodzice siedzieli na ławkach nad rzeką.',
        _ => null,
      },
    );
    final last = await OutsideMeanings(translations)
        .of('Bänken', sentence, <String>['en', 'pl', 'ru'])
        .last;
    expect(last, <String, List<MeaningSuggestion>>{
      'en': <MeaningSuggestion>[(meaning: 'bench', here: false)],
      'pl': <MeaningSuggestion>[(meaning: 'ławka', here: false)],
    });
  });

  test("#1278 a bare answer that explains rather than translates is left "
      "out; a compound's long meaning stays", () async {
    final last = await OutsideMeanings(
      _Translations(
        bare: (to) => switch (to) {
          'en' => 'This is a German word that means a bench in a park.',
          _ => 'কফি পাত্র গরম করার যন্ত্র',
        },
      ),
    ).of('Kaffeekannenwärmer', sentence, <String>['en', 'bn']).last;
    expect(last, <String, List<MeaningSuggestion>>{
      'bn': <MeaningSuggestion>[
        (meaning: 'কফি পাত্র গরম করার যন্ত্র', here: false),
      ],
    });
  });

  test("#1278 with only the sentence's answer, it alone is offered", () async {
    final last = await OutsideMeanings(
      _Translations(inSentence: (to) => 'benches'),
    ).of('Bänken', sentence, <String>['en']).last;
    expect(last, <String, List<MeaningSuggestion>>{
      'en': <MeaningSuggestion>[(meaning: 'benches', here: true)],
    });
  });

  test('#1233 nothing from the translator (no model, translation off): no '
      'meaning, so D2 offers the download', () async {
    final seen = await OutsideMeanings(_Translations())
        .of('Bänken', sentence, <String>['en', 'bn'])
        .toList();
    expect(seen, <Map<String, List<MeaningSuggestion>>>[
      <String, List<MeaningSuggestion>>{},
    ], reason: 'one empty answer, so the card stops waiting');
  });

  test("#1233 the word's answer, not the sentence's: 1 to 4 words, as the "
      'spot check found them', () {
    expect(OutsideMeanings.isTheWords('benches'), isTrue);
    expect(
      OutsideMeanings.isTheWords('মাসের পর মাস ধরে'),
      isTrue,
      reason: 'monatelang, in 4 words',
    );
    // The spot check's misses: a sentence, shorter than its German.
    expect(
      OutsideMeanings.isTheWords(
        'Zabierzcie dziecko na czas lub dajcie mu pozwolenie',
      ),
      isFalse,
    );
    expect(
      OutsideMeanings.isTheWords('কোর্সগুলো প্রায় সবসময় পূর্ণ থাকে।'),
      isFalse,
      reason: 'five words, and a sentence ends with «।»',
    );
    expect(
      OutsideMeanings.isTheWords('Plany są dobre.'),
      isFalse,
      reason: 'short, but ends as a sentence ends',
    );
    expect(OutsideMeanings.isTheWords(' '), isFalse);
    expect(OutsideMeanings.isTheWords(null), isFalse);
  });

  group("#1300 D2's card offers M4's download only when it would bring "
      'Hy-MT2', () {
    Future<bool> downloadable({
      required bool fits,
      required ModelStatus status,
    }) async {
      final container = ProviderContainer(
        overrides: <Override>[
          translationFitsProvider.overrideWith((ref) async => fits),
          modelRepositoryProvider.overrideWithValue(_Models(status)),
        ],
      );
      addTearDown(container.dispose);
      return container.read(translationDownloadableProvider.future);
    }

    test('not on the phone, and the phone has the memory: yes', () async {
      expect(
        await downloadable(fits: true, status: ModelStatus.notDownloaded),
        isTrue,
      );
    });

    test('on the phone (translation off in M3, or a run that found '
        'nothing): no', () async {
      expect(
        await downloadable(fits: true, status: ModelStatus.ready),
        isFalse,
      );
      expect(
        await downloadable(fits: true, status: ModelStatus.updateAvailable),
        isFalse,
      );
    });

    test('below the memory floor: no, as M4 offers none', () async {
      expect(
        await downloadable(fits: false, status: ModelStatus.notDownloaded),
        isFalse,
      );
    });
  });

  test("#1233 D2's card asks in the learner's meaning languages, and closed, "
      'abandons what it asked', () async {
    final settings = StubSettings()
      ..put(SettingKeys.meaningPrimary, 'pl')
      ..put(SettingKeys.meaningSecondary, 'bn');
    final translations = _Translations(bare: (to) => 'x');
    final container = ProviderContainer(
      overrides: <Override>[
        settingsProvider.overrideWithValue(settings),
        translationRepositoryProvider.overrideWithValue(translations),
      ],
    );
    addTearDown(container.dispose);
    final card = outsideMeaningProvider('Bänken', sentence);
    final sub = container.listen(card, (_, _) {});
    await container.read(card.future);
    await pumpEventQueue();
    expect(container.read(card).value, <String, List<MeaningSuggestion>>{
      'pl': <MeaningSuggestion>[(meaning: 'x', here: false)],
      'bn': <MeaningSuggestion>[(meaning: 'x', here: false)],
    });
    var gone = false;
    unawaited(translations.abandoned.first!.then((_) => gone = true));
    sub.close();
    await pumpEventQueue();
    expect(gone, isTrue);
  });
}

/// Hy-MT2's files at [status], as the manifest names them.
class _Models extends Fake implements ModelRepository {
  _Models(this.status);

  final ModelStatus status;

  @override
  Future<ModelManifest> manifest() async =>
      ModelManifest(version: 1, models: <ModelEntry>[translationEntry]);

  @override
  Future<ModelState> stateOf(
    ModelEntry entry,
    ModelVariant variant, {
    bool sized = true,
  }) async => ModelState(
    entry: entry,
    variant: variant,
    status: status,
    bytesOnDisk: 0,
  );
}
