import 'dart:async';
import 'dart:io';

// The widgets layer is the SDK's own, so its delegate still comes from
// flutter_localizations; Material and Cupertino come from their packages.
import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter/foundation.dart' show kReleaseMode, debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is not in the main barrel in Riverpod 3.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sogda/bootstrap.dart';
import 'package:sogda/core/adaptive/orientation.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/app_theme.dart';
import 'package:sogda/core/theme/glass_capability.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/theme/system_bars.dart';
import 'package:sogda/data/repositories/backup_repository.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/features/bootstrap/bootstrap_error_screen.dart';
import 'package:sogda/features/splash/splash_screen.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/l10n/ui_language_locale.dart';
import 'package:sogda/router/app_router.dart';
import 'package:sogda/router/deep_links.dart' show readable, todayLink;
import 'package:sogda/services/background_tasks.dart';
import 'package:sogda/services/background_work.dart';
import 'package:sogda/services/reminder_notifications.dart';
import 'package:sogda/services/tts/tts_service.dart'
    show TtsService, VoiceRelease;
import 'package:sogda/services/widget_snapshot.dart';

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
    void Function(UiLanguage)? onUiLanguage,
    void Function()? onCourseUpdate,
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
  /// What the app on screen was built from: kept, not the widget, so the
  /// error screen follows a language a *Retry* read later (#720).
  BootstrapResult? _result;

  /// #577: a phone stays portrait, a tablet turns. Decided from the window's
  /// size as it comes, not before `runApp`, when it can still be empty, and
  /// again when it crosses the tablet line (a foldable, split screen).
  final OrientationLock _orientation = OrientationLock();

  /// The learner's language, once bootstrap has read it. Until then the
  /// splash follows the phone — there is nothing else to follow.
  Locale? _splashLocale;

  /// Whether an app update is copying its new course in: the splash says so,
  /// not "first start only" (#686 ST-9).
  bool _updatingCourse = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    didChangeMetrics();
    unawaited(_start());
  }

  @override
  void didChangeMetrics() {
    // The app's own window, not whichever view the engine lists first (#698).
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null) return;
    unawaited(_orientation.update(view.physicalSize / view.devicePixelRatio));
  }

  /// The system light/dark switch, heard as an observer (#644).
  ///
  /// Never by taking the dispatcher's `onPlatformBrightnessChanged`, as
  /// `main` once did: that callback is the framework's own. Replaced, the
  /// theme notifier heard the switch but the root `MediaQuery` never did, so
  /// the app's system theme mode kept the old brightness until some other
  /// metric changed.
  @override
  void didChangePlatformBrightness() {
    if (_ready) _tellBrightness(_container!);
  }

  /// #748: a link that arrives before the app is ready (the widget tapped
  /// during a first run's course copy), which the splash's own app would
  /// push as a named route and throw on. Kept, and opened by the router once
  /// the app is ready, under the same rules as any arrival.
  Uri? _pendingLink;

  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) {
    // #980: a link that can't be read goes on as Today's: as it is, every
    // observer after this one, and the router, would throw on it.
    // ponytail: the View's MediaQuery above the app is asked first, and
    // Flutter's default there logs a caught FormatException (logcat only);
    // silencing it means MainActivity rewriting the intent's data.
    final arrived = routeInformation.uri;
    final link = readable(arrived) ? arrived : todayLink;
    if (!_ready) {
      _pendingLink = link;
      return Future<bool>.value(true);
    }
    if (identical(link, arrived)) return Future<bool>.value(false);
    // Under the same rules as a platform push: a running exam holds.
    if (_result case BootstrapReady(:final bootstrap)) {
      bootstrap.router.go(link.toString());
    }
    return Future<bool>.value(true);
  }

  /// Tells the theme notifier the phone's brightness, which its own default
  /// can't know: a dark phone would otherwise get a light first frame.
  void _tellBrightness(ProviderContainer container) => container
      .read(themeProvider.notifier)
      .platformBrightnessChanged(
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
      );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Its own: an `UncontrolledProviderScope` leaves the container alone.
    _container?.dispose();
    super.dispose();
  }

  /// The container the app runs in: the first start's, or a retry's.
  ProviderContainer? _container;

  /// Whether [_container] is a ready app's, which has a theme to tell.
  bool _ready = false;

  Future<void> _start() async {
    final result = await _run();
    if (mounted) _adopt(result);
  }

  /// [bootstrap], or the test's stand-in: at launch, and again from the
  /// error screen's *Retry*.
  Future<BootstrapResult> _run() => (widget.run ?? bootstrap)(
    onUiLanguage: (ui) {
      if (mounted) setState(() => _splashLocale = ui.locale);
    },
    onCourseUpdate: () {
      if (mounted) setState(() => _updatingCourse = true);
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
      try {
        _tellBrightness(container);
        (widget.wire ?? wireApp)(container, result.bootstrap);
      } on Object {
        // Nothing half-built stays behind (#652). A retry's gate shows its
        // failure again, and disposes the result's database.
        container.dispose();
        rethrow;
      }
    }

    final previous = _container;
    setState(() {
      _container = container;
      _ready = result is BootstrapReady;
      _result = result;
    });
    if (result case BootstrapReady(:final bootstrap)) {
      if (_pendingLink case final link?) {
        _pendingLink = null;
        bootstrap.router.go(link.toString());
      }
    }
    // The failed start's. Nothing was opened through it, and it goes once
    // the frame that drops its tree has been built.
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  @override
  Widget build(BuildContext context) => switch ((_result, _container)) {
    (final result?, final container?) => UncontrolledProviderScope(
      // Keyed by its container: a retry replaces the whole tree, rather
      // than swapping the container under widgets that read the old one.
      key: ObjectKey(container),
      container: container,
      child: appFor(
        result,
        retry: _run,
        onReady: _adopt,
        locale: _splashLocale,
      ),
    ),
    _ => MaterialApp(
      debugShowCheckedModeBanner: false,
      // Platform brightness, because settings are exactly what bootstrap has
      // not read yet. It is also what the native launch window followed, so
      // the hand-off does not change colour.
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      locale: _splashLocale,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: supportedLocales,
      home: SplashProgressGate(updating: _updatingCourse),
    ),
  };
}

/// A ready app's plugins: the reminders, the home-screen widget, model
/// downloads and the voice. The light/dark switch is the host's own
/// (`didChangePlatformBrightness`, #644).
///
/// Once per app container, at launch or after a retry that worked (#643).
void wireApp(ProviderContainer container, Bootstrap bootstrap) {
  unawaited(
    startReminders(
      container,
      PlatformReminderNotifications(),
      const WorkmanagerWork(),
      widgets: const HomeWidgetStore(),
      open: bootstrap.router.go,
    ),
  );
  // FR-X1-01: the home-screen widget's snapshot, kept to today (#159).
  followWidget(container, const HomeWidgetStore());
  // FR-M4-01: model downloads carry on from where the app left them, and
  // report as they go (#156).
  unawaited(container.read(modelDownloadsProvider).attach());
  // #638: Supertonic opens on the first clip a screen needs, not here, and
  // lets go of its sessions in the background or under memory pressure.
  watchVoiceMemory(container);
  watchGlassTheme(container, bootstrap.glass);
  // FR-D3-03: old documents go after the start, never in its way (#1296).
  unawaited(deleteOldDocuments(container));
}

/// FR-D3-03 (#1296): at launch, the documents older than M3's *Delete
/// documents after* go, with their photos, as D3's *Delete* takes one. A
/// failure costs the clean-up, never the start: the next launch tries again.
Future<int> deleteOldDocuments(ProviderContainer container) => container
    .read(documentRepositoryProvider)
    .deleteOlderThan(
      container
          .read(settingsSourceProvider)
          .read(SettingKeys.docAutodeleteDays),
    )
    .catchError((Object error) {
      debugPrint('auto-delete: $error');
      return 0;
    });

/// #650: the glass frame watchdog watches only while glass is the theme, so
/// a slow frame in light or dark never turns a later glass opaque.
ProviderSubscription<SgMode> watchGlassTheme(
  ProviderContainer container,
  GlassCapability glass,
) => container.listen<SgMode>(
  themeProvider,
  (_, mode) => glass.glassOnScreen = mode == SgMode.glass,
  fireImmediately: true,
);

/// #638: the voice lets go of its sessions in the background and under
/// memory pressure, for the app's life. Only a voice a screen has built: a
/// pause before any speaker would otherwise build the whole TTS stack, a
/// player included, to release nothing (#906).
VoiceRelease watchVoiceMemory(ProviderContainer container) {
  final observer = VoiceRelease(() async {
    // The sessions are Supertonic's, whichever path opened them (#1035):
    // a speaker, through the service, or M4's voice chips, which speak to
    // the engine itself. In the app the two are one engine.
    if (container.exists(ttsProvider)) {
      await container.read(ttsProvider).release();
    } else if (container.exists(supertonicTtsProvider)) {
      await TtsService.releaseEngine(container.read(supertonicTtsProvider));
    }
  });
  WidgetsBinding.instance.addObserver(observer);
  return observer;
}

/// The daily reminder (#157) and the background tasks (#158): the plugins
/// set up, a tapped reminder opening what it links to, and the schedule kept
/// to the settings from now on.
///
/// A function a test can call: `main` is the one no test does. A plugin that
/// fails to start costs the reminder, never the app.
Future<StreamSubscription<SettingKey<Object?>>?> startReminders(
  ProviderContainer container,
  ReminderNotifications notifications,
  BackgroundWork work, {
  required WidgetStore widgets,
  required void Function(String location) open,
}) async {
  // #625: apart from the notifications, which the widget and the nightly
  // plan_pregenerate don't need: a notifications plugin that fails to
  // start must not leave them unqueued until the next launch.
  final background =
      startBackgroundWork(work, widgets, container.read(clockProvider)()).then(
        (_) => true,
        onError: (Object error) {
          debugPrint('background: $error');
          return false;
        },
      );
  // The link goes to the router as it is, not resolved here: the router
  // resolves it, and holds a running exam against it as against any
  // arrival (#676).
  try {
    await notifications.init(open);
    // A tap that started the app arrives here, not through [init]'s
    // callback, which hears only taps while it runs.
    if (await notifications.launchedWith() case final link?) open(link);
  } on Object catch (error) {
    debugPrint('reminders: $error');
    return null;
  }
  // The schedule queues reminder_compose, on the work started above.
  if (!await background) return null;
  // #626: and today's follows a day finished, or opened again, in the app.
  followReminder(container, notifications);
  return remindersFor(container, notifications, work).follow();
}

/// The app for a finished bootstrap, or FR-S1-03's error screen.
///
/// The error screen's *Retry* runs [retry], and hands a result that worked to
/// [onReady]: the host, which builds the app its own container (#643). The
/// error screen is in [locale], the app language bootstrap read, if it did
/// (#720).
Widget appFor(
  BootstrapResult result, {
  required void Function(BootstrapReady ready) onReady,
  required Future<BootstrapResult> Function() retry,
  Locale? locale,
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
    locale: locale,
  ),
};

/// Supported UI languages, English first — see `supportedLocales` in [SogdaApp].
/// Every [UiLanguage], so a new one needs no edit here (#1078).
final List<Locale> supportedLocales = <Locale>[
  for (final language in UiLanguage.values) language.locale,
];

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
    final followsPlatform = ref.watch(themeFollowsPlatformProvider);

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
    this.locale,
    super.key,
  });

  final BootstrapFailure failure;

  /// The learner's app language, if bootstrap read it (#720).
  final Locale? locale;

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
  final Future<void> Function(List<XFile> files)? onShare;

  @override
  State<BootstrapGate> createState() => _BootstrapGateState();
}

class _BootstrapGateState extends State<BootstrapGate> {
  late BootstrapFailure _failure = widget.failure;
  var _retrying = false;

  /// Set while a backup is being made (#652): Retry closes the database it
  /// reads, so the two never overlap, and a second tap makes no second file.
  var _exporting = false;

  /// Set once a retry has closed the failure's database (#652). A retry that
  /// then throws leaves this failure on screen, and an export of a closed
  /// database could only ever fail: Export stays off until a retry answers.
  var _closed = false;

  Future<void> _retry() async {
    if (_retrying || _exporting) return;
    setState(() => _retrying = true);

    BootstrapResult? result;
    try {
      // The database first (#652): the course file is attached to it, and a
      // content retry deletes that file.
      await _failure.dispose();
      _closed = true;
      // A content failure is nearly always a half-written or corrupt copy,
      // and retrying against the same file would fail identically for ever.
      if (_failure.step == BootstrapStep.content) {
        await resetInstalledContent();
      }

      result = await (widget.onRetry ?? bootstrap)();
      if (!mounted) {
        if (result case BootstrapReady(:final bootstrap)) {
          await bootstrap.dispose();
        }
        return;
      }

      switch (result) {
        case BootstrapReady():
          // `_retrying` stays set: the host swaps this tree on its next
          // frame, and until then Retry stays off, so a second tap can't
          // adopt a second app (#643).
          widget.onReady(result);
        case BootstrapFailed(:final failure):
          setState(() {
            _retrying = false;
            _failure = failure;
            _closed = false;
          });
      }
    } on Object catch (error) {
      // #652: a step that throws leaves Retry live, not dead. A ready result
      // whose app never took over is closed, rather than left holding
      // user.db open behind the next try.
      debugPrint('retry: $error');
      if (result case BootstrapReady(:final bootstrap)) {
        await bootstrap.dispose();
      }
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) => BootstrapErrorApp(
    failure: _failure,
    locale: widget.locale,
    onRetry: _retrying || _exporting ? null : _retry,
    onExport:
        (_failure.canExport || _failure.file != null) &&
            !_retrying &&
            !_exporting &&
            !_closed
        ? _export
        : null,
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
  ///
  /// Answers whether the backup was handed over, so the screen can say when
  /// it wasn't (#652): this is most likely the corrupt-database case the
  /// button exists for, and a throw used to vanish with no word.
  ///
  /// A database that never opened has no backup to make (#619): the file
  /// itself goes instead, with its write-ahead log when there is one, which
  /// holds whatever was saved since the last checkpoint.
  Future<bool> _export() async {
    final db = _failure.db;
    final raw = _failure.file;
    if ((db == null && raw == null) || _exporting) return true;
    setState(() => _exporting = true);
    try {
      final List<File> files;
      if (db != null) {
        final json = await BackupRepository(db).exportJson();
        final file = File(
          '${(await getTemporaryDirectory()).path}/$exportFileName',
        );
        await file.writeAsString(json, flush: true);
        files = <File>[file];
      } else {
        final wal = File('${raw!.path}-wal');
        files = <File>[raw, if (wal.existsSync()) wal];
      }

      final share =
          widget.onShare ??
          (List<XFile> shared) async {
            await SharePlus.instance.share(ShareParams(files: shared));
          };
      await share(<XFile>[for (final file in files) XFile(file.path)]);
      return true;
    } on Object catch (error) {
      debugPrint('export: $error');
      return false;
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

/// What the exported backup is called when it leaves the app.
///
/// Named rather than inlined because FR-M6 will read it back, and a file the
/// import side cannot recognise is a backup the learner cannot restore.
const String exportFileName = 'sogda-backup.json';
