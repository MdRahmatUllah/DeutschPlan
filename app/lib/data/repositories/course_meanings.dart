import 'package:sogda/data/db/content_dao.dart';

/// A word's text in one meaning language (#1080's `word_meanings`).
typedef WordMeaningText = ({String meaning, String? pronunciation});

/// #1081: every meaning and pronunciation the course ships, by word and
/// language. Read once: a list's rows (L2, L6, R1, T4) each show a meaning,
/// and a query for each row would cost a list its scroll.
class CourseMeanings {
  const CourseMeanings(this._byWord);

  /// Nothing yet: a word falls back to its own English and Bangla.
  static const CourseMeanings none = CourseMeanings(
    <String, Map<String, WordMeaningText>>{},
  );

  final Map<String, Map<String, WordMeaningText>> _byWord;

  /// [uid]'s meaning in [lang], or null where the course has none: a word of
  /// the learner's own, or a language that didn't ship.
  String? meaning(String uid, String lang) => _byWord[uid]?[lang]?.meaning;

  /// [uid]'s pronunciation guide in [lang]'s script, or null where there is
  /// none (English's, until #1082).
  String? pronunciation(String uid, String lang) =>
      _byWord[uid]?[lang]?.pronunciation;
}

/// The course's meanings, read once per content database.
// ponytail: kept while the database is open, as `course_text.dart` does, so a
// course update reaches it on the next start; key it by the content version
// if that must be sooner.
Future<CourseMeanings> loadCourseMeanings(ContentDao dao) async {
  final cached = _loaded[dao.attachedDatabase];
  if (cached != null) return cached;
  final loading = _load(dao);
  _loaded[dao.attachedDatabase] = loading;
  try {
    return await loading;
  } on Object {
    // A read that failed is tried again, not remembered.
    _loaded[dao.attachedDatabase] = null;
    rethrow;
  }
}

final Expando<Future<CourseMeanings>> _loaded =
    Expando<Future<CourseMeanings>>();

Future<CourseMeanings> _load(ContentDao dao) async {
  final byWord = <String, Map<String, WordMeaningText>>{};
  for (final row in await dao.allWordMeanings().get()) {
    (byWord[row.wordUid] ??= <String, WordMeaningText>{})[row.lang] = (
      meaning: row.meaning,
      pronunciation: row.pronunciation,
    );
  }
  return CourseMeanings(byWord);
}
