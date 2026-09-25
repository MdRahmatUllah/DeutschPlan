import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/fsrs.dart' show Rating;
import 'package:deutschplan/features/words/word_detail_screen.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// The WordDetail artboard's word: die Straße, A1.1, Done, due in eight days
/// from the artboards' Monday, 2026-09-21.
WordDetail artboardWordDetail({
  String uid = 'uid-strasse',
  String? article = 'die',
  String german = 'Straße',
  WordStatus status = WordStatus.done,
  MeaningLanguage meaning = MeaningLanguage.both,
  bool translate = false,
}) => WordDetail(
  meaning: meaning,
  pron: true,
  translate: translate,
  word: WordWithState(
    word: Word(
      uid: uid,
      sublevelCode: 'A1.1',
      levelCode: 'A1',
      seq: 1,
      seqInSublevel: 1,
      article: article,
      german: german,
      forms: '-n',
      pos: 'noun',
      pronBn: 'স্ট্রাসে',
      english: 'street, road',
      bangla: 'রাস্তা',
      collocations: 'die Straße überqueren; auf der Straße; die Straße entlang',
      synonymsRegister: 'Gasse = narrow street · Weg = path, way',
      searchKey: 'strasse',
      searchKeyAlt: 'strasse',
    ),
    state: WordStateData(
      wordUid: uid,
      status: status.name,
      introducedOn: '2026-09-01',
      due: '2026-09-29',
      stability: 30,
      difficulty: 5,
      reps: 5,
      lapses: 0,
      fsrsState: 2,
      lastReview: '2026-09-21T08:00:00Z',
      cardMode: 'plain',
      cardModeManual: 0,
      timesLogged: 0,
    ),
    status: status,
  ),
  examples: const <({String german, String? english})>[
    (
      german: 'Die Straße ist wegen Bauarbeiten gesperrt.',
      english: 'The street is closed because of roadworks.',
    ),
    (
      german: 'Wir wohnen in einer ruhigen Straße.',
      english: 'We live on a quiet street.',
    ),
  ],
);

/// "reviewed 5 times · last: Good".
const ReviewHistory artboardHistory = (reviews: 5, last: Rating.good);

/// W1 without a database: every uid is the artboard's word.
List<Override> wordStub() => <Override>[
  wordDetailProvider.overrideWith(
    (ref, uid) => Stream.value(artboardWordDetail(uid: uid)),
  ),
  wordHistoryProvider.overrideWith((ref, uid) => Stream.value(artboardHistory)),
];
