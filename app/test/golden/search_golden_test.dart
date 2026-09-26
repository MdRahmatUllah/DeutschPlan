import 'package:deutschplan/data/repositories/search_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/features/search/search_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../features/search_fixtures.dart';
import '../services/fake_tts.dart';
import 'golden_harness.dart';

/// R1 · Search — #137. The artboard's "strase": die Straße as the exact
/// match, two that start with it, die Strafe as a typo, and a sentence.
void main() {
  goldenTest(
    'search',
    overrides: [
      searchResultsProvider.overrideWith(
        (ref, query) => Stream.value(artboardSearch()),
      ),
      recentSearchesProvider.overrideWith(() => StubRecentSearches(const [])),
      myWordsProvider.overrideWith((ref) => Stream.value(const <MyWord>[])),
      fakeVoice(FakeTts()),
    ],
    builder: (_) => const SearchScreen(),
    act: (tester) async {
      await tester.enterText(find.byType(TextField), 'strase');
      await tester.pump(SearchScreen.debounce);
      await tester.pumpAndSettle();
    },
  );

  // #138: nothing typed. The SearchIdle artboard's five recents and three
  // own words.
  goldenTest(
    'search_idle',
    overrides: [
      recentSearchesProvider.overrideWith(
        () => StubRecentSearches(artboardRecent),
      ),
      myWordsProvider.overrideWith((ref) => Stream.value(artboardMyWords())),
      fakeVoice(FakeTts()),
    ],
    builder: (_) => const SearchScreen(),
  );

  // #139: the SearchNone artboard's "Wohnungsgeberbestätigung", not in the
  // course's 5,594 words.
  goldenTest(
    'search_none',
    overrides: [
      searchResultsProvider.overrideWith(
        (ref, query) => Stream.value(
          const SearchView(words: <SearchRow>[], sentences: <SentenceHit>[]),
        ),
      ),
      courseWordsProvider.overrideWith((ref) async => 5594),
      recentSearchesProvider.overrideWith(() => StubRecentSearches(const [])),
      myWordsProvider.overrideWith((ref) => Stream.value(const <MyWord>[])),
      fakeVoice(FakeTts()),
    ],
    builder: (_) => const SearchScreen(),
    act: (tester) async {
      await tester.enterText(
        find.byType(TextField),
        'Wohnungsgeberbestätigung',
      );
      await tester.pump(SearchScreen.debounce);
      await tester.pumpAndSettle();
    },
  );

  // #396, #516: the same search, a word the learner saved already. Offered
  // to open, its *Open* button breaking at syllables above 100 %, as *Add*
  // does: the text audit checks it at 150 and 200 %.
  goldenTest(
    'search_none_mine',
    overrides: [
      searchResultsProvider.overrideWith(
        (ref, query) => Stream.value(
          const SearchView(words: <SearchRow>[], sentences: <SentenceHit>[]),
        ),
      ),
      courseWordsProvider.overrideWith((ref) async => 5594),
      recentSearchesProvider.overrideWith(() => StubRecentSearches(const [])),
      myWordsProvider.overrideWith(
        (ref) => Stream.value(const <MyWord>[
          (
            id: 7,
            article: 'die',
            german: 'Wohnungsgeberbestätigung',
            meaning: "landlord's confirmation",
            whereSeen: 'Bürgeramt',
            timesSeen: 1,
          ),
        ]),
      ),
      fakeVoice(FakeTts()),
    ],
    builder: (_) => const SearchScreen(),
    act: (tester) async {
      await tester.enterText(
        find.byType(TextField),
        'Wohnungsgeberbestätigung',
      );
      await tester.pump(SearchScreen.debounce);
      await tester.pumpAndSettle();
    },
  );
}
