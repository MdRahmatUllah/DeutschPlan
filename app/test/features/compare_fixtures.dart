import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/compare_set.dart';
import 'package:deutschplan/features/today/today_providers.dart';
import 'package:deutschplan/features/words/compare_screen.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// A course word To do, for *Add all*.
WordWithState compareWord(String uid, String german, String? article) =>
    WordWithState(
      word: Word(
        uid: uid,
        sublevelCode: 'C1.1',
        levelCode: 'C1',
        seq: 1,
        seqInSublevel: 1,
        article: article,
        german: german,
        english: german,
        searchKey: german.toLowerCase(),
        searchKeyAlt: german.toLowerCase(),
      ),
      state: null,
      status: WordStatus.todo,
    );

/// The Compare artboard's set: der Grund · die Ursache · der Anlass, C1.1,
/// every cell filled, all three To do.
CompareView artboardCompare({
  List<CompareMember>? members,
  List<WordWithState>? todo,
  int quizItems = 5,
}) => CompareView(
  set: const CompareWord(
    uid: 'set-grund',
    german: 'Grund / Ursache / Anlass',
    english: 'reason / cause / trigger',
    step: 'C1.1',
  ),
  members: members ?? artboardMembers,
  todo:
      todo ??
      <WordWithState>[
        compareWord('uid-grund', 'Grund', 'der'),
        compareWord('uid-ursache', 'Ursache', 'die'),
        compareWord('uid-anlass', 'Anlass', 'der'),
      ],
  quizItems: quizItems,
);

const List<CompareMember> artboardMembers = <CompareMember>[
  CompareMember(
    headword: 'Grund',
    article: 'der',
    uid: 'uid-grund',
    step: 'C1.1',
    meaning: 'reason, ground',
    register: <String>['neutral'],
    withText: 'aus · ohne + Akk.',
    useWhen: 'the everyday word: a reason for something',
    examples: <CompareExample>[
      (german: 'Aus diesem Grund bleibe ich zu Hause.', english: null),
    ],
  ),
  CompareMember(
    headword: 'Ursache',
    article: 'die',
    uid: 'uid-ursache',
    step: 'C1.1',
    meaning: 'cause',
    register: <String>['neutral / technical'],
    withText: 'für + Akk.',
    useWhen: 'what actually caused an event',
    examples: <CompareExample>[
      (german: 'Die Ursache des Feuers ist unklar.', english: null),
    ],
  ),
  CompareMember(
    headword: 'Anlass',
    article: 'der',
    uid: 'uid-anlass',
    step: 'C1.1',
    meaning: 'occasion, cause',
    register: <String>['formal'],
    withText: 'zu + Dat. · aus + Dat.',
    useWhen: 'the trigger or occasion for an action',
    examples: <CompareExample>[
      (german: 'Aus Anlass des Jubiläums gab es ein Fest.', english: null),
    ],
  ),
];

/// W2 without a database: the artboard's set for every uid, and [open] as
/// today's plan — nothing, unless a test says so.
List<Override> compareStub({
  CompareView? view,
  Set<(String, String)> open = const <(String, String)>{},
}) => <Override>[
  compareViewProvider.overrideWith(
    (ref, uid) => Stream.value(view ?? artboardCompare()),
  ),
  todayOpenProvider.overrideWith((ref) => Stream.value(open)),
];
