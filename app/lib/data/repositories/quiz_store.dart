import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/data/repositories/course_meanings.dart';
import 'package:sogda/data/repositories/meaning_choice.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/data/repositories/word_repository.dart';
import 'package:sogda/domain/compare_set.dart';
import 'package:sogda/domain/plan_engine.dart' show planDate;
import 'package:sogda/domain/quiz_builder.dart';

/// The quiz builder's view of the course (`quiz-engine.md`, #81): the
/// queries in `word_queries.drift`, shaped into [QuizWord]s.
class DriftQuizStore implements QuizStore {
  DriftQuizStore(this._words, this._settings, this._content, [this._course]);

  final WordRepository _words;
  final SettingsRepository _settings;

  /// The course, for W2's sets: the app's one, so its forms index is built
  /// once.
  final ContentDao _content;

  /// The course's meanings beyond English and Bangla (#1120), read while the
  /// learner has chosen such a language; null otherwise, and the words carry
  /// only their own two.
  final Future<CourseMeanings>? _course;

  Future<CourseMeanings> get _meanings async =>
      await _course ?? CourseMeanings.none;

  @override
  Future<Map<String, List<QuizWord>>> sharedMeanings() =>
      _content.sharedMeanings();

  @override
  Future<List<QuizWord>> learned(QuizSource source, {String? ref}) async {
    final uids = source == QuizSource.compareSet
        ? <String>{
            for (final uid in (ref ?? '').split(','))
              if (uid.trim().isNotEmpty) uid.trim(),
          }
        : const <String>{};
    final category = int.tryParse(ref ?? '');
    final course = await _meanings;
    return <QuizWord>[
      for (final row in await _words.quizWords().get())
        if (switch (source) {
          QuizSource.stepLearned => row.step == ref,
          QuizSource.allLearned => true,
          QuizSource.category =>
            row.categoryId != null && row.categoryId == category,
          QuizSource.compareSet => uids.contains(row.uid),
        })
          QuizWord(
            uid: row.uid,
            german: row.german,
            english: row.english,
            step: row.step,
            article: row.article,
            pos: row.pos,
            bangla: row.bangla,
            forms: row.forms,
            synonyms: row.synonyms,
            stability: row.stability,
            lastReview: switch (row.reviewed) {
              final instant? => planDate(DateTime.parse(instant).toLocal()),
              null => null,
            },
            meanings: course.meaningsOf(row.uid),
          ),
      // FR-R2-04 (#363): the learner's own words, opted in, in all-learned
      // quizzes, and in a compare set that names them: L9's *Retry
      // mistakes* of such a quiz. Their meaning is the English one, as on T2.
      if (source == QuizSource.compareSet ||
          source == QuizSource.allLearned &&
              _settings.read(SettingKeys.quizCustomWords))
        for (final row in await _words.myQuizWords().get())
          if (source != QuizSource.compareSet ||
              uids.contains(customUid(row.id)))
            QuizWord(
              uid: customUid(row.id),
              german: row.german,
              english: row.meaning,
              step: row.step ?? '',
              article: row.article,
              stability: row.stability,
              lastReview: switch (row.reviewed) {
                final instant? => planDate(DateTime.parse(instant).toLocal()),
                null => null,
              },
            ),
    ];
  }

  @override
  Future<List<QuizWord>> stepWords(String step) async {
    final course = await _meanings;
    return <QuizWord>[
      for (final row in await _words.quizPool(step).get())
        QuizWord(
          uid: row.uid,
          german: row.german,
          english: row.english,
          step: row.step,
          article: row.article,
          pos: row.pos,
          bangla: row.bangla,
          synonyms: row.synonyms,
          meanings: course.meaningsOf(row.uid),
        ),
    ];
  }

  /// W2's set in the learner's first language (#1120), as W2 shows it.
  @override
  Future<CompareSet?> compareSet(String uid) =>
      _content.compareSet(uid, lang: meaningChoiceOf(_settings).primary);
}
