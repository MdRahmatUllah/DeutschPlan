// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/features/study/study_screen.dart';
import 'package:deutschplan/features/study/study_session.dart';
import 'package:deutschplan/features/study/study_summary.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_harness.dart';

/// T3 · the session summary — #107. The artboard's sheet over the faded
/// session: "Gut gemacht!", 20 cards in 12 minutes, 2 · 3 · 10 · 5, two
/// words to watch, and the next step with the backlog under it.
void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  setUpAll(() async {
    db = AppDatabase.memory();
    settings = SettingsRepository(db);
    await settings.load();
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
        for (var i = 0; i < 10; i++) 'n$i',
      ]),
    ],
  );

  Word word(String uid, String article, String german) => Word(
    uid: uid,
    sublevelCode: 'A2.1',
    levelCode: 'A2',
    seq: 1,
    seqInSublevel: 1,
    article: article,
    german: german,
    english: german,
    searchKey: german.toLowerCase(),
    searchKeyAlt: german.toLowerCase(),
  );

  goldenTest(
    'study_summary',
    builder: (context) => ProviderScope(
      overrides: [
        settingsProvider.overrideWithValue(settings),
        studySessionProvider(args).overrideWith(_Done.new),
        studyNextProvider('2026-09-21').overrideWith(
          (ref) async => (sentences: 3, backlog: 14, dayDone: false),
        ),
        for (final (uid, article, german) in <(String, String, String)>[
          ('r0', 'die', 'Rechnung'),
          ('r1', 'der', 'Vermieter'),
        ])
          studyWordProvider(uid).overrideWith(
            (ref) async => WordWithState(
              word: word(uid, article, german),
              state: null,
              status: WordStatus.learning,
            ),
          ),
      ],
      child: StudyScreen(args: args),
    ),
  );
}

/// Twenty cards done in twelve minutes: 2 Again, 3 Hard, 10 Good, 5 Easy.
class _Done extends StudySession {
  @override
  Future<StudySessionState> build(SessionArgs args) async {
    final items = <StudyItem>[
      for (final block in args.blocks)
        for (final uid in block.uids) StudyItem(block.kind, uid),
    ];
    return StudySessionState(
      items: items,
      position: items.length,
      startedAt: DateTime.now().subtract(const Duration(minutes: 12)),
      results: <int, CardOutcome>{
        for (var i = 0; i < 20; i++)
          i: switch (i) {
            < 2 => CardOutcome.again,
            < 5 => CardOutcome.hard,
            < 15 => CardOutcome.good,
            _ => CardOutcome.easy,
          },
      },
    );
  }
}
