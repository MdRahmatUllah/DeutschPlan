import 'package:flutter/foundation.dart' show immutable;
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/data/repositories/meaning_choice.dart';

/// A meaning language the course ships (`course_languages`), named in
/// itself as a learner looks for it: English, বাংলা, Русский.
typedef CourseLanguageName = ({String code, String ownName});

/// English and Bangla, which every course ships: the pickers' list while the
/// course's own is not read, or on one without the table.
const List<CourseLanguageName> baseLanguages = <CourseLanguageName>[
  (code: 'en', ownName: 'English'),
  (code: 'bn', ownName: 'বাংলা'),
];

/// [code]'s own name in [languages], or the code where the list has none.
String ownNameOf(String code, List<CourseLanguageName> languages) {
  for (final language in languages) {
    if (language.code == code) return language.ownName;
  }
  return code;
}

/// #1128: the course's category names in the primary meaning language, by
/// their English name. A category the language has none for stays English.
class CategoryNames {
  const CategoryNames(this._byEnglish);

  /// English's, the course's own: nothing to change.
  static const CategoryNames none = CategoryNames(<String, String>{});

  final Map<String, String> _byEnglish;

  /// [english]'s name in the language, or [english] itself.
  String of(String english) => _byEnglish[english] ?? english;
}

/// A pronunciation guide and the language it is written for: the key under
/// it is that language's (#1122).
typedef PronGuide = ({String lang, String text});

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

  /// How many words have a meaning.
  int get length => _byWord.length;

  /// [uid]'s meaning in [lang], or null where the course has none: a word of
  /// the learner's own, or a language that didn't ship.
  String? meaning(String uid, String lang) => _byWord[uid]?[lang]?.meaning;

  /// [uid]'s meanings in the languages beyond English and Bangla, whose
  /// source is still the word's own row ([Meanings.of]): what a quiz in them
  /// asks (#1120).
  Map<String, String> meaningsOf(String uid) => <String, String>{
    for (final MapEntry(key: lang, value: text)
        in (_byWord[uid] ?? const <String, WordMeaningText>{}).entries)
      if (lang != 'en' && lang != 'bn') lang: text.meaning,
  };

  /// [uid]'s pronunciation guide in [lang]'s script, or null where there is
  /// none (English's, until #1082).
  String? pronunciation(String uid, String lang) =>
      _byWord[uid]?[lang]?.pronunciation;
}

/// #1081: a word's meanings in the learner's languages. T2's card, W1, the
/// lists' rows and the home-screen widget show a word through it.
@immutable
class Meanings {
  const Meanings(this.choice, [this.course = CourseMeanings.none]);

  final MeaningChoice choice;

  /// The languages beyond English and Bangla; [CourseMeanings.none] while
  /// the choice has none.
  final CourseMeanings course;

  /// [word]'s meaning in [lang], or null where the course has none.
  // ponytail: English and Bangla from the word's own row, which the pipeline
  // fills from the same columns and a learner's own word has alone. #1096
  // reads them from `word_meanings` when it drops the columns.
  String? of(Word word, String lang) => switch (lang) {
    'en' => word.english,
    'bn' => word.bangla,
    _ => course.meaning(word.uid, lang),
  };

  /// The meanings shown, primary first: English where the primary has none,
  /// as a Bangla-only learner has always had it, then the secondary's where
  /// it has one.
  List<({String lang, String text})> lines(Word word) {
    final primary = of(word, choice.primary);
    final first = primary == null
        ? (lang: 'en', text: word.english)
        : (lang: choice.primary, text: primary);
    final code = choice.secondary;
    final second = code == null || code == first.lang ? null : of(word, code);
    return <({String lang, String text})>[
      first,
      if (second != null) (lang: code!, text: second),
    ];
  }

  /// [lines] on one line, for a list's row or a sheet: "table · টেবিল"
  /// (#689 TD-15).
  String line(Word word) =>
      <String>[for (final l in lines(word)) l.text].join(' · ');

  /// The pronunciation guide: the primary's, or the secondary's where the
  /// primary has none (English's, until #1082). Bangla's only while [bangla]
  /// (`show_pron_bn`, the learner's choice within Bangla, #1077).
  PronGuide? pronunciation(Word word, {required bool bangla}) {
    for (final lang in choice.languages) {
      final guide = lang == 'bn'
          ? (bangla ? word.pronBn : null)
          : course.pronunciation(word.uid, lang);
      if (guide != null && guide.isNotEmpty) return (lang: lang, text: guide);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is Meanings &&
      other.choice == choice &&
      identical(other.course, course);

  @override
  int get hashCode => Object.hash(choice, identityHashCode(course));
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
