import 'dart:async';

import 'package:sogda/bootstrap.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/components/sg_button.dart';
import 'package:sogda/core/components/sg_feedback.dart';
import 'package:sogda/core/theme/app_theme.dart';
import 'package:sogda/core/theme/aurora_backdrop.dart';
import 'package:sogda/core/theme/sg_surface.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/features/splash/splash_screen.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/main.dart'
    show appLocalizationsDelegates, supportedLocales;
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

  /// Null while a retry or an export runs. Answers whether the backup was
  /// handed over; when it wasn't, the screen says so (#652).
  final Future<bool> Function()? onExport;

  Future<void> _export(BuildContext context) async {
    if (await onExport!() || !context.mounted) return;
    SgToast.show(
      context,
      AppLocalizations.of(context).exportImportExportFailed,
    );
  }

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
    final panel = SgSurface(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SgText(
            _message(l10n),
            role: SgTextRole.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SgButton(label: l10n.retry, onPressed: onRetry),

          // FR-S1-03 offers a route into export, but only when there is
          // anything to export: `canExport` is true once user.db opened. A
          // button that cannot do what it says is worse than no button — the
          // learner taps it precisely because their data is what worries them.
          // A user.db that would not open still offers the file itself (#619).
          if (failure.canExport || failure.file != null) ...<Widget>[
            const SizedBox(height: 4),
            SgButton(
              label: failure.canExport
                  ? l10n.exportProgress
                  : l10n.bootstrapShareDataFile,
              onPressed: onExport == null
                  ? null
                  : () => unawaited(_export(context)),
              kind: SgButtonKind.text,
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
              // S1's lockup at 60 %: at full size it pushed *Export progress*
              // to the fold on a 360 × 640 phone.
              const ExcludeSemantics(child: SplashMark(scale: 0.6)),
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
    // #619: a newer build's file opens once the app is updated; retrying
    // this build fails for ever.
    BootstrapStep.database when failure.newer =>
      l10n.bootstrapErrorNewerDatabase,
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
    this.locale,
  });

  final BootstrapFailure failure;
  final VoidCallback? onRetry;
  final Future<bool> Function()? onExport;

  /// The learner's app language, when bootstrap read it before failing, as
  /// the splash showed it (#720). Null: the phone's language.
  final Locale? locale;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    locale: locale,
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: supportedLocales,
    home: BootstrapErrorScreen(
      failure: failure,
      onRetry: onRetry,
      onExport: onExport,
    ),
  );
}
