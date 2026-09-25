import 'dart:io';

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/features/me/reminder_days_screen.dart';
import 'package:deutschplan/features/today/today_providers.dart';
import 'package:deutschplan/features/today/today_view.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/services/notification_permission.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../core/text_clipping.dart';
import '../db/content_fixture.dart';
import 'today_fixtures.dart';

/// The phone's permission dialog, answered.
class FakePermission implements NotificationPermission {
  bool allowed = true;
  int asked = 0;
  int opened = 0;

  @override
  Future<bool> request() async {
    asked++;
    return allowed;
  }

  @override
  Future<bool> openSettings() async {
    opened++;
    return true;
  }
}

/// M5 · Study days & reminder — #147.
void main() {
  late AppLocalizations l10n;
  late Directory directory;
  late AppDatabase db;
  late SettingsRepository settings;
  late FakePermission permission;
  late TodayView view;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('deutschplan_m5');
    final content = ContentFixture.write('${directory.path}/content.db').file;
    db = AppDatabase.memory();
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
    );
    await db.customStatement(
      "INSERT INTO enrollments VALUES ('A1.1', '2026-09-01', 7, 127, NULL)",
    );
    settings = SettingsRepository(db);
    await settings.load();
    permission = FakePermission();
    view = artboardToday(reviseDone: 0, newDone: 0);
  });

  tearDown(() async {
    await settings.dispose();
    await db.close();
    directory.deleteSync(recursive: true);
  });

  Future<int> enrolledMask() async =>
      (await db
              .customSelect(
                'SELECT study_days_mask AS m FROM enrollments '
                'WHERE completed_on IS NULL',
              )
              .getSingle())
          .read<int>('m');

  Future<void> pump(
    WidgetTester tester, {
    AdaptiveChrome chrome = AdaptiveChrome.material,
  }) async {
    tester.view
      ..physicalSize = const Size(1200, 2600)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWithValue(settings),
          clockProvider.overrideWithValue(() => DateTime(2026, 9, 21, 8)),
          notificationPermissionProvider.overrideWithValue(permission),
          todayViewProvider.overrideWith((ref) async => view),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: AdaptiveChromeScope(chrome: chrome, child: child!),
          ),
          home: const ReminderDaysScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder day(String full) => find.bySemanticsLabel(full);

  // The rows' switches, in the card's order.
  final reminderSwitch = find.byType(AdaptiveSwitch).first;
  final onlyWhenDueSwitch = find.byType(AdaptiveSwitch).last;

  group('FR-M5-01 the study days', () {
    testWidgets('a day off reaches the setting and the plan', (tester) async {
      await pump(tester);
      expect(find.text(l10n.reminderDaysEveryDay), findsOneWidget);

      await tester.tap(find.text(l10n.weekdayShortSun));
      await tester.pumpAndSettle();

      expect(settings.read(SettingKeys.studyDaysMask), 63);
      expect(await enrolledMask(), 63);
      expect(find.text(l10n.reminderDaysRest(1, 'Sunday')), findsOneWidget);

      await tester.tap(find.text(l10n.weekdayShortSat));
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.reminderDaysRest(2, 'Saturday and Sunday')),
        findsOneWidget,
      );
    });

    testWidgets('the last study day stays', (tester) async {
      await settings.write(SettingKeys.studyDaysMask, 1);
      await pump(tester);

      await tester.tap(find.text(l10n.weekdayShortMon));
      await tester.pumpAndSettle();

      expect(settings.read(SettingKeys.studyDaysMask), 1);
      expect(await enrolledMask(), 127, reason: 'nothing was written');
    });

    testWidgets('a screen reader hears each day, and whether it is on', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await settings.write(SettingKeys.studyDaysMask, 63);
      await pump(tester);
      expect(
        tester.getSemantics(day(l10n.weekdayMon)),
        isSemantics(isButton: true, hasToggledState: true, isToggled: true),
      );
      expect(
        tester.getSemantics(day(l10n.weekdaySun)),
        isSemantics(isButton: true, hasToggledState: true, isToggled: false),
      );
      semantics.dispose();
    });
  });

  group('FR-M5-02 the reminder', () {
    testWidgets('on asks first; allowed, it is on', (tester) async {
      await pump(tester);
      expect(find.text(l10n.onboardingReminderOff), findsOneWidget);

      await tester.tap(reminderSwitch);
      await tester.pumpAndSettle();

      expect(permission.asked, 1);
      expect(settings.read(SettingKeys.reminderEnabled), isTrue);
      expect(find.text(l10n.reminderDaysGranted), findsOneWidget);
    });

    testWidgets('refused, it stays off, and says where to allow it', (
      tester,
    ) async {
      permission.allowed = false;
      await pump(tester);

      await tester.tap(reminderSwitch);
      await tester.pumpAndSettle();

      expect(settings.read(SettingKeys.reminderEnabled), isFalse);
      expect(find.text(l10n.onboardingReminderBlocked), findsOneWidget);
      await tester.tap(find.text(l10n.reminderDaysOpenSettings));
      expect(permission.opened, 1);
    });

    testWidgets('Open settings is a button of its own, not the whole card', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      permission.allowed = false;
      await pump(tester);
      await tester.tap(reminderSwitch);
      await tester.pumpAndSettle();

      final node = tester.getSemantics(
        find.bySemanticsLabel(l10n.reminderDaysOpenSettings),
      );
      expect(node, isSemantics(isButton: true, hasTapAction: true));
      expect(node.rect.height, lessThan(64), reason: 'the card is taller');
      semantics.dispose();
    });

    testWidgets('off asks nothing, and the preview goes', (tester) async {
      await settings.write(SettingKeys.reminderEnabled, true);
      await pump(tester);
      expect(find.text(l10n.reminderDaysTonight.toUpperCase()), findsOneWidget);

      await tester.tap(reminderSwitch);
      await tester.pumpAndSettle();

      expect(permission.asked, 0);
      expect(settings.read(SettingKeys.reminderEnabled), isFalse);
      expect(find.text(l10n.reminderDaysTonight.toUpperCase()), findsNothing);
    });

    testWidgets('only when there is something to do is saved', (tester) async {
      await pump(tester);
      await tester.tap(onlyWhenDueSwitch);
      await tester.pumpAndSettle();
      expect(settings.read(SettingKeys.reminderOnlyWhenDue), isFalse);
    });
  });

  testWidgets('FR-M5-04 a new time is saved, which reschedules the reminder', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('19:30'), findsOneWidget);

    await tester.tap(
      find.bySemanticsLabel(l10n.onboardingReminderTime('19:30')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.first, '21');
    await tester.enterText(fields.last, '05');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(settings.read(SettingKeys.reminderTime), (hour: 21, minute: 5));
    expect(find.text('21:05'), findsOneWidget);
  });

  group("FR-M5-03 tonight's text, from the task's composer", () {
    setUp(() async {
      await settings.write(SettingKeys.reminderEnabled, true);
    });

    testWidgets("today's plan, as the notification will say it", (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('DeutschPlan · 19:30'), findsOneWidget);
      expect(find.text('10 revisions · 7 new · about 6 min'), findsOneWidget);
    });

    testWidgets('a grammar topic due goes on the second line', (tester) async {
      view = TodayView(
        date: '2026-09-21',
        hour: 8,
        revise: const BlockProgress(done: 0, total: 12),
        newToday: const BlockProgress(done: 0, total: 7),
        openRevise: const <String>[],
        openNew: const <String>[],
        grammarDue: const <String>['g1'],
        backlog: 0,
        streak: 1,
        estimate: const Duration(minutes: 9),
        courseDay: 1,
        stepWords: (done: 0, learning: 0, todo: 3, total: 3),
      );
      await pump(tester);
      expect(find.text('12 revisions · 7 new · about 9 min'), findsOneWidget);
      expect(
        find.text(l10n.reminderGrammar('Wortstellung im Hauptsatz')),
        findsOneWidget,
      );
    });

    testWidgets('a done day: no reminder, or the plain one', (tester) async {
      view = artboardDone();
      await pump(tester);
      expect(find.text(l10n.reminderDaysNothing), findsOneWidget);

      await tester.tap(onlyWhenDueSwitch);
      await tester.pumpAndSettle();
      expect(find.text(l10n.reminderBody), findsOneWidget);
    });

    testWidgets('a rest day: no reminder', (tester) async {
      view = artboardRest();
      await pump(tester);
      expect(find.text(l10n.reminderDaysRestToday), findsOneWidget);
    });
  });

  testWidgets('#314 at 200 % text nothing on M5 is cut', (tester) async {
    textAt(tester, 2);
    await settings.write(SettingKeys.reminderEnabled, true);
    await pump(tester);
    expectNothingClipped(tester, within: find.byType(ReminderDaysScreen));
  });

  testWidgets('iOS: "Settings" beside the back chevron', (tester) async {
    await pump(tester, chrome: AdaptiveChrome.cupertino);
    expect(find.text(l10n.settingsTitle), findsOneWidget);
  });
}
