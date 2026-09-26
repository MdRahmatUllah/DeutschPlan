// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/features/me/reminder_days_screen.dart';
import 'package:sogda/features/today/today_providers.dart';
import 'package:sogda/services/background_tasks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';

import '../features/settings_fixtures.dart';
import '../features/today_fixtures.dart';
import 'golden_harness.dart';

/// M5 · Study days & reminder — #147. The artboard: Monday to Saturday, the
/// reminder on at 19:30 only when there is something to do, and tonight's
/// "12 revisions · 7 new · about 9 min" with Konjunktiv II due.
void main() {
  Widget screen(BuildContext context) => ProviderScope(
    overrides: <Override>[
      settingsProvider.overrideWithValue(
        StubSettings()
          ..put(SettingKeys.studyDaysMask, 63)
          ..put(SettingKeys.reminderEnabled, true),
      ),
      todayViewProvider.overrideWith((ref) async => artboardToday()),
      reminderBodyProvider.overrideWith(
        (ref) async =>
            '12 revisions · 7 new · about 9 min\nGrammar due: Konjunktiv II',
      ),
    ],
    child: MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: const ReminderDaysScreen(),
    ),
  );

  goldenTest('reminder_days', builder: screen);
  goldenTest(
    'reminder_days_ios',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
    builder: screen,
  );
}
