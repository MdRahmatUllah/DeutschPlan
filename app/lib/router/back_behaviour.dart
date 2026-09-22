import 'dart:async';

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:material_ui/material_ui.dart';

/// Android back, inside the shell. `navigation.md`:
///
/// > **Android back**: pops the current route; on a tab root returns to
/// > Today; on Today exits (predictive back enabled).
///
/// `canPop` is what predictive back reads: true lets the system draw the
/// preview of the app closing, and it is only true on Today with nothing
/// pushed. Everywhere else this handles the press and the system draws
/// nothing — which is correct, because nothing is closing.
class ShellBackHandler extends StatelessWidget {
  const ShellBackHandler({
    required this.child,
    required this.onTabRoot,
    required this.goToFirstTab,
    required this.isFirstTab,
    super.key,
  });

  final Widget child;

  /// Whether the visible branch has nothing pushed on it.
  final bool Function() onTabRoot;

  /// Switches to Today.
  final VoidCallback goToFirstTab;

  /// Whether Today is the branch showing.
  final bool Function() isFirstTab;

  /// Whether a back press should close the app rather than be handled here.
  bool get _exits => isFirstTab() && onTabRoot();

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _exits,
    onPopInvokedWithResult: (didPop, _) {
      // `didPop` true means the system already did it — on Today, that is the
      // app closing, and there is nothing left to do.
      if (didPop) return;

      // Nothing here about popping a pushed route: the branch navigator is
      // inside this one and Flutter offers the press to the innermost
      // navigator first, so by the time this runs the branch is already at
      // its root. A `if (!onTabRoot()) return;` guard here was dead, and
      // planting proved it — removing it changed no test.
      goToFirstTab();
    },
    child: child,
  );
}

/// The exam runner's back. FR-L12-04 and `exam-runner.md`'s leave dialog.
///
/// Back does not pop: it asks. An exam is timed, and a stray back gesture
/// that dropped the learner out of one — losing the time rather than the
/// answers, which are saved per question — is the reason the dialog exists.
///
/// `canPop: false` is also what turns off the iOS edge swipe and the Android
/// predictive-back preview for this route, which is the rest of #69's
/// criteria: one mechanism, not three.
class ExamBackGuard extends StatefulWidget {
  const ExamBackGuard({required this.child, required this.onLeave, super.key});

  final Widget child;

  /// Called when the learner confirms. Abandoning the attempt and popping is
  /// the runner's job, not this widget's.
  final VoidCallback onLeave;

  @override
  State<ExamBackGuard> createState() => _ExamBackGuardState();
}

class _ExamBackGuardState extends State<ExamBackGuard> {
  /// Whether the dialog is already up.
  ///
  /// Not defensive coding. The handler is async and shows a dialog, so a
  /// second back press arriving while the first is still opening reaches
  /// `ModalRoute.willPop` mid-transition and trips a framework assertion —
  /// `'scope != null': is not true`. Two fast presses during a timed exam is
  /// an ordinary input, and in release the assertion is stripped and the
  /// behaviour is undefined rather than absent.
  var _asking = false;

  Future<void> _ask() async {
    if (_asking) return;
    setState(() => _asking = true);

    try {
      // A frame before the dialog goes up. Without it a second press landing
      // in the same frame reaches the dialog's route while it is still being
      // installed, and `ModalRoute.willPop` asserts `scope != null`. Waiting
      // means the second press finds the exam route still on top and is
      // swallowed by `_asking` above — which is the only place this app can
      // stop it.
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted) return;

      final l10n = AppLocalizations.of(context);
      final leave = await Adaptive.showConfirm(
        context: context,
        title: l10n.examLeaveTitle,
        message: l10n.examLeaveMessage,
        confirmLabel: l10n.examLeaveConfirm,
        cancelLabel: l10n.examLeaveCancel,
        destructive: true,
      );

      if ((leave ?? false) && mounted) widget.onLeave();
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) return;
      unawaited(_ask());
    },
    child: widget.child,
  );
}
