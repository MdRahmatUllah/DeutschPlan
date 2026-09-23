// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/features/study/study_screen.dart';
import 'package:deutschplan/features/study/study_session.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'golden_harness.dart';

/// T2 · the study session's shell — #100. The StudyFront artboard's place:
/// "Revise · 4 / 10", with seven new words behind it.
void main() {
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
    english: 'bill, invoice',
    searchKey: 'rechnung',
    searchKeyAlt: 'rechnung',
  );

  goldenTest(
    'study_shell',
    builder: (context) => ProviderScope(
      overrides: [
        studySessionProvider(args).overrideWith(_Fourth.new),
        studyWordProvider('r3').overrideWith(
          (ref) async => const WordWithState(
            word: rechnung,
            state: null,
            status: WordStatus.learning,
          ),
        ),
      ],
      child: StudyScreen(args: args),
    ),
  );
}

/// The session at its fourth revision.
class _Fourth extends StudySession {
  @override
  Future<StudySessionState> build(SessionArgs args) async => StudySessionState(
    items: <StudyItem>[
      for (final block in args.blocks)
        for (final uid in block.uids) StudyItem(block.kind, uid),
    ],
    position: 3,
  );
}
