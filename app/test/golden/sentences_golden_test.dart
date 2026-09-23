// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/domain/sentence_picker.dart';
import 'package:deutschplan/features/sentences/sentences_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_harness.dart';

/// T5 · Practice sentences — #110. The artboard: "Sentence 1 of 3", die
/// Nebenkosten underlined in Raspberry, the play button, the translation
/// shown, and the three answers.
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

  goldenTest(
    'sentences',
    builder: (context) => ProviderScope(
      overrides: [
        settingsProvider.overrideWithValue(settings),
        practiceSentencesProvider.overrideWith(_Artboard.new),
      ],
      child: const SentencesScreen(),
    ),
    act: (tester) async {
      await tester.tap(find.text('Show translation'));
    },
  );
}

class _Artboard extends PracticeSentences {
  static const Word _nebenkosten = Word(
    uid: 'nebenkosten',
    sublevelCode: 'A2.1',
    levelCode: 'A2',
    seq: 1,
    seqInSublevel: 1,
    article: 'die',
    german: 'Nebenkosten',
    pos: 'noun',
    english: 'utility costs',
    searchKey: 'nebenkosten',
    searchKeyAlt: 'nebenkosten',
  );

  @override
  Future<List<PracticeSentence>> build() async => const <PracticeSentence>[
    PracticeSentence(
      sentence: SentenceCandidate(
        wordUid: 'nebenkosten',
        ord: 1,
        german: 'Der Vermieter hat die Nebenkosten für nächstes Jahr erhöht.',
        english: 'The landlord has raised the utility costs for next year.',
      ),
      word: _nebenkosten,
    ),
    PracticeSentence(
      sentence: SentenceCandidate(
        wordUid: 'miete',
        ord: 1,
        german: 'Die Miete ist hoch.',
        english: 'The rent is high.',
      ),
    ),
    PracticeSentence(
      sentence: SentenceCandidate(
        wordUid: 'keller',
        ord: 1,
        german: 'Der Keller ist kalt.',
        english: 'The cellar is cold.',
      ),
    ),
  ];
}
