import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

/// The umlaut helper row, attached to every German text field.
///
/// `docs/03-domain/answer-checking.md`: "Umlaut helper row (ä ö ü ß, long-press
/// ß → ẞ) is a shared widget `UmlautBar` attached to every German text field."
///
/// It inserts at the cursor and preserves the selection, so a learner correcting
/// the middle of `Strasse` gets `Straße` rather than `Strasseß`.
class DpUmlautBar extends StatelessWidget {
  const DpUmlautBar({required this.controller, super.key, this.enabled = true});

  final TextEditingController controller;
  final bool enabled;

  /// From the ExamWriting artboard: 44 dp keys, radius 8, card fill, 1.5 px ink
  /// border, 20 px at weight 500, 8 dp apart.
  static const double keyHeight = 44;

  /// The four characters an English keyboard has no key for, each mapped to
  /// its capital.
  ///
  /// Long-press gives the capital on every key, not just ß. There is no ä on
  /// the keyboard to shift, and German capitalises every noun — Übung, Äpfel,
  /// Österreich are all A1 words whose first letter would otherwise be
  /// unreachable from this bar.
  static const Map<String, String> keys = <String, String>{
    'ä': 'Ä',
    'ö': 'Ö',
    'ü': 'Ü',
    'ß': 'ẞ',
  };

  /// The capital sharp s exists in Unicode and on no keyboard at all.
  static const String capitalSharpS = 'ẞ';

  /// Inserts [text] at the cursor, replacing any selection, and leaves the
  /// caret after it.
  static void insert(TextEditingController controller, String text) {
    final value = controller.value;
    final selection = value.selection;

    // A field that has never been focused reports an invalid selection; append.
    if (!selection.isValid) {
      final appended = value.text + text;
      controller.value = TextEditingValue(
        text: appended,
        selection: TextSelection.collapsed(offset: appended.length),
      );
      return;
    }

    final replaced = value.text.replaceRange(
      selection.start,
      selection.end,
      text,
    );
    controller.value = TextEditingValue(
      text: replaced,
      selection: TextSelection.collapsed(offset: selection.start + text.length),
      composing: TextRange.empty,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Row(
      children: <Widget>[
        for (final (index, entry) in keys.entries.indexed) ...<Widget>[
          if (index > 0) SizedBox(width: tokens.spacing.sm),
          Expanded(
            child: _UmlautKey(
              label: entry.key,
              shifted: entry.value,
              onTap: enabled ? () => insert(controller, entry.key) : null,
              onLongPress: enabled
                  ? () => insert(controller, entry.value)
                  : null,
            ),
          ),
        ],
      ],
    );
  }
}

class _UmlautKey extends StatelessWidget {
  const _UmlautKey({
    required this.label,
    required this.shifted,
    required this.onTap,
    required this.onLongPress,
  });

  final String label;
  final String shifted;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return AdaptiveTapTarget(
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: AppLocalizations.of(context).umlautLongPressHint(label, shifted),
        onTap: onTap,
        onLongPress: onLongPress,
        child: ExcludeSemantics(
          child: GestureDetector(
            onTap: onTap,
            onLongPress: onLongPress,
            behavior: HitTestBehavior.opaque,
            // The artboard's height at least, taller at large text: a fixed one
            // cut "ä" at 150 % (#165).
            child: Container(
              constraints: const BoxConstraints(
                minHeight: DpUmlautBar.keyHeight,
              ),
              decoration: BoxDecoration(
                color: tokens.surface.card,
                borderRadius: BorderRadius.circular(tokens.shape.chip),
                border: Border.all(
                  color: tokens.color.ink,
                  width: tokens.surface.outlineWidth,
                ),
              ),
              // Its own height, centred: an Align would fill a tall parent.
              child: Center(
                heightFactor: 1,
                child: DpText(label, role: DpTextRole.title, weight: 500),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A note with a coloured bar down its left edge.
///
/// The artboards use it for grammar "Watch out" and for interference tips —
/// "⚠ bekommen = to get, not 'to become'" — both with the Tangerine bar.
///
/// It draws its own container rather than a [DpSurface]: the GrammarTopic
/// artboard gives it an Oat fill at radius 12 with no border and no shadow,
/// because it sits *inside* a card rather than being one.
class DpCallout extends StatelessWidget {
  const DpCallout({required this.child, super.key, this.colour, this.title});

  DpCallout.text(String text, {Key? key, Color? colour, String? title})
    : this(key: key, colour: colour, title: title, child: _CalloutText(text));

  final Widget child;

  /// Defaults to Tangerine, which is what both documented uses draw.
  final Color? colour;

  final String? title;

  /// The artboard draws a 6 px bar.
  static const double barWidth = 6;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final bar = colour ?? tokens.color.hard;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface.muted,
        borderRadius: BorderRadius.circular(tokens.shape.button),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.shape.button),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                width: barWidth,
                child: ColoredBox(color: bar),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(tokens.spacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (title != null) ...<Widget>[
                        DpText(title!, role: DpTextRole.label, weight: 700),
                        SizedBox(height: tokens.spacing.xs),
                      ],
                      child,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalloutText extends StatelessWidget {
  const _CalloutText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      DpText(text, role: DpTextRole.body, allowBreaks: true);
}

/// The single rendering for a failed load.
///
/// `docs/01-architecture/state-management.md`: "Errors: `AsyncValue.error`
/// renders the shared `ErrorPanel` with Retry." Every screen uses this one, so
/// a failure looks the same everywhere and Retry always exists.
class DpErrorPanel extends StatelessWidget {
  const DpErrorPanel({
    required this.message,
    required this.retryLabel,
    super.key,
    this.onRetry,
    this.detail,
    this.action,
  });

  final String message;
  final String retryLabel;
  final VoidCallback? onRetry;

  /// Shown under the message, smaller. Never a raw exception string — a learner
  /// cannot act on a stack trace.
  final String? detail;

  /// A second action beside Retry. The bootstrap failure adds "Export progress"
  /// so a learner can rescue their data when the app will not start.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Semantics(
      liveRegion: true,
      child: DpSurface(
        padding: EdgeInsets.all(tokens.spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            DpText(message, role: DpTextRole.title),
            if (detail != null) ...<Widget>[
              SizedBox(height: tokens.spacing.sm),
              DpText(
                detail!,
                role: DpTextRole.body,
                color: tokens.color.textSecondary,
              ),
            ],
            SizedBox(height: tokens.spacing.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child: DpButton(
                    label: retryLabel,
                    kind: DpButtonKind.secondary,
                    onPressed: onRetry,
                  ),
                ),
                if (action != null) ...<Widget>[
                  SizedBox(width: tokens.spacing.md),
                  Expanded(child: action!),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// How an answer was judged. `business-rules.md` BR-ANS-01…04.
enum DpVerdict { correct, almost, wrongArticle, wrong }

/// The verdict line under a quiz, cloze or exam answer.
///
/// `accessibility-performance.md`: "Never colour alone: articles printed,
/// statuses labelled, verdicts have icons and words." So every verdict renders
/// an icon *and* text, and the colour is the third signal, not the only one.
class DpVerdictRow extends StatelessWidget {
  const DpVerdictRow({
    required this.verdict,
    required this.message,
    super.key,
    this.emphasis = const <String>[],
  });

  final DpVerdict verdict;

  /// "Correct", "Almost — watch the spelling: der Mietvertrag", "die, not der".
  final String message;

  /// The parts of [message] set in ink rather than the verdict's colour — the
  /// answer, as the QuizRunner artboard sets "der Mietvertrag". Found in
  /// order: a translation may put text around them, but must keep them in
  /// this order.
  final List<String> emphasis;

  /// `correct` and `wrong` are a tick and a cross in the artboard, which
  /// Material has. `almost` is the mathematical "approximately equal" sign, and
  /// Material has no glyph for it — it renders as text instead of a near-miss
  /// icon that means something else.
  IconData? get icon => switch (verdict) {
    DpVerdict.correct => Icons.check,
    DpVerdict.almost => null,
    DpVerdict.wrongArticle || DpVerdict.wrong => Icons.close,
  };

  /// The artboard's own mark for [DpVerdict.almost].
  static const String almostGlyph = '≈';

  /// All three marks are 18 in the artboard while the words beside them are 15.
  /// They are marks, not text, so the glyph is sized like the icons rather than
  /// taking whatever the type scale happens to offer.
  static const double markSize = 18;

  Color colourFrom(DpPalette palette) => switch (verdict) {
    DpVerdict.correct => palette.correctText,
    DpVerdict.almost => palette.almostText,
    DpVerdict.wrongArticle || DpVerdict.wrong => palette.wrongText,
  };

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colour = colourFrom(tokens.color);

    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (icon != null)
            Icon(icon, size: markSize, color: colour)
          else
            SizedBox(
              width: markSize,
              child: Text(
                almostGlyph,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: markSize, color: colour),
              ),
            ),
          SizedBox(width: tokens.spacing.sm),
          Expanded(
            child: emphasis.isEmpty
                ? DpText(
                    message,
                    role: DpTextRole.body,
                    weight: 600,
                    color: colour,
                  )
                : Text.rich(
                    TextSpan(children: _spans(tokens.color.ink)),
                    style: DpText.styleFor(
                      tokens,
                      DpTextRole.body,
                      color: colour,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
          ),
        ],
      ),
    );
  }
}

extension on DpVerdictRow {
  List<InlineSpan> _spans(Color ink) {
    final spans = <InlineSpan>[];
    var at = 0;
    for (final part in emphasis) {
      final found = part.isEmpty ? -1 : message.indexOf(part, at);
      if (found < 0) continue;
      if (found > at) spans.add(TextSpan(text: message.substring(at, found)));
      spans.add(
        TextSpan(
          text: part,
          style: TextStyle(color: ink),
        ),
      );
      at = found + part.length;
    }
    if (at < message.length) spans.add(TextSpan(text: message.substring(at)));
    return spans;
  }
}

/// The one snackbar the artboards draw (StudyNew): inverse — ink with paper
/// text in light mode, the other way round in dark — 8 px corners, a soft
/// shadow, and the action in [DpPalette.inverseLink].
///
/// One at a time: a queue of bars is a queue the learner cannot use, because
/// the older ones expire while they read.
void _showInverse(
  BuildContext context, {
  required String message,
  required Duration duration,
  SnackBarAction? action,
  double lift = 0,
}) {
  final tokens = context.tokens;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: duration,
        // A bar with an action persists by default; ours time out (#319,
        // FR-T2-02's 4 s), except for a screen-reader user, who needs the
        // time to reach it (WCAG 2.2.1), as Flutter's own rule has it.
        persist: MediaQuery.accessibleNavigationOf(context),
        backgroundColor: tokens.color.ink,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, 10 + lift),
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.shape.chip),
        ),
        content: DpText(
          message,
          role: DpTextRole.body,
          color: tokens.surface.paper,
        ),
        action: action,
      ),
    );
}

/// A short note that something happened: "Copied".
abstract final class DpToast {
  static const Duration duration = Duration(seconds: 2);

  /// [lift] floats it clear of a thumb zone, as [DpUndo.show]'s does.
  ///
  /// An [actionLabel] with [onAction] is a link — the TTS fallback's Settings
  /// (#153) — and stays [DpUndo.duration], long enough to reach.
  static void show(
    BuildContext context,
    String message, {
    double lift = 0,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final action = actionLabel == null || onAction == null
        ? null
        : SnackBarAction(
            label: actionLabel,
            textColor: context.tokens.color.inverseLink,
            onPressed: onAction,
          );
    _showInverse(
      context,
      message: message,
      duration: action == null ? duration : DpUndo.duration,
      lift: lift,
      action: action,
    );
  }
}

/// The shared undo affordance.
///
/// Rating, skipping and every word action show one. Four seconds, one action,
/// and the same shape everywhere so a learner learns it once.
abstract final class DpUndo {
  /// FR-T2-02: "a 4 s snackbar *Undo* MUST revert it fully".
  static const Duration duration = Duration(seconds: 4);

  /// The label is read from ARB rather than passed in: it is the same word at
  /// every call site, and a parameter is a chance to pass an unlocalised one.
  ///
  /// [lift] floats it clear of a screen's thumb zone: the StudyNew artboard
  /// holds it 128 px up, above *Show meaning*, rather than over it.
  static void show(
    BuildContext context, {
    required String message,
    required VoidCallback onUndo,
    double lift = 0,
  }) {
    _showInverse(
      context,
      message: message,
      duration: duration,
      lift: lift,
      action: SnackBarAction(
        label: AppLocalizations.of(context).undo,
        textColor: context.tokens.color.inverseLink,
        onPressed: onUndo,
      ),
    );
  }
}
