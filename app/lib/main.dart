import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/glass_capability.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Entry point. Real bootstrap work (opening user.db, copying content.db,
/// loading settings, resolving the theme) lands in `bootstrap.dart` — see
/// docs/04-screens/splash.md, FR-S1-01.
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Glass asks the platform whether it will blur, and watches real frame
  // timings so a struggling device drops to the opaque surface instead of
  // stuttering. Both are cheap and neither blocks the first frame.
  final glass = GlassCapability()
    ..startFrameWatchdog()
    ..queryPlatform();

  // ProviderScope stays at the very root (riverpod_lint enforces it); the glass
  // capability sits just inside so every DpSurface can reach it.
  runApp(
    ProviderScope(
      child: GlassCapabilityScope(
        notifier: glass,
        child: const DeutschPlanApp(),
      ),
    ),
  );
}

/// Supported UI languages, English first — see `supportedLocales` in [DeutschPlanApp].
const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('bn')];

class DeutschPlanApp extends StatelessWidget {
  const DeutschPlanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // theming.md: the default follows the system light/dark setting. The
      // learner's explicit choice (theme_mode, incl. Glass) arrives with
      // Settings in #143.
      themeMode: ThemeMode.system,
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
