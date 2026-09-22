import 'package:deutschplan/bootstrap.dart';
import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/features/splash/splash_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart' show supportedLocales;
import 'package:material_ui/material_ui.dart';

/// S1 · the bootstrap error state. FR-S1-03, `docs/04-screens/splash.md`.
///
/// > On bootstrap failure show a full-screen error with *Retry* and *Export
/// > progress* — never a blank screen.
///
/// A variant of S1 rather than a screen of its own: the issue points at the
/// same artboards, and the learner is looking at the splash when it fails. The
/// mark stays, the caption becomes the failure, and two actions appear under
/// it — so the screen changes without the app appearing to have crashed into
/// something else.
class BootstrapErrorScreen extends StatelessWidget {
  const BootstrapErrorScreen({
    required this.failure,
    super.key,
    this.onRetry,
    this.onExport,
  });

  final BootstrapFailure failure;

  /// Null while a retry is already running, which disables the button rather
  /// than hiding it — a button that vanishes under the finger reads as a crash.
  final VoidCallback? onRetry;

  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);

    // The message and the actions sit on a card rather than straight on the
    // field. Two reasons, both visible the moment it is rendered: a primary
    // button's fill *is* `primary`, so on the Lagoon field it vanishes into
    // the background and reads as an outline; and the text button's link
    // colour against Lagoon is far too low-contrast to be an affordance.
    // On paper both behave the way the Foundations artboard draws them.
    final panel = DpSurface(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DpText(
            _message(l10n),
            role: DpTextRole.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          DpButton(label: l10n.retry, onPressed: onRetry),

          // FR-S1-03 offers a route into export, but only when there is
          // anything to export: `canExport` is true once user.db opened. A
          // button that cannot do what it says is worse than no button — the
          // learner taps it precisely because their data is what worries them.
          if (failure.canExport) ...<Widget>[
            const SizedBox(height: 4),
            DpButton(
              label: l10n.exportProgress,
              onPressed: onExport,
              kind: DpButtonKind.text,
            ),
          ],
        ],
      ),
    );

    final body = SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const ExcludeSemantics(child: SplashMark()),
              const SizedBox(height: 40),
              panel,
            ],
          ),
        ),
      ),
    );

    return AdaptiveScaffold(
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.color.primary,
      body: tokens.isGlass
          ? AuroraBackdrop(leading: tokens.color.primary, child: body)
          : body,
    );
  }

  /// What went wrong, in the learner's language.
  ///
  /// Named per step rather than one message with the error in it: "could not
  /// open your data" and "could not install the course" call for different
  /// worries, and a stack trace on a splash screen helps nobody.
  String _message(AppLocalizations l10n) => switch (failure.step) {
    BootstrapStep.database => l10n.bootstrapErrorDatabase,
    BootstrapStep.content => l10n.bootstrapErrorContent,
    BootstrapStep.settings => l10n.bootstrapErrorSettings,
  };
}

/// [BootstrapErrorScreen] with the app scaffolding it needs.
///
/// Its own `MaterialApp`, because a failed bootstrap has no router and no
/// provider overrides — this is the one screen that has to render when nothing
/// else in the app can.
class BootstrapErrorApp extends StatelessWidget {
  const BootstrapErrorApp({
    required this.failure,
    super.key,
    this.onRetry,
    this.onExport,
  });

  final BootstrapFailure failure;
  final VoidCallback? onRetry;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: supportedLocales,
    home: BootstrapErrorScreen(
      failure: failure,
      onRetry: onRetry,
      onExport: onExport,
    ),
  );
}
