import 'dart:async';

import 'package:sogda/features/bootstrap/bootstrap_error_screen.dart';
import 'package:sogda/features/splash/splash_screen.dart';
import 'package:sogda/features/today/today_providers.dart' show warmTodaysVoice;
import 'package:flutter/foundation.dart' show kReleaseMode, debugPrint;
import 'package:flutter/services.dart';

import 'dart:io';

import 'package:sogda/data/repositories/backup_repository.dart';
import 'package:sogda/core/theme/system_bars.dart';
import 'package:sogda/core/adaptive/orientation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sogda/bootstrap.dart';
import 'package:sogda/core/theme/app_theme.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/theme/glass_capability.dart';
import 'package:sogda/core/theme/theme_mode.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/l10n/ui_language_locale.dart';
import 'package:sogda/router/app_router.dart';
import 'package:sogda/router/deep_links.dart';
import 'package:sogda/services/background_tasks.dart';
import 'package:sogda/services/background_work.dart';
import 'package:sogda/services/reminder_notifications.dart';
import 'package:sogda/services/widget_snapshot.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is not in the main barrel in Riverpod 3.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
// The widgets layer is the SDK's own, so its delegate still comes from
// flutter_localizations; Material and Cupertino come from their packages.
import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;

import 'dart:ui' show PlatformDispatcher;

export 'package:sogda/l10n/ui_language_locale.dart';

/// Entry point.
///
/// Every byte of disk work still happens inside [bootstrap] — FR-S1-01 — but
/// `runApp` goes *first*, showing S1 while that runs.
///
/// It used to await bootstrap before the first frame, which meant the native
/// launch window covered the whole wait and `SplashScreen` could never render:
/// nothing reached `/splash`, and FR-S1's "progress line after 600 ms" had no
/// moment in which to appear. On a first run that wait is an 8 MB content copy,
/// so the line is not hypothetical.
///
/// The provider container is still built from bootstrap's result and still
/// overrides everything it opened; it just cannot exist until there is a
/// result, so S1 renders outside it. S1 needs a theme and nothing else.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Edge to edge, because the design is. S2's coloured header, S1's field and
  // the Today header all bleed to the top of the screen; without this Android
  // paints its own opaque bar above them and every one of those screens gets a
  // grey band across the top. Each screen still takes the inset with
  // `SafeArea` — this only stops the system filling it in first.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(transparentSystemBars);

  // A `ProviderScope` at the true root, which riverpod_lint requires and which
  // S1 needs anyway now that it renders before bootstrap has produced a
  // container. Once there is a result, the `UncontrolledProviderScope` below
  // shadows this one for everything under it — that is the scope carrying
  // bootstrap's overrides, and the one every screen actually reads from.
  runApp(const ProviderScope(child: BootstrapHost()));
}

/// Shows S1 while [bootstrap] runs, then swaps in the real app.
class BootstrapHost extends StatefulWidget {
  const BootstrapHost({super.key, this.run, this.wire});

  /// Overridden in tests. Defaults to the real [bootstrap].
  final Future<BootstrapResult> Function({
    Brightness platformBrightness,
    void Function(UiLanguage)? onUiLanguage,
  })?
  run;

  /// Overridden in tests, which have no platform side for the plugins behind
  /// it. Defaults to [wireApp].
  final void Function(ProviderContainer container, Bootstrap bootstrap)? wire;

  @override
  State<BootstrapHost> createState() => _BootstrapHostState();
}

class _BootstrapHostState extends State<BootstrapHost>
    with WidgetsBindingObserver {
  Widget? _app;

  /// #577: a phone stays portrait, a tablet turns. Decided from the window's
  /// size as it comes, not before `runApp`, when it can still be empty, and
  /// again when it crosses the tablet line (a foldable, split screen).
  final OrientationLock _orientation = OrientationLock();

  /// The learner's language, once bootstrap has read it. Until then the
  /// splash follows the phone — there is nothing else to follow.
  Locale? _splashLocale;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    didChangeMetrics();
    unawaited(_start());
  }

  @override
  void didChangeMetrics() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    unawaited(_orientation.update(view.physicalSize / view.devicePixelRatio));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Its own: an `UncontrolledProviderScope` leaves the container alone.
    _container?.dispose();
    super.dispose();
  }

  /// The container the app runs in: the first start's, or a retry's.
  ProviderContainer? _container;

  Future<void> _start() async {
    final result = await _run();
    if (mounted) _adopt(result);
  }

  /// [bootstrap], or the test's stand-in: at launch, and again from the
  /// error screen's *Retry*.
  Future<BootstrapResult> _run() => (widget.run ?? bootstrap)(
    platformBrightness: PlatformDispatcher.instance.platformBrightness,
    onUiLanguage: (ui) {
      if (mounted) setState(() => _splashLocale = ui.locale);
    },
  );

  /// Puts the app for [result] on screen, in a container of its own.
  ///
  /// Also where a retry that worked lands (#643). The failed start's
  /// container carries no overrides, so an app built under it threw on its
  /// first frame, and nothing it needs had been started. This gives it a new
  /// container and the same wiring as a first start.
  void _adopt(BootstrapResult result) {
    // ProviderScope at the very root, on both paths: riverpod_lint enforces
    // it, and the error screen's *Export progress* reads a repository too.
    //
    // The overrides are what stop the providers re-opening what bootstrap has
    // already opened. A failed bootstrap has none, so anything that reads the
    // database throws with a message rather than opening a second one.
    final container = ProviderContainer(
      overrides: switch (result) {
        BootstrapReady(:final bootstrap) => bootstrap.overrides,
        BootstrapFailed() => const <Override>[],
      },
    );

    if (result is BootstrapReady) {
      // FR-S1-02 is a budget, and a budget nobody can read is a budget nobody
      // keeps. One line in logcat, so the number is measurable on a device
      // rather than inferred from `am start -W` — which now reports the
      // splash frame rather than the time to Today. Release builds report
      // Today as Android's "Fully drawn" instead (#462).
      //
      // Debug *and* profile, never release: a debug build is JIT and its
      // numbers mean nothing against a 500 ms budget, so the only build worth
      // measuring is an AOT one.
      if (!kReleaseMode) {
        debugPrint('bootstrap: ${result.bootstrap.elapsed.inMilliseconds} ms');
      }
      (widget.wire ?? wireApp)(container, result.bootstrap);
    }

    final previous = _container;
    setState(() {
      _container = container;
      _app = UncontrolledProviderScope(
        // Keyed by its container: a retry replaces the whole tree, rather
        // than swapping the container under widgets that read the old one.
        key: ObjectKey(container),
        container: container,
        child: appFor(result, retry: _run, onReady: _adopt),
      );
    });
    // The failed start's. Nothing was opened through it, and it goes once
    // the frame that drops its tree has been built.
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  @override
  Widget build(BuildContext context) =>
      _app ??
      MaterialApp(
        debugShowCheckedModeBanner: false,
        // Platform brightness, because settings are exactly what bootstrap has
        // not read yet. It is also what the native launch window followed, so
        // the hand-off does not change colour.
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        locale: _splashLocale,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: supportedLocales,
        home: const SplashProgressGate(),
      );
}

/// A ready app's platform side: the light/dark switch, the reminders, the
/// home-screen widget, model downloads and the voice.
///
/// Once per app container, at launch or after a retry that worked (#643).
void wireApp(ProviderContainer container, Bootstrap bootstrap) {
  final platform = PlatformDispatcher.instance;
  // The system light/dark switch. Without this the theme notifier never
  // hears about it, and a learner following the platform would keep whatever
  // the phone was on when the app launched.
  container
      .read(themeProvider.notifier)
      .platformBrightnessChanged(platform.platformBrightness);
  platform.onPlatformBrightnessChanged = () => container
      .read(themeProvider.notifier)
      .platformBrightnessChanged(platform.platformBrightness);

  unawaited(
    startReminders(
      container,
      PlatformReminderNotifications(),
      const WorkmanagerWork(),
      open: bootstrap.router.go,
    ),
  );
  // FR-X1-01: the home-screen widget's snapshot, kept to today (#159).
  followWidget(container, const HomeWidgetStore());
  // FR-M4-01: model downloads carry on from where the app left them, and
  // report as they go (#156).
  unawaited(container.read(modelDownloadsProvider).attach());
  // #460: Supertonic ready before the first session opens.
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => unawaited(warmTodaysVoice(container)),
  );
}

/// The daily reminder (#157) and the background tasks (#158): the plugins
/// set up, a tapped reminder opening what it links to, and the schedule kept
/// to the settings from now on.
///
/// Like [followPlatformBrightness], a function a test can call: `main` is
/// the one no test does. A plugin that fails to start costs the reminder,
/// never the app.
Future<StreamSubscription<SettingKey<Object?>>?> startReminders(
  ProviderContainer container,
  ReminderNotifications notifications,
  BackgroundWork work, {
  required void Function(String location) open,
}) async {
  void go(String link) => open(resolveDeepLink(Uri.parse(link)));
  try {
    await notifications.init(go);
    // A tap that started the app arrives here, not through [init]'s
    // callback, which hears only taps while it runs.
    if (await notifications.launchedWith() case final link?) go(link);
    await startBackgroundWork(work, container.read(clockProvider)());
  } on Object catch (error) {
    debugPrint('reminders: $error');
    return null;
  }
  return remindersFor(container, notifications, work).follow();
}

/// Keeps the theme notifier in step with the system light/dark switch.
///
/// Without this the notifier never hears about it, and a learner following
/// the platform keeps whatever the phone was on when the app launched.
///
/// [read] and [onChanged] rather than a `PlatformDispatcher`, so the wiring
/// is something a test can drive: `main` is the one function no test calls,
/// and a hook installed only there is a hook nothing checks.
void followPlatformBrightness(
  ProviderContainer container, {
  required Brightness Function() read,
  required void Function(VoidCallback listener) onChanged,
}) {
  void tell() =>
      container.read(themeProvider.notifier).platformBrightnessChanged(read());

  // Once now, because the notifier's own default is only what a test gets —
  // a dark phone would otherwise see a light first frame.
  tell();
  onChanged(tell);
}

/// The app for a finished bootstrap, or FR-S1-03's error screen.
///
/// The error screen's *Retry* runs [retry], and hands a result that worked to
/// [onReady]: the host, which builds the app its own container (#643).
Widget appFor(
  BootstrapResult result, {
  required void Function(BootstrapReady ready) onReady,
  required Future<BootstrapResult> Function() retry,
}) => switch (result) {
  // The providers #71 declares are overridden from here, so nothing has to
  // re-open what bootstrap already opened.
  BootstrapReady(:final bootstrap) => GlassCapabilityScope(
    notifier: bootstrap.glass,
    child: SogdaApp(router: bootstrap.router),
  ),
  BootstrapFailed(:final failure) => BootstrapGate(
    failure: failure,
    onRetry: retry,
    onReady: onReady,
  ),
};

/// Supported UI languages, English first — see `supportedLocales` in [SogdaApp].
const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('bn')];

/// The delegates every `MaterialApp` here takes — not gen_l10n's own list.
///
/// gen_l10n names `flutter_localizations`' Material and Cupertino delegates,
/// which localise the SDK's widgets. This app draws `material_ui`'s and
/// `cupertino_ui`'s, which look up types of their own. With gen_l10n's list
/// English only worked because `material_ui` falls back to built-in English;
/// Bangla had nothing, and the first widget to ask — the nav bar — threw.
const List<LocalizationsDelegate<Object?>> appLocalizationsDelegates =
    <LocalizationsDelegate<Object?>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ];

class SogdaApp extends ConsumerWidget {
  SogdaApp({GoRouter? router, super.key}) : router = router ?? buildRouter();

  /// Built by [bootstrap] and held for the life of the app.
  ///
  /// Passed in rather than made here: a router rebuilt on every frame loses
  /// its navigation stack, and one in a static is shared by every instance,
  /// so two widget tests in a file would inherit each other's history. The
  /// default is for tests that only want a tree to look at.
  final GoRouter router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watched, not passed in: Settings writes through `Theme.choose` and the
    // new mode has to reach the first frame after it, which a value captured
    // at launch cannot do.
    final mode = ref.watch(themeProvider);
    final followsPlatform = ref
        .watch(settingsProvider)
        .read(SettingKeys.themeMode)
        .followsPlatform;

    return MaterialApp.router(
      routerConfig: router,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      // `ui_language`, not the device: S2 page 2 and Settings both set it, and
      // a learner who chose বাংলা on an English phone means it.
      locale: ref.watch(languagesProvider).ui.locale,
      // FR-M3-02: Glass is a theme of its own, in a light and a smoked dark
      // variant; the platform's light/dark picks between them (theming.md).
      theme: mode == SgMode.glass ? AppTheme.glass() : AppTheme.light(),
      darkTheme: mode == SgMode.glass
          ? AppTheme.glass(dark: true)
          : AppTheme.dark(),
      themeMode: switch (mode) {
        _ when followsPlatform || mode == SgMode.glass => ThemeMode.system,
        SgMode.light => ThemeMode.light,
        SgMode.dark => ThemeMode.dark,
        SgMode.glass => ThemeMode.system,
      },
      localizationsDelegates: appLocalizationsDelegates,
      // English first: gen_l10n orders supportedLocales alphabetically, which puts
      // Bangla first, and Flutter falls back to the FIRST supported locale when the
      // device locale matches none. `ui_language` defaults to `en`
      // (docs/02-data/user-database.md), so English has to lead.
      supportedLocales: supportedLocales,
      // #164: iOS's Reduce Motion reaches every `still` in the app.
      builder: (context, child) =>
          stillOnReduceMotion(context, child ?? const SizedBox.shrink()),
    );
  }
}

/// FR-S1-03's *Retry*: re-runs bootstrap, shows a new failure itself, and
/// hands a ready result to [onReady], the host, which builds the app (#643).
///
/// It never builds the app: it sits under the failed start's container,
/// which carries no overrides, and the app's first frame threw there.
/// Stateful for the busy flag and the failure on screen. The disabled buttons
/// a callback-less error screen renders are not an error screen, they are a
/// dead end.
class BootstrapGate extends StatefulWidget {
  const BootstrapGate({
    required this.failure,
    required this.onReady,
    this.onRetry,
    this.onShare,
    super.key,
  });

  final BootstrapFailure failure;

  /// Where a retry that worked goes: [BootstrapHost], which builds the app a
  /// container carrying bootstrap's overrides (#643). The gate never builds
  /// the app itself: it sits under the failed start's container, which has
  /// none, and the app's first frame threw there.
  final void Function(BootstrapReady ready) onReady;

  /// The host's bootstrap, and a stand-in in tests, which have no disk to
  /// bootstrap against.
  final Future<BootstrapResult> Function()? onRetry;

  /// Hands the finished backup to the platform. Overridden in tests, which
  /// have no share sheet — and injected rather than called inline so a test
  /// can drive the *wiring* and not just the file format. A test that only
  /// checked the artefact could not tell this button from an empty closure,
  /// which is how it shipped as one.
  final Future<void> Function(XFile file)? onShare;

  @override
  State<BootstrapGate> createState() => _BootstrapGateState();
}

class _BootstrapGateState extends State<BootstrapGate> {
  late BootstrapFailure _failure = widget.failure;
  var _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);

    // A content failure is nearly always a half-written or corrupt copy, and
    // retrying against the same file would fail identically for ever.
    if (_failure.step == BootstrapStep.content) {
      await resetInstalledContent();
    }
    await _failure.dispose();

    final result = await (widget.onRetry ?? bootstrap)();
    if (!mounted) return;

    switch (result) {
      case BootstrapReady():
        widget.onReady(result);
      case BootstrapFailed(:final failure):
        setState(() {
          _retrying = false;
          _failure = failure;
        });
    }
  }

  @override
  Widget build(BuildContext context) => BootstrapErrorApp(
    failure: _failure,
    onRetry: _retrying ? null : _retry,
    onExport: _failure.canExport ? _export : null,
  );

  /// FR-S1-03's second half: get the learner's data out when nothing else in
  /// the app will start.
  ///
  /// It used to be `() {}` with a comment deferring the share sheet to another
  /// issue — which offered a button that did nothing, the very thing
  /// `canExport` exists to prevent. `share_plus` is already a dependency, so
  /// there was nothing to wait for.
  ///
  /// The file goes to temporary storage rather than app support: it is a copy
  /// being handed to another app, not state, and the OS may clear it
  /// afterwards — which is the right lifetime for something already sent.
  Future<void> _export() async {
    final db = _failure.db;
    if (db == null) return;

    final json = await BackupRepository(db).exportJson();
    final file = File(
      '${(await getTemporaryDirectory()).path}/$exportFileName',
    );
    await file.writeAsString(json, flush: true);

    final share =
        widget.onShare ??
        (XFile shared) async {
          await SharePlus.instance.share(ShareParams(files: <XFile>[shared]));
        };
    await share(XFile(file.path));
  }
}

/// What the exported backup is called when it leaves the app.
///
/// Named rather than inlined because FR-M6 will read it back, and a file the
/// import side cannot recognise is a backup the learner cannot restore.
const String exportFileName = 'sogda-backup.json';

/// FR-S1-03: a full-screen, recoverable error. Never a blank screen.
///
/// Its own `MaterialApp`, because the failure may well be the database the
/// real one is built from — a theme resolved from settings that would not load
/// is not available here.
