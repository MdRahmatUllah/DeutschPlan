import 'package:deutschplan/data/db/app_database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:deutschplan/data/repositories/plan_store.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/domain/plan_engine.dart';

/// What S2 decided, ready to be written.
class SetupChoice {
  const SetupChoice({
    required this.step,
    required this.dailyNew,
    required this.reviseCount,
    required this.studyDaysMask,
    required this.reminderOn,
    required this.reminderTime,
  });

  final String step;
  final int dailyNew;
  final int reviseCount;
  final int studyDaysMask;
  final bool reminderOn;
  final Clock reminderTime;
}

/// FR-S2-03: the end of S2, written in one transaction.
///
/// `onboarding.md`: "`OnboardingNotifier` holds draft values; commits in one
/// transaction on finish." The settings and the enrollment together, so a
/// learner never has a pace without a step or a step without its pace — the
/// states a crash halfway through a series of separate writes would leave.
class SetupRepository {
  SetupRepository(this._db, this._settings)
    : _store = DriftPlanStore(_db, _settings);

  final AppDatabase _db;
  final SettingsRepository _settings;

  /// For `enroll` and `activeStep`, which run inside the transaction here
  /// exactly as they do on their own.
  final DriftPlanStore _store;

  /// M3's *New words per day*: the setting, and the pace of the open
  /// enrollment, which is what the plan engine reads. BR-PLAN-08 has it reach
  /// the plan from tomorrow — days already planned are not rewritten.
  ///
  /// Through drift's typed update, not a raw statement, so the step lines
  /// that show the pace ("about 41 days left at 15 words/day") hear it.
  Future<void> setDailyNew(int count) => _db.transaction(() async {
    await _settings.write(SettingKeys.dailyNew, count);
    await (_db.update(_db.enrollments)..where((e) => e.completedOn.isNull()))
        .write(EnrollmentsCompanion(dailyNew: Value(count)));
  });

  /// Writes [choice] as of [today]. Progress — word states, the review log,
  /// days already planned — is not touched: restart setup changes the plan,
  /// not the history (`onboarding.md`).
  Future<void> commit(SetupChoice choice, {required PlanDate today}) async {
    try {
      await _db.transaction(() async {
        await _settings.write(SettingKeys.dailyNew, choice.dailyNew);
        await _settings.write(SettingKeys.reviseCount, choice.reviseCount);
        await _settings.write(SettingKeys.studyDaysMask, choice.studyDaysMask);
        await _settings.write(SettingKeys.reminderEnabled, choice.reminderOn);
        await _settings.write(SettingKeys.reminderTime, choice.reminderTime);

        final active = (await _store.activeStep())?.sublevelCode;
        if (active == choice.step) {
          // The same step again — restart setup with a new pace. The
          // enrollment keeps its start; only the pace it was frozen at moves,
          // and BR-PLAN-08 has that reach the plan from tomorrow.
          await _db.customStatement(
            'UPDATE enrollments SET daily_new = ?2, study_days_mask = ?3 '
            'WHERE sublevel_code = ?1',
            <Object>[choice.step, choice.dailyNew, choice.studyDaysMask],
          );
          return;
        }

        // A different step. `idx_one_active_enrollment` allows one open
        // enrollment, so the old one closes first — `completed_on` is the
        // schema's only way to say "no longer active", and backup import
        // closes a surplus one the same way.
        if (active != null) {
          await _db.customStatement(
            'UPDATE enrollments SET completed_on = ?2 WHERE sublevel_code = ?1',
            <Object>[active, today],
          );
        }
        await _store.enroll(
          ActiveStep(
            sublevelCode: choice.step,
            startedOn: today,
            dailyNew: choice.dailyNew,
            studyDaysMask: choice.studyDaysMask,
          ),
        );
      });
    } on Object {
      // `write` puts each value in memory before the database. A rolled-back
      // transaction would leave the cache saying what the disk does not, so
      // it is read back from the disk before the error goes on.
      await _settings.load();
      rethrow;
    }
  }

  /// The step restart setup starts from, or null before the first setup.
  Future<String?> activeStep() async =>
      (await _store.activeStep())?.sublevelCode;
}
