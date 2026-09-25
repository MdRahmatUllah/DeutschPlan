@TestOn('vm')
library;

import 'dart:async';
import 'dart:io' show FileSystemException;

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
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../services/fake_tts.dart';

/// S2 page 5 · Reminder and voice — #91.
void main() {
  // The manifest test reads the bundled asset outside a widget test.
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  late _FakePermission permission;
  late FakeTts tts;
  late _FakeDownloads downloads;
  late ProviderContainer container;

  OnboardingDraft draft() => container.read(onboardingProvider);

  Future<void> pump(
    WidgetTester tester, {
    bool allowed = true,
    bool permissionThrows = false,
    bool germanVoice = true,
    bool downloadFails = false,
    ModelStatus installed = ModelStatus.notDownloaded,
    bool asking = false,
    bool modelsFail = false,
    int shortfall = 0,
    DownloadProgress? inFlight,
    List<SupertonicOnPhone?>? heard,
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
    tts = FakeTts(voice: germanVoice);
    downloads = _FakeDownloads(
      fails: downloadFails,
      short: shortfall,
      last: inFlight,
    );
    container = ProviderContainer(
      // No retrying a provider that failed: a test's timers end with it.
      retry: (_, _) => null,
      overrides: <Override>[
        notificationPermissionProvider.overrideWithValue(permission),
        systemTtsProvider.overrideWithValue(tts),
        modelDownloadsProvider.overrideWithValue(downloads),
        modelRepositoryProvider.overrideWithValue(
          _FakeModels(installed, asking: asking, fails: modelsFail),
        ),
        supertonicMegabytesProvider.overrideWith((ref) async => 100),
      ],
    );
    if (heard != null) {
      container.listen(
        supertonicOnPhoneProvider,
        (_, next) => heard.add(next.value),
        fireImmediately: true,
      );
    }
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
      expect(
        find.text(l10n.onboardingSupertonicDownloading(0)),
        findsOneWidget,
      );
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

    testWidgets('#428 and waits disabled until the phone has been asked: an '
        'installed voice is never fetched in the moment before Ready', (
      tester,
    ) async {
      await pump(tester, asking: true);

      final download = tester.widget<DpButton>(
        find.widgetWithText(DpButton, l10n.onboardingSupertonicDownload),
      );
      expect(download.onPressed, isNull);
    });

    test("the size is the manifest's, rounded to ten", () async {
      // #245: the shipped manifest's seven files (four ONNX, two JSON and
      // the F1 voice) come to 398,653,248 bytes — read, not written.
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

      expect(await probe.read(supertonicMegabytesProvider.future), 400);
    });
  });

  group('#428 the voice as it stands on the phone', () {
    /// The download manager says [phase], [progress] of the way.
    Future<void> say(
      WidgetTester tester,
      DownloadPhase phase, [
      double progress = 0,
    ]) async {
      downloads.progress.add((phase: phase, progress: progress));
      await tester.pump();
      await tester.pump();
    }

    DpButton downloadButton(WidgetTester tester) => tester.widget<DpButton>(
      find.widgetWithText(DpButton, l10n.onboardingSupertonicDownload),
    );

    testWidgets('FR-S2-06 FR-M4 a phone short of space disables Download now '
        'and says by how much, rounded up', (tester) async {
      // 170.7 MB short: 171 MB freed is enough, 170 is not.
      await pump(tester, shortfall: 170700000);

      expect(
        find.text(l10n.onboardingSupertonicShortfall(171)),
        findsOneWidget,
      );
      expect(downloadButton(tester).onPressed, isNull);
      await tester.tap(find.text(l10n.onboardingSupertonicDownload));
      await tester.pump();
      expect(downloads.started, isEmpty);
    });

    testWidgets('FR-M4 space gone since the page looked: start refuses, and '
        'the card says by how much', (tester) async {
      await pump(tester);
      downloads.short = 170700000;

      await tester.tap(find.text(l10n.onboardingSupertonicDownload));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(downloads.started, isEmpty);
      expect(
        find.text(l10n.onboardingSupertonicShortfall(171)),
        findsOneWidget,
      );
      expect(downloadButton(tester).onPressed, isNull);
    });

    testWidgets('FR-S2-06 waiting for Wi-Fi reads as waiting, not '
        'downloading', (tester) async {
      await pump(tester);

      await say(tester, DownloadPhase.waitingForWifi);

      expect(find.text(l10n.onboardingSupertonicWaiting), findsOneWidget);
      expect(find.text(l10n.onboardingSupertonicDownloading(0)), findsNothing);
      expect(find.text(l10n.onboardingSupertonicDownload), findsNothing);
    });

    testWidgets('#428 FR-M4 a Retry refused for space says by how much, '
        'rounded up, and Retry stays', (tester) async {
      await pump(tester);
      await say(tester, DownloadPhase.failed, 0.6);
      downloads.retryShort = 50500000;

      await tester.tap(find.widgetWithText(DpButton, l10n.retry));
      await tester.pump();
      await tester.pump();

      expect(find.text(l10n.onboardingSupertonicShortfall(51)), findsOneWidget);
      expect(find.text(l10n.onboardingSupertonicDownloadFailed), findsNothing);
      expect(find.widgetWithText(DpButton, l10n.retry), findsOneWidget);
    });

    testWidgets('#428 a phone that could not be asked leaves Download now '
        'on: start still checks the space', (tester) async {
      await pump(tester, modelsFail: true);

      expect(downloadButton(tester).onPressed, isNotNull);
    });

    testWidgets('#428 an attempt in flight is heard before the space check: '
        'no flash of Needs N MB, which its own bytes would cause', (
      tester,
    ) async {
      final heard = <SupertonicOnPhone?>[];
      await pump(
        tester,
        shortfall: 170700000,
        inFlight: (phase: DownloadPhase.running, progress: 0.427),
        heard: heard,
      );
      // The space check's platform call answers.
      await tester.pump(Duration.zero);
      await tester.pump();

      expect(heard.whereType<SupertonicOnPhone>(), isNotEmpty);
      expect(
        heard.whereType<SupertonicOnPhone>().map((v) => v.shortfall),
        everyElement(0),
      );
      expect(
        find.text(l10n.onboardingSupertonicDownloading(42)),
        findsOneWidget,
      );
    });

    testWidgets('FR-M4 a failed download says so, and Retry retries rather '
        'than starting over', (tester) async {
      await pump(tester);

      await say(tester, DownloadPhase.failed, 0.6);
      expect(
        find.text(l10n.onboardingSupertonicDownloadFailed),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(DpButton, l10n.retry));
      await tester.pump();

      expect(downloads.retried, <String>[OnboardingNotifier.supertonic]);
      expect(downloads.started, isEmpty);
    });

    for (final status in <ModelStatus>[
      ModelStatus.ready,
      ModelStatus.updateAvailable,
    ]) {
      testWidgets('FR-S2-06 an installed voice (${status.name}) is Ready: no '
          'Download now, and nothing is fetched again', (tester) async {
        await pump(tester, installed: status);

        expect(find.text(l10n.onboardingSupertonicReady), findsOneWidget);
        expect(find.text(l10n.onboardingSupertonicDownload), findsNothing);
        expect(find.text(l10n.onboardingSupertonicLater), findsNothing);
        expect(downloads.started, isEmpty);
      });
    }

    testWidgets('FR-S2-06 the line follows the download: n %, then Ready when '
        'it finishes during the visit', (tester) async {
      await pump(tester);

      await say(tester, DownloadPhase.running, 0.427);
      expect(
        find.text(l10n.onboardingSupertonicDownloading(42)),
        findsOneWidget,
      );
      expect(find.text(l10n.onboardingSupertonicDownload), findsNothing);

      await say(tester, DownloadPhase.ready, 1);
      expect(find.text(l10n.onboardingSupertonicReady), findsOneWidget);
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

  @override
  Future<bool> openSettings() async => true;
}

class _FakeDownloads implements ModelDownloads {
  _FakeDownloads({required this.fails, required this.short, this.last});

  final bool fails;

  /// An attempt already in flight: `watch` says it first, as the real one's
  /// last word.
  final DownloadProgress? last;

  /// What *Retry* finds missing: its refusal.
  int retryShort = 0;

  /// What the phone lacks: the space check, and `start`'s refusal.
  int short;
  final List<String> started = <String>[];
  final List<String> retried = <String>[];
  final StreamController<DownloadProgress> progress =
      StreamController<DownloadProgress>.broadcast();

  @override
  Future<void> start(String modelId) async {
    if (fails) throw StateError('no network');
    if (short > 0) throw NotEnoughSpace(short);
    started.add(modelId);
  }

  /// A platform call: slower than the download manager's last word, which
  /// matters only when there is one.
  @override
  Future<int> shortfallFor(String modelId) async {
    if (last != null) await Future<void>.delayed(Duration.zero);
    return short;
  }

  @override
  Stream<DownloadProgress> watch(String modelId) async* {
    if (last case final last?) yield last;
    yield* progress.stream;
  }

  @override
  Future<void> retry(String modelId) async {
    if (retryShort > 0) throw NotEnoughSpace(retryShort);
    retried.add(modelId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Supertonic in the manifest, and on the phone as [installed] — or still
/// being asked, with [asking].
class _FakeModels implements ModelRepository {
  _FakeModels(this.installed, {this.asking = false, this.fails = false});

  final ModelStatus installed;
  final bool asking;

  /// The phone's model folder can't be read.
  final bool fails;

  static final ModelEntry _voice = ModelEntry(
    id: OnboardingNotifier.supertonic,
    name: 'Supertonic 3',
    licence: 'test',
    disables: 'tts_engine',
    regionExcluded: const <String>[],
    variants: <ModelVariant>[
      ModelVariant(
        id: 'f1',
        name: 'F1',
        files: <ModelFile>[
          ModelFile(
            name: 'model.onnx',
            url: Uri.parse('https://example.invalid/model.onnx'),
            bytes: 400000000,
            sha256: '0' * 64,
          ),
        ],
      ),
    ],
  );

  @override
  Future<ModelManifest> manifest() async =>
      ModelManifest(version: 1, models: <ModelEntry>[_voice]);

  @override
  Future<ModelState> stateOf(ModelEntry entry, ModelVariant variant) => asking
      ? Completer<ModelState>().future
      : fails
      ? Future<ModelState>.error(const FileSystemException('unreadable'))
      : Future<ModelState>.value(
          ModelState(entry: entry, variant: variant, status: installed),
        );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
