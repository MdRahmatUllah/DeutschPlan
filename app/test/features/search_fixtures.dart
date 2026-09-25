import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/search_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/features/search/search_screen.dart';

/// One row of R1: a word with its state, meaning and tier.
SearchRow searchRow(
  String uid, {
  required String german,
  required String meaning,
  required SearchTier tier,
  String? article,
  String step = 'A1.1',
  WordStatus status = WordStatus.todo,
}) => (
  word: (
    word: WordWithState(
      word: Word(
        uid: uid,
        sublevelCode: step,
        levelCode: step.substring(0, 2),
        seq: 1,
        seqInSublevel: 1,
        article: article,
        german: german,
        english: meaning,
        searchKey: german.toLowerCase(),
        searchKeyAlt: german.toLowerCase(),
      ),
      state: null,
      status: status,
    ),
    meaning: meaning,
  ),
  tier: tier,
);

/// The Search artboard's results for "strase".
SearchView artboardSearch() => SearchView(
  words: <SearchRow>[
    searchRow(
      'strasse',
      article: 'die',
      german: 'Straße',
      meaning: 'street, road',
      tier: SearchTier.exact,
      status: WordStatus.done,
    ),
    searchRow(
      'strassenbahn',
      article: 'die',
      german: 'Straßenbahn',
      meaning: 'tram',
      tier: SearchTier.startsWith,
      step: 'A1.2',
      status: WordStatus.done,
    ),
    searchRow(
      'strassenverkehr',
      article: 'der',
      german: 'Straßenverkehr',
      meaning: 'road traffic',
      tier: SearchTier.startsWith,
      step: 'B1.1',
    ),
    searchRow(
      'strafe',
      article: 'die',
      german: 'Strafe',
      meaning: 'penalty, fine',
      tier: SearchTier.similar,
      step: 'A2.2',
    ),
  ],
  sentences: const <SentenceHit>[
    SentenceHit(
      wordUid: 'strasse',
      german: 'Die Straße ist wegen Bauarbeiten gesperrt.',
      english: 'The street is closed because of roadworks.',
      head: 'Straße',
      article: 'die',
      step: 'A1.1',
      runs: <(String, bool)>[
        ('Die ', false),
        ('Straße', true),
        (' ist wegen Bauarbeiten gesperrt.', false),
      ],
    ),
  ],
);

/// The SearchIdle artboard's recent searches, newest first.
const List<String> artboardRecent = <String>[
  'Rechnung',
  'umziehen',
  'Kaution',
  'strase',
  'Nebenkosten',
];

/// The SearchIdle artboard's three own words.
List<MyWord> artboardMyWords() => <MyWord>[
  (
    id: 1,
    article: 'das',
    german: 'Pfandflasche',
    meaning: 'deposit bottle',
    whereSeen: 'Rewe receipt',
    timesSeen: 3,
  ),
  (
    id: 2,
    article: 'die',
    german: 'Quittung',
    meaning: 'receipt',
    whereSeen: 'Bäckerei',
    timesSeen: 1,
  ),
  (
    id: 3,
    article: null,
    german: 'ausschließlich',
    meaning: 'exclusively',
    whereSeen: 'Mietvertrag',
    timesSeen: 1,
  ),
];

/// FR-R1-04's recents without a database.
class StubRecentSearches extends RecentSearches {
  StubRecentSearches(this.terms);

  final List<String> terms;

  @override
  List<String> build() => terms;
}
