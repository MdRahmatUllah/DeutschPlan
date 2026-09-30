import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/repositories/course_meanings.dart';
import 'package:sogda/data/repositories/meaning_choice.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/word_repository.dart';
import 'package:sogda/domain/fsrs.dart' show Rating;
import 'package:sogda/features/words/word_detail_screen.dart';

/// The WordDetail artboard's word: die Straße, A1.1, Done, due in eight days
/// from the artboards' Monday, 2026-09-21.
WordDetail artboardWordDetail({
  String uid = 'uid-strasse',
  String? article = 'die',
  String german = 'Straße',
  WordStatus status = WordStatus.done,
  MeaningLanguage meaning = MeaningLanguage.both,
  bool translate = false,
  String kind = 'vocab',
}) => WordDetail(
  meanings: Meanings(MeaningChoice.of(meaning)),
  pron: 'স্ট্রাসে',
  translate: translate,
  word: WordWithState(
    word: Word(
      kind: kind,
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
  examples: const <({String german, String? translation})>[
    (
      german: 'Die Straße ist wegen Bauarbeiten gesperrt.',
      translation: 'The street is closed because of roadworks.',
    ),
    (
      german: 'Wir wohnen in einer ruhigen Straße.',
      translation: 'We live on a quiet street.',
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
