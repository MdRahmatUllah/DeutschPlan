// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/features/study/study_screen.dart';
import 'package:deutschplan/features/study/study_session.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show BuildContext, Widget;

import 'golden_harness.dart';

/// T2 · StudyFront — #101, in the shell from #100. The artboard's card:
/// "Revise · 4 / 10", die Rechnung, with seven new words behind it.
void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  setUpAll(() async {
    db = AppDatabase.memory();
    settings = SettingsRepository(db);
    await settings.load();
    // Still: nothing speaks while the frame is taken.
    await settings.write(SettingKeys.autoplayHeadword, false);
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
    searchKey: 'rechnung',
    searchKeyAlt: 'rechnung',
  );

  Widget card(Word word) => ProviderScope(
    overrides: [
      settingsProvider.overrideWithValue(settings),
      studySessionProvider(args).overrideWith(_Fourth.new),
      studyWordProvider('r3').overrideWith(
        (ref) async =>
            WordWithState(word: word, state: null, status: WordStatus.learning),
      ),
    ],
    child: StudyScreen(args: args),
  );
  Widget front(BuildContext context) => card(rechnung);

  goldenTest('study_front', builder: front);
  // #165: at 200 % text.
  goldenTest(
    'study_front_200',
    builder: front,
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    textScale: 2,
    textAudit: false,
  );
  // #419: a headword broken at a syllable shows its "-": at 200 %, as a
  // learner with large text sees it. Its pronunciation, too wide for its
  // line, breaks between aksharas (#504).
  goldenTest(
    'study_front_hyphen_200',
    builder: (context) => card(
      const Word(
        uid: 'r3',
        sublevelCode: 'B1.2',
        levelCode: 'B1',
        seq: 1,
        seqInSublevel: 1,
        article: 'die',
        german: 'Geschwindigkeitsbegrenzung',
        forms: 'Geschwindigkeitsbegrenzungen',
        pos: 'noun',
        pronBn: 'গেশ্ভিন্ডিশকাইট্‌সবেগ্রেন্‌ৎসুং',
        english: 'speed limit',
        searchKey: 'geschwindigkeitsbegrenzung',
        searchKeyAlt: 'geschwindigkeitsbegrenzung',
      ),
    ),
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    textScale: 2,
  );
  // #502: its caption too, with the Bangla pronunciation among the German.
  goldenTest(
    'study_front_hyphen_bn_200',
    builder: (context) => card(
      const Word(
        uid: 'r3',
        sublevelCode: 'B1.1',
        levelCode: 'B1',
        seq: 1,
        seqInSublevel: 1,
        article: 'die',
        german: 'Geschwindigkeit',
        forms: 'Geschwindigkeiten',
        pos: 'noun',
        pronBn: 'গেশ্ভিন্ডিশকাইট',
        english: 'speed',
        searchKey: 'geschwindigkeit',
        searchKeyAlt: 'geschwindigkeit',
      ),
    ),
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    textScale: 2,
  );

  // #363: a word of the learner's own, fourth in the same Revise block. Its
  // chip says so where a course word's names its step.
  final mine = SessionArgs(
    planDate: '2026-09-21',
    blocks: <SessionBlock>[
      SessionBlock(SessionBlockKind.revise, <String>[
        for (var i = 0; i < 10; i++) i == 3 ? 'custom:1' : 'r$i',
      ]),
    ],
  );
  goldenTest(
    'study_front_my_word',
    builder: (context) => ProviderScope(
      overrides: [
        settingsProvider.overrideWithValue(settings),
        studySessionProvider(mine).overrideWith(_Fourth.new),
        studyWordProvider('custom:1').overrideWith(
          (ref) async => const WordWithState(
            word: Word(
              uid: 'custom:1',
              sublevelCode: '',
              levelCode: '',
              seq: 0,
              seqInSublevel: 0,
              article: 'das',
              german: 'Pfand',
              english: 'deposit (on bottles)',
              searchKey: '',
              searchKeyAlt: '',
            ),
            state: null,
            status: WordStatus.learning,
          ),
        ),
      ],
      child: StudyScreen(args: mine),
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
