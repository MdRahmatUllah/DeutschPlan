// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/repositories/course_meanings.dart';
import 'package:sogda/data/repositories/meaning_choice.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/data/repositories/word_repository.dart';
import 'package:sogda/domain/fsrs.dart' show Rating;
import 'package:sogda/features/study/study_back.dart';
import 'package:sogda/features/study/study_rating.dart';
import 'package:sogda/features/study/study_screen.dart';
import 'package:sogda/features/study/study_session.dart';
import 'package:sogda/router/routes.dart';

import 'golden_harness.dart';

/// T2 · StudyBack — #102. The artboard's card turned over: die Rechnung's
/// meanings, two examples, its collocations and register, and the rating
/// bar with its intervals (#105).
void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  setUpAll(() async {
    db = AppDatabase.memory();
    settings = SettingsRepository(db);
    await settings.load();
    // Still: nothing speaks while the frame is taken.
    await settings.write(SettingKeys.autoplayHeadword, false);
    await settings.write(SettingKeys.autoplayExample, false);
  });
  tearDownAll(() async {
    await settings.dispose();
    await db.close();
  });

  final args = SessionArgs(
    planDate: '2026-09-21',
    blocks: <SessionBlock>[
      SessionBlock(SessionBlockKind.revise, <String>[
        for (var i = 0; i < 10; i++) 'r$i',
      ]),
      SessionBlock(SessionBlockKind.newWords, <String>[
        for (var i = 0; i < 7; i++) 'n$i',
      ]),
    ],
  );
  const rechnung = Word(
    kind: 'vocab',
    uid: 'r3',
    sublevelCode: 'A2.1',
    levelCode: 'A2',
    seq: 1,
    seqInSublevel: 1,
    article: 'die',
    german: 'Rechnung',
    forms: 'Rechnungen',
    pos: 'noun',
    pronBn: 'রেশনুং',
    english: 'bill, invoice',
    bangla: 'বিল, চালান',
    collocations: 'die Rechnung bezahlen; eine Rechnung stellen',
    synonymsRegister: 'Im Restaurant auch: „Zahlen, bitte!“',
    searchKey: 'rechnung',
    searchKeyAlt: 'rechnung',
  );

  ProviderScope screen({
    bool russian = false,
    Set<String> updated = const <String>{},
    Map<Rating, int> intervals = const <Rating, int>{
      Rating.again: 1,
      Rating.hard: 3,
      Rating.good: 8,
      Rating.easy: 21,
    },
  }) => ProviderScope(
    overrides: [
      settingsProvider.overrideWithValue(settings),
      recentlyUpdatedProvider.overrideWith((ref) async => updated),
      studySessionProvider(args).overrideWith(_Fourth.new),
      studyIntervalsProvider('r3').overrideWith((ref) async => intervals),
      // #1119: Russian first and English second, from a course that ships
      // Russian.
      if (russian)
        meaningsProvider.overrideWithValue(
          const Meanings(
            MeaningChoice('ru', 'en'),
            CourseMeanings(<String, Map<String, WordMeaningText>>{
              'r3': <String, WordMeaningText>{
                'ru': (meaning: 'счёт', pronunciation: 'рЭхнунг'),
              },
            }),
          ),
        ),
      studyBackProvider('r3').overrideWith(
        (ref) async => (
          examples: <StudyExample>[
            (
              german: 'Ich habe die Rechnung noch nicht bezahlt.',
              translation: russian
                  ? 'Я ещё не оплатил счёт.'
                  : "I haven't paid the bill yet.",
            ),
            (
              german: 'Können wir bitte die Rechnung haben?',
              translation: russian
                  ? 'Можно нам счёт, пожалуйста?'
                  : 'Could we have the bill, please?',
            ),
          ],
          tip: russian
              ? const <String, String>{
                  'ru': 'die Rechnung — женский род, как «сумма», но не как «счёт».',
                }
              : null,
        ),
      ),
      studyWordProvider('r3').overrideWith(
        (ref) async => const WordWithState(
          word: rechnung,
          state: null,
          status: WordStatus.learning,
        ),
      ),
    ],
    child: StudyScreen(args: args),
  );

  goldenTest('study_back', builder: (_) => screen());
  goldenTest('study_back_ru_meanings', builder: (_) => screen(russian: true));
  // #1078: in Polish, as a Polish phone's first run shows it.
  goldenTest(
    'study_back_pl',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    textAudit: false,
    locale: const Locale('pl'),
    builder: (_) => screen(),
  );
  // #1079: in Russian: Cyrillic drawn, not boxes.
  goldenTest(
    'study_back_ru',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    textAudit: false,
    locale: const Locale('ru'),
    builder: (_) => screen(),
  );

  // #1155: at 200 %, "Хорошо" and "Trudne" are wider than a quarter of the
  // row: the rating bar is two rows of two, no label broken, and the
  // header's "4 / 10" stays together.
  for (final lang in const <String>['ru', 'pl']) {
    goldenTest(
      'study_back_${lang}_200',
      modes: const <GoldenMode>[GoldenMode.light],
      devices: const <GoldenDevice>[GoldenDevice.phone],
      textScale: 2,
      textAudit: false,
      locale: Locale(lang),
      builder: (_) => screen(),
    );
  }

  // BR-CONTENT-02: a meaning a course update changed this week.
  goldenTest(
    'study_back_updated',
    devices: <GoldenDevice>[GoldenDevice.phone],
    builder: (_) => screen(updated: <String>{'r3'}),
  );

  // #581: a mature word's intervals, past a thousand days. In Bangla at
  // 200 % "১,১১১ দি" wraps and the four buttons grow together (#580);
  // "1,111 d" fits, so only the audit's Bangla pass holds the rating bar's
  // minimum height.
  goldenTest(
    'study_back_mature',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    builder: (_) => screen(
      intervals: <Rating, int>{
        Rating.again: 1,
        Rating.hard: 45,
        Rating.good: 390,
        Rating.easy: 1111,
      },
    ),
  );
}

/// The session at its fourth revision, turned over.
class _Fourth extends StudySession {
  @override
  Future<StudySessionState> build(SessionArgs args) async => StudySessionState(
    items: <StudyItem>[
      for (final block in args.blocks)
        for (final uid in block.uids) StudyItem(block.kind, uid),
    ],
    position: 3,
    revealed: true,
  );
}
