import 'package:deutschplan/bootstrap.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/theme/glass_capability.dart';
import 'package:deutschplan/core/theme/theme_mode.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'dart:ui' show PlatformDispatcher;

/// Entry point.
///
/// Everything that touches the disk happens in [bootstrap], before `runApp` —
/// FR-S1-01. The first frame is therefore already the right theme, with the
/// course attached and the settings in memory, and nothing on any screen is
/// waiting on I/O that should have finished here.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final result = await bootstrap(
    platformBrightness: PlatformDispatcher.instance.platformBrightness,
  );

  // ProviderScope at the very root, on both paths: riverpod_lint enforces it,
  // and the error screen's *Export progress* reads a repository too.
  runApp(ProviderScope(child: appFor(result)));
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
    child: DeutschPlanApp(
      mode: bootstrap.themeMode,
      followsPlatform: bootstrap.themeSetting.followsPlatform,
    ),
  ),
  BootstrapFailed(:final failure) => BootstrapGate(failure: failure),
};

/// Supported UI languages, English first — see `supportedLocales` in [DeutschPlanApp].
const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('bn')];

class DeutschPlanApp extends StatelessWidget {
  const DeutschPlanApp({
    required this.mode,
    this.followsPlatform = false,
    super.key,
  });

  /// Resolved in [bootstrap] against `theme_mode` and the platform, so the
  /// first frame is not a frame of the wrong theme.
  final DpMode mode;

  /// True when the learner chose *Follow the system*.
  ///
  /// [mode] is then only the answer for the first frame. `MaterialApp` has to
  /// keep following the platform afterwards, or turning the phone to dark
  /// would leave DeutschPlan light until it was killed.
  final bool followsPlatform;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
      home: const _Placeholder(),
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
class BootstrapErrorApp extends StatelessWidget {
  const BootstrapErrorApp({
    required this.failure,
    this.onRetry,
    this.onExport,
    super.key,
  });

  final BootstrapFailure failure;
  final VoidCallback? onRetry;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: supportedLocales,
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Builder(
                  builder: (context) {
                    final l10n = AppLocalizations.of(context);
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(switch (failure.step) {
                          BootstrapStep.database => l10n.bootstrapErrorDatabase,
                          BootstrapStep.content => l10n.bootstrapErrorContent,
                          BootstrapStep.settings => l10n.bootstrapErrorSettings,
                        }, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: onRetry,
                          child: Text(l10n.retry),
                        ),
                        // Only when user.db opened: the button has to do
                        // something, or it is a promise the screen cannot keep.
                        if (failure.canExport)
                          TextButton(
                            onPressed: onExport,
                            child: Text(l10n.exportProgress),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

// ponytail: placeholder shell so the app runs; replaced by the router shell in #67.
class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          AppLocalizations.of(context).loadingCourse,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
    );
  }
}
