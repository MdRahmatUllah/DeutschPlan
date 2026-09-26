// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/fsrs.dart' show Rating;
import 'package:deutschplan/features/study/study_back.dart';
import 'package:deutschplan/features/study/study_rating.dart';
import 'package:deutschplan/features/study/study_screen.dart';
import 'package:deutschplan/features/study/study_session.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

  ProviderScope screen({Set<String> updated = const <String>{}}) =>
      ProviderScope(
        overrides: [
          settingsProvider.overrideWithValue(settings),
          recentlyUpdatedProvider.overrideWith((ref) async => updated),
          studySessionProvider(args).overrideWith(_Fourth.new),
          studyIntervalsProvider('r3').overrideWith(
            (ref) async => <Rating, int>{
              Rating.again: 1,
              Rating.hard: 3,
              Rating.good: 8,
              Rating.easy: 21,
            },
          ),
          studyBackProvider('r3').overrideWith(
            (ref) async => (
              examples: <StudyExample>[
                (
                  german: 'Ich habe die Rechnung noch nicht bezahlt.',
                  english: "I haven't paid the bill yet.",
                ),
                (
                  german: 'Können wir bitte die Rechnung haben?',
                  english: 'Could we have the bill, please?',
                ),
              ],
              tip: null,
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

  // BR-CONTENT-02: a meaning a course update changed this week.
  goldenTest(
    'study_back_updated',
    devices: <GoldenDevice>[GoldenDevice.phone],
    builder: (_) => screen(updated: <String>{'r3'}),
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
