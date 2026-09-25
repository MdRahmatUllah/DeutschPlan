import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/plan_engine.dart' show planDate;
import 'package:deutschplan/domain/quiz_builder.dart';

/// The quiz builder's view of the course (`quiz-engine.md`, #81): the
/// queries in `word_queries.drift`, shaped into [QuizWord]s.
class DriftQuizStore implements QuizStore {
  DriftQuizStore(this._words, this._settings);

  final WordRepository _words;
  final SettingsRepository _settings;

  @override
  Future<List<QuizWord>> learned(QuizSource source, {String? ref}) async {
    final uids = source == QuizSource.compareSet
        ? <String>{
            for (final uid in (ref ?? '').split(','))
              if (uid.trim().isNotEmpty) uid.trim(),
          }
        : const <String>{};
    final category = int.tryParse(ref ?? '');
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
          ),
      // FR-R2-04 (#363): the learner's own words, opted in, and only in
      // all-learned quizzes. Their meaning is the English one, as on T2.
      if (source == QuizSource.allLearned &&
          _settings.read(SettingKeys.quizCustomWords))
        for (final row in await _words.myQuizWords().get())
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
  Future<List<QuizWord>> stepWords(String step) async => <QuizWord>[
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
      ),
  ];
}
