import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/components/sg_chip.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/data/repositories/backup_repository.dart';
import 'package:sogda/data/repositories/setting_keys.dart' show UiLanguage;
import 'package:sogda/features/me/export_import_screen.dart';
import 'package:sogda/features/onboarding/onboarding_shell.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/l10n/ui_language_locale.dart';
import 'package:sogda/services/start_report.dart';

/// S2 page 1 · Welcome. `OnboardingWelcome-android.html`.
///
/// Three promises and one button, under the app language (#1078): the first
/// thing a learner reads, in a list where each language names itself, and
/// the rest of setup reads in it. Written as it is tapped. The page has no
/// *Skip*: the language is already the phone's, or English (bootstrap).
///
/// And *Restore a backup* (#822, the owner's option 3): a learner moving
/// phones brings their data in before setup writes a setting of its own.
/// The file replaces this phone's data, as M6's *Replace* does: there is
/// nothing here yet to keep.
class OnboardingWelcomePage extends StatefulWidget {
  const OnboardingWelcomePage({super.key, this.onStart, this.onRestored});

  final VoidCallback? onStart;

  /// After a restore that brought in a step: Today, skipping the rest of
  /// setup. A file with none carries on to page 2 ([onStart]). Null hides
  /// the link: restart setup, where a Replace would take the progress.
  final VoidCallback? onRestored;

  @override
  State<OnboardingWelcomePage> createState() => _OnboardingWelcomePageState();
}

class _OnboardingWelcomePageState extends State<OnboardingWelcomePage> {
  bool _busy = false;
  String? _error;

  /// The file picked, then imported as the phone's data. Nothing is written
  /// for a file that isn't a backup, or one from a newer Sogda (FR-M6-02).
  Future<void> _restore() async {
    final l10n = AppLocalizations.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      final file = await container.read(backupFilesProvider).pick();
      if (file == null) return;
      await importBackup(container, file.json, ImportMode.replace);
      final enrolled = await container
          .read(planRepositoryProvider)
          .hasEnrollment();
      if (!mounted) return;
      (enrolled ? widget.onRestored : widget.onStart)?.call();
    } on ImportException catch (refused) {
      error = refused.reason == ImportRefusal.newerSchema
          ? l10n.exportImportNewer
          : l10n.exportImportNotABackup;
    } on FormatException {
      // Not text, or too big to be a backup (#657).
      error = l10n.exportImportNotABackup;
    } on Object catch (failed) {
      debugPrint('restore: $failed');
      error = l10n.exportImportFailed;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    // #462: a first run's cold start ends here, drawn with its first frame.
    StartReport.fullyDrawn();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return OnboardingShell(
      page: OnboardingPage.welcome,
      headline: l10n.onboardingWelcomeHeadline,
      headerArt: const _RisingChart(),
      primaryLabel: l10n.onboardingWelcomeStart,
      onPrimary: widget.onStart,
      busy: _busy,
      error: _error,
      secondaryLabel: widget.onRestored == null
          ? null
          : l10n.onboardingRestoreBackup,
      onSecondary: () => unawaited(_restore()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: 4),
          const _AppLanguage(),
          _Promise(
            icon: Icons.download_outlined,
            text: l10n.onboardingPromiseOffline,
          ),
          _Promise(
            icon: Icons.shield_outlined,
            text: l10n.onboardingPromiseSteps,
          ),
          _Promise(
            icon: Icons.lock_outline,
            text: l10n.onboardingPromisePrivate,
          ),
        ],
      ),
    );
  }
}

/// The app language, each named in itself (#1078).
class _AppLanguage extends ConsumerWidget {
  const _AppLanguage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final ui = ref.watch(languagesProvider).ui;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SgText(
            l10n.settingsUiLanguage,
            role: SgTextRole.caption,
            weight: 700,
            color: tokens.color.textSecondary,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            // Rows apart by their targets, so a screen reader reads them as
            // drawn when larger text wraps them (#952).
            runSpacing: AdaptiveTapTarget.runSpacing(32),
            children: <Widget>[
              for (final language in UiLanguage.values)
                SgChip(
                  label: language.nativeName,
                  kind: SgChipKind.filter,
                  selected: language == ui,
                  onTap: () => unawaited(
                    ref.read(languagesProvider.notifier).setUi(language),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One promise: a Sun tile with an icon, and the sentence beside it.
class _Promise extends StatelessWidget {
  const _Promise({required this.icon, required this.text});

  final IconData icon;
  final String text;

  static const double tile = 36;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            width: tile,
            height: tile,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.color.accent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tokens.color.ink, width: 1.5),
            ),
            child: Icon(icon, size: 18, color: tokens.color.onAccent),
          ),
          const SizedBox(width: 12),
          Expanded(child: SgText(text, role: SgTextRole.body)),
        ],
      ),
    );
  }
}

/// The dotted rising line with its milestones and a flag at the end.
///
/// A painter rather than an asset: it is drawn in ink and Sun, so it has to
/// follow the theme into dark and glass, and an exported PNG could not.
class _RisingChart extends StatelessWidget {
  const _RisingChart();

  static const Size artboard = Size(390, 120);

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return SizedBox(
      height: artboard.height,
      child: CustomPaint(
        painter: _RisingChartPainter(
          // The header's ink, so the line stays visible under glass-dark.
          line: OnboardingPage.welcome.headerInk(tokens),
          start: tokens.color.accent,
          milestone: tokens.surface.card,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _RisingChartPainter extends CustomPainter {
  const _RisingChartPainter({
    required this.line,
    required this.start,
    required this.milestone,
  });

  final Color line;
  final Color start;
  final Color milestone;

  /// The artboard's milestones, in its 390 × 120 space. They sit near the
  /// wave rather than on it — the artboard places them by hand.
  static const List<Offset> _points = <Offset>[
    Offset(28, 96),
    Offset(60, 84),
    Offset(92, 92),
    Offset(124, 76),
    Offset(156, 84),
    Offset(188, 66),
    Offset(220, 74),
    Offset(252, 56),
    Offset(284, 62),
    Offset(312, 44),
    Offset(340, 50),
    Offset(366, 30),
  ];

  /// The artboard's wave: `M28 96C50 60 70 110 92 92s40-40 64-16 40 30 64-10
  /// 44 20 64-10 50 0 84-26`, with each `s` written out as the `C` it
  /// abbreviates — its first control point is the previous second one,
  /// reflected through the join.
  static Path get _wave => Path()
    ..moveTo(28, 96)
    ..cubicTo(50, 60, 70, 110, 92, 92)
    ..cubicTo(114, 74, 132, 52, 156, 76)
    ..cubicTo(180, 100, 196, 106, 220, 66)
    ..cubicTo(244, 26, 264, 86, 284, 56)
    ..cubicTo(304, 26, 334, 56, 368, 30);

  @override
  void paint(Canvas canvas, Size size) {
    // Stretched across, not scaled: the block is 120 tall at every width, so
    // on a tablet the wave widens and the dots keep their size.
    final scale = size.width / _RisingChart.artboard.width;
    final stretch = Matrix4.diagonal3Values(scale, 1, 1).storage;
    Offset at(Offset point) => Offset(point.dx * scale, point.dy);

    final stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // `stroke-dasharray: 6 8`, measured along the stretched curve so the
    // dashes stay 6 dp long whatever the width. Flutter has no dashed stroke;
    // `PathMetric.extractPath` is the stock way to cut one.
    for (final metric in _wave.transform(stretch).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 6 + 8) {
        canvas.drawPath(metric.extractPath(d, d + 6), stroke);
      }
    }

    for (final point in _points) {
      final centre = at(point);
      canvas
        ..drawCircle(
          centre,
          6,
          Paint()..color = point == _points.first ? start : milestone,
        )
        ..drawCircle(centre, 6, stroke);
    }

    // The flag at the summit: `M352 22l14-6v22l-14 6z`, which puts it just
    // behind the last dot. Anchored to that dot rather than stretched, so it
    // stays a flag on a tablet instead of widening into a banner.
    final tip = at(_points.last);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx - 14, tip.dy - 8)
        ..lineTo(tip.dx, tip.dy - 14)
        ..lineTo(tip.dx, tip.dy + 8)
        ..lineTo(tip.dx - 14, tip.dy + 14)
        ..close(),
      Paint()..color = start,
    );
  }

  @override
  bool shouldRepaint(_RisingChartPainter old) =>
      old.line != line || old.start != start || old.milestone != milestone;
}
