import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart'
    show DatabaseConnection, Table, TableInfo, Variable;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/data/repositories/meaning_choice.dart';
import 'package:sogda/data/repositories/plan_store.dart';
import 'package:sogda/data/repositories/sentence_store.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/domain/plan_engine.dart' show PlanDate;
import 'package:sogda/domain/sentence_picker.dart';

import '../db/content_fixture.dart';

/// The sentence picker's drift side — #80.
void main() {
  late Directory directory;
  late AppDatabase db;
  late DriftSentenceStore store;
  const today = '2026-09-21';

  setUp(() async {
    directory = tempDir('sogda_sentences');
    final content = ContentFixture.write(
      '${directory.path}/content.db',
      russian: true,
    ).file;
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
    );
    store = DriftSentenceStore(db);
    // Haus and Tür learned; Straße suspended.
    await db.customStatement('''
INSERT INTO word_state (word_uid, status, introduced_on) VALUES
  ('${ContentFixture.haus}', 'learning', '2026-09-01'),
  ('${ContentFixture.tuer}', 'done', '2026-09-01'),
  ('${ContentFixture.strasse}', 'suspended', '2026-09-01')
''');
  });

  tearDown(() async {
    await db.close();
  });

  Future<Set<(String, int)>> candidates({int gap = 14}) async =>
      <(String, int)>{
        for (final c in await store.candidates(today, gapDays: gap))
          (c.wordUid, c.ord),
      };

  test("candidates are learned words' examples, not suspended ones", () async {
    expect(await candidates(), <(String, int)>{
      (ContentFixture.haus, 1),
      (ContentFixture.haus, 2),
      (ContentFixture.tuer, 1),
    });
  });

  test("#1119 a sentence's translation is in the primary meaning language, "
      'English where it has none, the day it was shown too', () async {
    var lang = 'ru';
    final russian = DriftSentenceStore(db, () => lang);
    Future<Map<(String, int), String?>> translations() async => {
      for (final c in await russian.candidates(today, gapDays: 14))
        (c.wordUid, c.ord): c.translation,
    };
    expect(await translations(), <(String, int), String?>{
      (ContentFixture.haus, 1): 'Дом большой.',
      (ContentFixture.haus, 2): null,
      (ContentFixture.tuer, 1): 'The door is open.',
    });

    final picked = await russian.candidates(today, gapDays: 14);
    await russian.record(today, picked);
    expect([
      for (final c in await russian.shownOn(today)) c.translation,
    ], contains('Дом большой.'));
    lang = 'bn';
    expect(
      [for (final c in await russian.shownOn(today)) c.translation],
      contains('The house is big.'),
      reason: 'no Bangla sentences: English (#598)',
    );
  });

  test(
    "#1119 the app's store reads in the learner's first meaning language",
    () async {
      final settings = SettingsRepository(db);
      await settings.load();
      addTearDown(settings.dispose);
      final container = ProviderContainer(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWithValue(settings),
        ],
      );
      addTearDown(container.dispose);
      await writeMeaningChoice(settings, const MeaningChoice('ru', 'en'));
      final haus =
          (await container
                  .read(sentenceStoreProvider)
                  .candidates(today, gapDays: 14))
              .firstWhere(
                (c) => c.wordUid == ContentFixture.haus && c.ord == 1,
              );
      expect(haus.translation, 'Дом большой.');
    },
  );

  test(
    "#325 a candidate carries its word's German and part of speech",
    () async {
      final haus = (await store.candidates(
        today,
        gapDays: 14,
      )).firstWhere((c) => c.wordUid == ContentFixture.haus);
      expect((haus.headword, haus.pos), ('Haus', 'noun'));
    },
  );

  test("#870 and its forms, where the underline is looked for too", () async {
    await db.customStatement(
      "UPDATE c.words SET forms = 'Häuser' WHERE uid = '${ContentFixture.haus}'",
    );
    final haus = (await store.candidates(
      today,
      gapDays: 14,
    )).firstWhere((c) => c.wordUid == ContentFixture.haus);
    expect(haus.forms, 'Häuser');
  });

  test('a sentence shown within the gap is left out', () async {
    await db.customStatement(
      "INSERT INTO sentence_log (word_uid, ord, shown_on) VALUES "
      "('${ContentFixture.haus}', 1, '2026-09-10')",
    );
    expect(await candidates(), isNot(contains((ContentFixture.haus, 1))));
    expect(await candidates(), contains((ContentFixture.haus, 2)));
  });

  test('and back once the gap has passed', () async {
    // Shown on the 7th: fourteen days before the 21st, so not within them.
    await db.customStatement(
      "INSERT INTO sentence_log (word_uid, ord, shown_on) VALUES "
      "('${ContentFixture.haus}', 1, '2026-09-07')",
    );
    expect(await candidates(), contains((ContentFixture.haus, 1)));
    expect(
      await candidates(gap: 15),
      isNot(contains((ContentFixture.haus, 1))),
    );
  });

  test('the learned keys are the search keys', () async {
    expect(await store.learnedKeys(), <String>{'haus', 'tuer'});
  });

  test('what is recorded reads back in order, with its sentence', () async {
    final picked = <SentenceCandidate>[
      const SentenceCandidate(wordUid: ContentFixture.tuer, ord: 1, german: ''),
      const SentenceCandidate(wordUid: ContentFixture.haus, ord: 2, german: ''),
    ];
    await store.record(today, picked);

    final shown = await store.shownOn(today);
    expect(shown, picked);
    expect(shown.first.german, 'Die Tür ist offen.');
    expect(await store.shownOn('2026-09-22'), isEmpty);
  });

  test('#750 FR-T5-01 a day recorded already keeps its set', () async {
    const tuer = SentenceCandidate(
      wordUid: ContentFixture.tuer,
      ord: 1,
      german: '',
    );
    const haus = SentenceCandidate(
      wordUid: ContentFixture.haus,
      ord: 1,
      german: '',
    );
    expect(await store.record(today, const <SentenceCandidate>[tuer]), [tuer]);

    expect(await store.record(today, const <SentenceCandidate>[haus]), [tuer]);
    expect(await store.shownOn(today), <SentenceCandidate>[tuer]);
  });

  test('#750 FR-T5-01 two picks that race record one set: the second read '
      'the day empty before the first wrote', () async {
    final gate = Completer<void>();
    final second = SentencePicker(
      _ReadsEarly(store, gate.future),
      count: 1,
      gapDays: 14,
    ).forDay(today);
    final first = await SentencePicker(
      store,
      count: 1,
      gapDays: 14,
    ).forDay(today);
    gate.complete();

    expect(await second, first);
    expect(await store.shownOn(today), first);
  });

  test("today's rated count follows the ratings", () async {
    await store.record(today, <SentenceCandidate>[
      const SentenceCandidate(wordUid: ContentFixture.tuer, ord: 1, german: ''),
      const SentenceCandidate(wordUid: ContentFixture.haus, ord: 1, german: ''),
    ]);
    final counts = <int>[];
    final subscription = store.watchRated(today).listen(counts.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    await db.customUpdate(
      "UPDATE sentence_log SET self_rating = 3 "
      "WHERE word_uid = '${ContentFixture.tuer}'",
      updates: <TableInfo<Table, Object?>>{db.sentenceLog},
    );
    await pumpEventQueue();

    expect(counts, <int>[0, 1]);
  });

  group('#659 a rated sentence is a day studied', () {
    const tuer = SentenceCandidate(
      wordUid: ContentFixture.tuer,
      ord: 1,
      german: '',
    );
    const haus = SentenceCandidate(
      wordUid: ContentFixture.haus,
      ord: 1,
      german: '',
    );

    Future<int> sentencesDone() async {
      final rows = await db
          .customSelect(
            'SELECT sentences_done AS n FROM daily_stats WHERE day = ?',
            variables: <Variable<Object>>[Variable<String>(today)],
          )
          .get();
      return rows.isEmpty ? 0 : rows.single.read<int>('n');
    }

    setUp(() => store.record(today, const <SentenceCandidate>[tuer, haus]));

    test(
      "#659 each sentence counts once in the day's sentences_done",
      () async {
        await store.rate(today, tuer, 3);
        await store.rate(today, tuer, 2); // a changed answer, not another
        await store.rate(today, haus, 1);

        expect(await sentencesDone(), 2);
      },
    );

    test(
      '#659 BR-PLAN-10 and a day of sentences alone keeps the streak',
      () async {
        // New words paused, nothing due: the sentences are the day's activity.
        final settings = SettingsRepository(db);
        await settings.load();
        addTearDown(settings.dispose);
        final plans = DriftPlanStore(db, settings);
        expect(await plans.activeDays(today, lookbackDays: 7), isEmpty);

        await store.rate(today, tuer, 3);

        expect(await plans.activeDays(today, lookbackDays: 7), <String>{today});
      },
    );

    test('#662 BR-FSRS-04 the word is rated with the first answer only: '
        'Not yet again, or after a change, rates nothing more', () async {
      var hard = 0;
      Future<void> rateHard() async => hard++;

      await store.rate(today, tuer, 1, andThen: rateHard);
      await store.rate(today, tuer, 1, andThen: rateHard);
      await store.rate(today, tuer, 3);
      await store.rate(today, tuer, 1, andThen: rateHard);
      expect(hard, 1);
      expect(await store.ratings(today), <(String, int), int>{
        (ContentFixture.tuer, 1): 1,
      });

      await store.rate(today, haus, 3);
      await store.rate(today, haus, 1, andThen: rateHard);
      expect(hard, 1, reason: 'a changed answer changes the sentence only');
    });

    test('#659 and a rating that fails counts nothing', () async {
      await expectLater(
        store.rate(today, tuer, 3, andThen: () => throw StateError('disk')),
        throwsStateError,
      );

      expect(await sentencesDone(), 0);
    });
  });
}

/// A store whose [shownOn] read is answered only once [gate] opens: a pick
/// that read the day before another pick wrote it (#750).
class _ReadsEarly implements SentenceStore {
  _ReadsEarly(this._store, this._gate);

  final SentenceStore _store;
  final Future<void> _gate;

  @override
  Future<List<SentenceCandidate>> shownOn(PlanDate date) async {
    final shown = await _store.shownOn(date);
    await _gate;
    return shown;
  }

  @override
  Future<List<SentenceCandidate>> candidates(
    PlanDate today, {
    required int gapDays,
  }) => _store.candidates(today, gapDays: gapDays);

  @override
  Future<Set<String>> learnedKeys() => _store.learnedKeys();

  @override
  Future<List<SentenceCandidate>> record(
    PlanDate date,
    List<SentenceCandidate> picked,
  ) => _store.record(date, picked);
}
