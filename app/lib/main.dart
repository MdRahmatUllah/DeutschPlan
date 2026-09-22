import 'dart:async';

import 'package:deutschplan/features/bootstrap/bootstrap_error_screen.dart';
import 'package:deutschplan/features/splash/splash_screen.dart';
import 'package:flutter/foundation.dart' show kReleaseMode, debugPrint;
import 'package:deutschplan/bootstrap.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/theme/glass_capability.dart';
import 'package:deutschplan/core/theme/theme_mode.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/router/app_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is not in the main barrel in Riverpod 3.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'dart:ui' show PlatformDispatcher;

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

  // A `ProviderScope` at the true root, which riverpod_lint requires and which
  // S1 needs anyway now that it renders before bootstrap has produced a
  // container. Once there is a result, the `UncontrolledProviderScope` below
  // shadows this one for everything under it — that is the scope carrying
  // bootstrap's overrides, and the one every screen actually reads from.
  runApp(const ProviderScope(child: BootstrapHost()));
}

/// Shows S1 while [bootstrap] runs, then swaps in the real app.
class BootstrapHost extends StatefulWidget {
  const BootstrapHost({super.key, this.run});

  /// Overridden in tests. Defaults to the real [bootstrap].
  final Future<BootstrapResult> Function({Brightness platformBrightness})? run;

  @override
  State<BootstrapHost> createState() => _BootstrapHostState();
}

class _BootstrapHostState extends State<BootstrapHost> {
  Widget? _app;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final platform = PlatformDispatcher.instance;
    final result = await (widget.run ?? bootstrap)(
      platformBrightness: platform.platformBrightness,
    );

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

    // The system light/dark switch. Without this the theme notifier never
    // hears about it, and a learner following the platform would keep whatever
    // the phone was on when the app launched.
    if (result is BootstrapReady) {
      container
          .read(themeProvider.notifier)
          .platformBrightnessChanged(platform.platformBrightness);
      platform.onPlatformBrightnessChanged = () => container
          .read(themeProvider.notifier)
          .platformBrightnessChanged(platform.platformBrightness);
    }

    // FR-S1-02 is a budget, and a budget nobody can read is a budget nobody
    // keeps. One line in logcat, so the number is measurable on a device
    // rather than inferred from `am start -W` — which now reports the splash
    // frame rather than the time to Today.
    //
    // Debug *and* profile, never release: a debug build is JIT and its
    // numbers mean nothing against a 500 ms budget, so the only build worth
    // measuring is an AOT one.
    if (!kReleaseMode && result is BootstrapReady) {
      debugPrint('bootstrap: ${result.bootstrap.elapsed.inMilliseconds} ms');
    }

    if (!mounted) {
      container.dispose();
      return;
    }
    setState(() {
      _app = UncontrolledProviderScope(
        container: container,
        child: appFor(result),
      );
    });
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: supportedLocales,
        home: const SplashProgressGate(),
      );
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
/// Split out so the error path is something a widget test can build without a
/// disk behind it.
Widget appFor(BootstrapResult result) => switch (result) {
  // The providers #71 declares are overridden from here, so nothing has to
  // re-open what bootstrap already opened.
  BootstrapReady(:final bootstrap) => GlassCapabilityScope(
    notifier: bootstrap.glass,
    child: DeutschPlanApp(router: bootstrap.router),
  ),
  BootstrapFailed(:final failure) => BootstrapGate(failure: failure),
};

/// Supported UI languages, English first — see `supportedLocales` in [DeutschPlanApp].
const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('bn')];

class DeutschPlanApp extends ConsumerWidget {
  DeutschPlanApp({GoRouter? router, super.key})
    : router = router ?? buildRouter();

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
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: switch (mode) {
        // Glass has its own light and dark variants inside `AppTheme.glass`,
        // so the platform decides which one shows either way. #143 wires it.
        _ when followsPlatform || mode == DpMode.glass => ThemeMode.system,
        DpMode.light => ThemeMode.light,
        DpMode.dark => ThemeMode.dark,
        DpMode.glass => ThemeMode.system,
      },
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      // English first: gen_l10n orders supportedLocales alphabetically, which puts
      // Bangla first, and Flutter falls back to the FIRST supported locale when the
      // device locale matches none. `ui_language` defaults to `en`
      // (docs/02-data/user-database.md), so English has to lead.
      supportedLocales: supportedLocales,
    );
  }
}

/// FR-S1-03's *Retry*: re-runs [bootstrap] and swaps in whatever comes back.
///
/// Stateful rather than a callback into `main`, because the retry has to
/// replace the widget tree it is running inside — and because the disabled
/// buttons a callback-less error screen renders are not an error screen, they
/// are a dead end.
class BootstrapGate extends StatefulWidget {
  const BootstrapGate({required this.failure, this.onRetry, super.key});

  final BootstrapFailure failure;

  /// Overridden in tests, which have no disk to bootstrap against.
  final Future<BootstrapResult> Function()? onRetry;

  @override
  State<BootstrapGate> createState() => _BootstrapGateState();
}

class _BootstrapGateState extends State<BootstrapGate> {
  late BootstrapFailure _failure = widget.failure;
  Widget? _next;
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

    setState(() {
      _retrying = false;
      switch (result) {
        case BootstrapReady():
          _next = appFor(result);
        case BootstrapFailed(:final failure):
          _failure = failure;
      }
    });
  }

  @override
  Widget build(BuildContext context) =>
      _next ??
      BootstrapErrorApp(
        failure: _failure,
        onRetry: _retrying ? null : _retry,
        // #150 wires the share sheet; until then the button is offered only
        // where it can be honoured.
        onExport: _failure.canExport ? () {} : null,
      );
}

/// FR-S1-03: a full-screen, recoverable error. Never a blank screen.
///
/// Its own `MaterialApp`, because the failure may well be the database the
/// real one is built from — a theme resolved from settings that would not load
/// is not available here.
