@TestOn('vm')
library;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoDatePicker;
import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_speaker_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/model_repository.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/features/onboarding/onboarding_notifier.dart';
import 'package:deutschplan/features/onboarding/onboarding_voice_page.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/services/model_downloads.dart';
import 'package:deutschplan/services/notification_permission.dart';
import 'package:deutschplan/services/tts/tts_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// S2 page 5 · Reminder and voice — #91.
void main() {
  // The manifest test reads the bundled asset outside a widget test.
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  late _FakePermission permission;
  late _FakeTts tts;
  late _FakeDownloads downloads;
  late ProviderContainer container;

  OnboardingDraft draft() => container.read(onboardingProvider);

  Future<void> pump(
    WidgetTester tester, {
    bool allowed = true,
    bool permissionThrows = false,
    bool germanVoice = true,
    bool downloadFails = false,
    DpMode mode = DpMode.light,
    double textScale = 1,
    VoidCallback? onFinish,
    VoidCallback? onBack,
  }) async {
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    permission = _FakePermission(allowed: allowed, throws: permissionThrows);
    tts = _FakeTts(available: germanVoice);
    downloads = _FakeDownloads(fails: downloadFails);
    container = ProviderContainer(
      overrides: <Override>[
        notificationPermissionProvider.overrideWithValue(permission),
        systemTtsProvider.overrideWithValue(tts),
        modelDownloadsProvider.overrideWithValue(downloads),
        supertonicMegabytesProvider.overrideWith((ref) async => 100),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: switch (mode) {
            DpMode.light => AppTheme.light(),
            DpMode.dark => AppTheme.dark(),
            DpMode.glass => AppTheme.glass(),
          },
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: OnboardingVoicePage(onFinish: onFinish, onBack: onBack),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Finder reminderSwitch() => find.byType(AdaptiveSwitch);

  group('FR-S2-05 the reminder', () {
    testWidgets('starts off at 19:30 and asks for nothing', (tester) async {
      // "Reminder permission MUST be requested only when the switch is turned
      // on" — so opening the page must not ask.
      await pump(tester);

      expect(draft().reminderOn, isFalse);
      expect(draft().reminderTime, (hour: 19, minute: 30));
      expect(permission.asked, 0);
      expect(find.text(l10n.onboardingReminderOff), findsOneWidget);
    });

    testWidgets('asks when the switch goes on, and turns on if allowed', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(reminderSwitch());
      await tester.pump();
      await tester.pump();

      expect(permission.asked, 1);
      expect(draft().reminderOn, isTrue);
      expect(tester.widget<AdaptiveSwitch>(reminderSwitch()).value, isTrue);
    });

    testWidgets('and stays off if refused, saying why', (tester) async {
      await pump(tester, allowed: false);

      await tester.tap(reminderSwitch());
      await tester.pump();
      await tester.pump();

      expect(permission.asked, 1);
      expect(draft().reminderOn, isFalse);
      expect(find.text(l10n.onboardingReminderBlocked), findsOneWidget);
    });

    testWidgets('and a request that throws changes nothing', (tester) async {
      // permission_handler errors rather than answers when a request is
      // already running. That is no answer — not a refusal to record.
      await pump(tester, permissionThrows: true);

      await tester.tap(reminderSwitch());
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(draft().reminderOn, isFalse);
      expect(draft().reminderBlocked, isFalse);
      expect(find.text(l10n.onboardingReminderOff), findsOneWidget);
    });

    testWidgets('and switching it off asks nothing', (tester) async {
      await pump(tester);
      await tester.tap(reminderSwitch());
      await tester.pump();
      await tester.pump();

      await tester.tap(reminderSwitch());
      await tester.pump();

      expect(permission.asked, 1, reason: 'only the switch-on asked');
      expect(draft().reminderOn, isFalse);
    });
  });

  group('the reminder time', () {
    testWidgets('opens the Material dialog on Android', (tester) async {
      await pump(tester);

      await tester.tap(
        find.bySemanticsLabel(l10n.onboardingReminderTime('7:30 PM')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TimePickerDialog), findsOneWidget);
    });

    testWidgets('and the Cupertino wheel on iOS', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await pump(tester);

      await tester.tap(
        find.bySemanticsLabel(l10n.onboardingReminderTime('7:30 PM')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      expect(find.byType(TimePickerDialog), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('and a new time lands in the draft', (tester) async {
      await pump(tester);

      container.read(onboardingProvider.notifier).setReminderTime((
        hour: 7,
        minute: 5,
      ));
      await tester.pump();

      expect(find.text('7:05 AM'), findsOneWidget);
      expect(draft().reminderTime, (hour: 7, minute: 5));
    });
  });

  group('the preview', () {
    testWidgets('speaks Guten Tag! with the system voice', (tester) async {
      // "Preview uses the system voice so it works before any model exists."
      await pump(tester);

      await tester.tap(find.byType(DpSpeakerButton));
      await tester.pump();

      expect(tts.spoken, <String>['Guten Tag!']);
      expect(find.text(l10n.onboardingVoiceSystem), findsOneWidget);
    });

    testWidgets('and says so when there is no German voice', (tester) async {
      await pump(tester, germanVoice: false);

      await tester.tap(find.byType(DpSpeakerButton));
      await tester.pump();

      expect(find.text(l10n.onboardingVoiceMissing), findsOneWidget);
      expect(
        tester.widget<DpSpeakerButton>(find.byType(DpSpeakerButton)).state,
        DpSpeakerState.unavailable,
      );
    });
  });

  group('FR-S2-06 the better voice', () {
    testWidgets('Download now queues Supertonic, and setup carries on', (
      tester,
    ) async {
      var finished = 0;
      await pump(tester, onFinish: () => finished++);

      await tester.tap(find.text(l10n.onboardingSupertonicDownload));
      await tester.pump();
      await tester.pump();

      expect(downloads.started, <String>[OnboardingNotifier.supertonic]);
      expect(find.text(l10n.onboardingSupertonicStarted), findsOneWidget);
      expect(find.text(l10n.onboardingSupertonicDownload), findsNothing);

      // "…and continue onboarding": nothing waits on the bytes.
      await tester.tap(find.text(l10n.onboardingStartLearning));
      await tester.pump();
      expect(finished, 1);
    });

    testWidgets('and is queued once however often the page is visited', (
      tester,
    ) async {
      await pump(tester);
      final notifier = container.read(onboardingProvider.notifier);

      await notifier.downloadVoice();
      await notifier.downloadVoice();

      expect(downloads.started, hasLength(1));
    });

    testWidgets('a failure to queue leaves the offer, and says so', (
      tester,
    ) async {
      await pump(tester, downloadFails: true);

      await tester.tap(find.text(l10n.onboardingSupertonicDownload));
      await tester.pump();
      await tester.pump();

      expect(draft().voice, VoiceOffer.offered);
      expect(find.text(l10n.onboardingSupertonicFailed), findsOneWidget);
      expect(find.text(l10n.onboardingSupertonicDownload), findsOneWidget);
    });

    testWidgets('Later puts it off, and queues nothing', (tester) async {
      await pump(tester);

      await tester.tap(find.text(l10n.onboardingSupertonicLater));
      await tester.pump();

      expect(downloads.started, isEmpty);
      expect(draft().voice, VoiceOffer.deferred);
      expect(find.text(l10n.onboardingSupertonicDeferred), findsOneWidget);
    });

    test("the size is the manifest's, rounded to ten", () async {
      // The shipped manifest's two files come to 102,760,448 bytes: "about
      // 100 MB", as the card says — read, not written.
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final settings = SettingsRepository(db);
      await settings.load();
      addTearDown(settings.dispose);

      final probe = ProviderContainer(
        overrides: <Override>[
          modelRepositoryProvider.overrideWithValue(ModelRepository(settings)),
        ],
      );
      addTearDown(probe.dispose);

      expect(await probe.read(supertonicMegabytesProvider.future), 100);
    });
  });

  group('the actions', () {
    testWidgets('Start learning finishes, and Back goes back', (tester) async {
      var finished = 0;
      var back = 0;
      await pump(tester, onFinish: () => finished++, onBack: () => back++);

      await tester.tap(find.text(l10n.onboardingStartLearning));
      await tester.tap(find.text(l10n.back));
      await tester.pump();

      expect(<int>[finished, back], <int>[1, 1]);
    });

    testWidgets('and with nowhere to finish yet, it waits disabled', (
      tester,
    ) async {
      // #92 builds the finish. Until the route hands one over, the button
      // renders — the learner can see where setup ends — but does nothing.
      await pump(tester);

      final start = tester.widget<DpButton>(
        find.widgetWithText(DpButton, l10n.onboardingStartLearning),
      );
      expect(start.onPressed, isNull);
    });
  });

  group('it is built from the design system', () {
    testWidgets('no Material chrome', (tester) async {
      await pump(tester);

      expect(find.byType(AdaptiveScaffold), findsOneWidget);
      // The adaptive wrapper, which is the one place a platform switch is
      // allowed to come from.
      expect(find.byType(AdaptiveSwitch), findsOneWidget);
      expect(find.byType(Card), findsNothing);
      expect(find.byType(IconButton), findsNothing);
    });

    for (final mode in <DpMode>[DpMode.dark, DpMode.glass]) {
      testWidgets('and ${mode.name} renders it', (tester) async {
        await pump(tester, mode: mode);
        expect(find.text(l10n.onboardingSupertonicTitle), findsOneWidget);
      });
    }
  });

  group('accessibility', () {
    testWidgets('every control says what it is', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);

      expect(
        find.bySemanticsLabel(l10n.onboardingReminderTime('7:30 PM')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(l10n.onboardingVoicePlay), findsOneWidget);
      expect(
        tester.getSemantics(reminderSwitch()).label,
        l10n.onboardingReminder,
      );

      handle.dispose();
    });

    testWidgets('and it holds together at 200 % text', (tester) async {
      await pump(tester, textScale: 2);

      expect(tester.takeException(), isNull);
    });
  });
}

class _FakePermission implements NotificationPermission {
  _FakePermission({required this.allowed, this.throws = false});

  final bool allowed;
  final bool throws;
  int asked = 0;

  @override
  Future<bool> request() async {
    asked++;
    if (throws) {
      throw StateError('A request for permissions is already running');
    }
    return allowed;
  }
}

class _FakeTts implements TtsEngine {
  _FakeTts({required this.available});

  final bool available;
  final List<String> spoken = <String>[];

  @override
  Future<bool> speak(String text) async {
    if (!available) return false;
    spoken.add(text);
    return true;
  }

  @override
  Future<void> stop() async {}
}

class _FakeDownloads implements ModelDownloads {
  _FakeDownloads({required this.fails});

  final bool fails;
  final List<String> started = <String>[];

  @override
  Future<void> start(String modelId) async {
    if (fails) throw StateError('no network');
    started.add(modelId);
  }
}
