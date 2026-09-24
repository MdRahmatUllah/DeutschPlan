// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/features/day_complete/day_complete_screen.dart';
import 'package:deutschplan/features/today/today_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/today_fixtures.dart';
import 'golden_harness.dart';

/// T6 · Day complete — #111. The artboard, once everything has landed: the
/// full ring and its check, the twenty pieces at rest, "Tag geschafft!",
/// 17 words in 12 minutes, the 13-day streak and tomorrow's 12 · 7.
///
/// Two sets: `day_complete` is the harness's usual still frame, which for
/// T6 is the reduced-motion state (FR-T6-03: no confetti), in all three
/// modes; `day_complete_confetti` lets the fall play and land, in light and
/// dark, where there is no aurora to keep the frame from settling.
void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  setUp(() async {
    db = AppDatabase.memory();
    settings = SettingsRepository(db);
    await settings.load();
  });
  tearDown(() async {
    await settings.dispose();
    await db.close();
  });

  goldenTest(
    'day_complete',
    builder: (context) => ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        settingsProvider.overrideWithValue(settings),
        todayViewProvider.overrideWith((ref) async => artboardDone()),
      ],
      child: const DayCompleteScreen(),
    ),
    act: land,
  );

  goldenTest(
    'day_complete_confetti',
    modes: const <GoldenMode>[GoldenMode.light, GoldenMode.dark],
    still: false,
    builder: (context) => ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        settingsProvider.overrideWithValue(settings),
        todayViewProvider.overrideWith((ref) async => artboardDone()),
      ],
      child: const DayCompleteScreen(),
    ),
    act: land,
  );
}

/// The day claimed off the fake clock, then the 1.2 s fall.
Future<void> land(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1300));
}
