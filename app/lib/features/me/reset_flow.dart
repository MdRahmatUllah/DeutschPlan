import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/components/sg_feedback.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/features/onboarding/onboarding_notifier.dart';
import 'package:sogda/features/study/study_session.dart';
import 'package:sogda/features/today/today_providers.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/router/routes.dart';

/// What M7's sheet leads to.
enum ResetChoice { exportFirst, step, everything }

/// The word the full reset is typed out with (FR-M7-02). The same in every
/// language: the Bangla text asks for RESET too.
const String resetWord = 'RESET';

/// M7 · Reset (`reset.md`, the ResetDialog artboards), from M3's Reset row:
/// a sheet with *Export first* (FR-M7-03), *Reset one step* and *Reset
/// everything*.
Future<void> openReset(BuildContext context) async {
  final choice = await Adaptive.showSheet<ResetChoice>(
    context: context,
    builder: (sheet) => const _ResetSheet(),
  );
  if (!context.mounted) return;
  switch (choice) {
    case ResetChoice.exportFirst:
      ExportImportRoute.open(context);
    case ResetChoice.step:
      await _resetStep(context);
    case ResetChoice.everything:
      await _resetEverything(context);
    case null:
      return;
  }
}

/// FR-M7-01: a step picked from those with something to reset, confirmed,
/// then reset; M3 stays.
Future<void> _resetStep(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  // Held, not M3's ref: Settings can close while the reset runs, and what
  // follows it must still happen (#679).
  final container = ProviderScope.containerOf(context, listen: false);
  final reset = container.read(resetRepositoryProvider);
  final List<({String code, bool current})> steps;
  try {
    steps = await reset.steps();
  } on Object catch (error) {
    // #692 ME-13: said, not silent; nothing was reset.
    debugPrint('reset steps: $error');
    if (context.mounted) SgToast.show(context, l10n.resetFailed);
    return;
  }
  if (!context.mounted) return;
  if (steps.isEmpty) {
    SgToast.show(context, l10n.resetNoStep);
    return;
  }
  final step = await Adaptive.showSheet<({String code, bool current})>(
    context: context,
    builder: (sheet) => _StepSheet(steps: steps),
  );
  if (step == null || !context.mounted) return;
  final sure = await Adaptive.showConfirm(
    context: context,
    title: l10n.resetStepTitle(step.code),
    message: <String>[
      l10n.resetStepMessage,
      if (step.current) l10n.resetStepCurrent(step.code),
    ].join(' '),
    confirmLabel: l10n.resetStepConfirm,
    cancelLabel: l10n.resetCancel,
    destructive: true,
  );
  if (sure != true || !context.mounted) return;
  final List<int> exams;
  try {
    exams = await reset.resetStep(
      step.code,
      today: container.read(todayProvider),
    );
  } on Object {
    if (context.mounted) SgToast.show(context, l10n.resetFailed);
    return;
  }
  await _dropRecordings(container, exams);
  // The plan engine and Today's plan were read before: the streams follow
  // drift, these don't.
  container
    ..invalidate(planEngineProvider)
    ..invalidate(todayPlanProvider);
  if (context.mounted) SgToast.show(context, l10n.resetStepDone(step.code));
}

/// FR-M7-02: the RESET dialog, then user.db as new but for the theme and
/// the language, the recordings gone, the models kept, and onboarding.
Future<void> _resetEverything(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  // Held, not M3's ref and context: the reset runs on if Settings closes,
  // and onboarding must open after it all the same (#679).
  final container = ProviderScope.containerOf(context, listen: false);
  final sure = await Adaptive.showTypedConfirm(
    context: context,
    title: l10n.resetEverythingTitle,
    message: l10n.resetEverythingMessage,
    word: resetWord,
    confirmLabel: l10n.resetEverythingConfirm,
    cancelLabel: l10n.resetCancel,
  );
  if (sure != true || !context.mounted) return;
  final router = GoRouter.of(context);
  try {
    await container.read(resetRepositoryProvider).resetEverything();
  } on Object {
    if (context.mounted) SgToast.show(context, l10n.resetFailed);
    return;
  }
  await _dropRecordings(container);
  // What is kept alive and read before: a setup draft, a session, the plan.
  container
    ..invalidate(planEngineProvider)
    ..invalidate(todayPlanProvider)
    ..invalidate(onboardingProvider)
    ..invalidate(studySessionProvider);
  OnboardingRoute.afterReset(router);
}

/// A row of M7's sheets: a title and its note, 48 dp at least.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.title,
    required this.onTap,
    this.note,
    this.color,
  });

  final String title;
  final String? note;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      container: true,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SgText(
                  title,
                  role: SgTextRole.body,
                  weight: 600,
                  color: color ?? tokens.color.ink,
                ),
                if (note case final note?)
                  SgText(
                    note,
                    role: SgTextRole.caption,
                    color: tokens.color.textSecondary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A sheet with a title over its rows, scrolling when they outgrow it.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(header: true, child: SgText(title, role: SgTextRole.title)),
        const SizedBox(height: 8),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    ),
  );
}

/// M7's sheet: *Export first* on top, before either reset (FR-M7-03).
class _ResetSheet extends StatelessWidget {
  const _ResetSheet();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    void choose(ResetChoice choice) => Navigator.of(context).pop(choice);
    return _Sheet(
      title: l10n.settingsReset,
      children: <Widget>[
        _Choice(
          title: l10n.resetExportFirst,
          note: l10n.resetExportFirstNote,
          color: tokens.color.link,
          onTap: () => choose(ResetChoice.exportFirst),
        ),
        _Choice(
          title: l10n.resetOneStep,
          note: l10n.resetOneStepNote,
          onTap: () => choose(ResetChoice.step),
        ),
        _Choice(
          title: l10n.resetEverything,
          note: l10n.resetEverythingNote,
          color: tokens.color.wrongText,
          onTap: () => choose(ResetChoice.everything),
        ),
      ],
    );
  }
}

/// FR-M7-01's picker: the steps with something to reset, the current one
/// named so.
class _StepSheet extends StatelessWidget {
  const _StepSheet({required this.steps});

  final List<({String code, bool current})> steps;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _Sheet(
      title: l10n.resetPickStep,
      children: <Widget>[
        for (final step in steps)
          _Choice(
            title: step.code,
            note: step.current ? l10n.learnCurrent : null,
            onTap: () => Navigator.of(context).pop(step),
          ),
      ],
    );
  }
}

/// The recordings go after the data, and best effort: the data is reset
/// either way, so a file the system holds must not report "nothing was
/// changed" nor stop the rest (#402's review).
///
/// ponytail: a leftover recording is a few hundred KB, cleared by the next
/// reset or an uninstall; a sweep at start if they ever pile up.
Future<void> _dropRecordings(
  ProviderContainer container, [
  List<int>? exams,
]) async {
  try {
    await container.read(modelRepositoryProvider).deleteRecordings(exams);
  } on Object catch (error) {
    debugPrint('reset: recordings not deleted: $error');
  }
}
