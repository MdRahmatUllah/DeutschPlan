import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/domain/exam_generator.dart';
import 'package:sogda/domain/exam_grading.dart'
    show connectorsUsed, targetsUsed, textWords;
import 'package:sogda/features/exam/exam_question_view.dart' show examTaskPanel;
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

/// L12's Writing (`exam-writing-speaking.md`, the ExamWriting artboard): the
/// task and its ten target words, which turn Lime as the text uses them
/// (FR-L12W-01); the text; and, live, its length against the level's
/// minimum (FR-L12W-02) and the connectors in it. The text is the runner's
/// typed answer, so it is kept in `exam_answers.given` and never leaves the
/// phone (FR-L12W-04).
class ExamWriting extends StatelessWidget {
  const ExamWriting({
    required this.task,
    required this.field,
    super.key,
    this.countPinned = false,
    this.typingLarge = false,
  });

  final WritingTask task;
  final TextEditingController field;

  /// The keyboard is up and the runner shows [ExamWritingCount] above it,
  /// where the button row was: under the field, it would scroll away with
  /// the task (#529).
  final bool countPinned;

  /// Typing past 130 % with the keyboard up: the field is 120 dp, not 150,
  /// to fit the room the pinned count line leaves in Bangla at 200 % (#590).
  final bool typingLarge;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final edge = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: tokens.color.ink, width: 2),
    );
    final topic = task.category ?? l10n.examWritingTopicFallback;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: field,
      builder: (context, value, _) {
        final text = value.text;
        final used = targetsUsed(text, task.targets).toSet();
        Widget panel(Widget child) => examTaskPanel(tokens, child);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Nodes of their own: merged, the task and the counts would be
            // read as the text field's label.
            Semantics(
              container: true,
              child: panel(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SgText(
                      <String>[
                        l10n.examWritingTask(task.level, topic),
                        l10n.examWritingUse,
                      ].join(' '),
                      role: SgTextRole.body,
                      weight: 600,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        for (final target in task.targets)
                          _Target(word: target, used: used.contains(target)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SgText(
                      l10n.examWritingUsed(
                        used.length,
                        task.targets.length,
                        task.minWords,
                        task.level,
                      ),
                      role: SgTextRole.caption,
                      color: tokens.color.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            SgText(
              l10n.examWritingYourText.toUpperCase(),
              role: SgTextRole.caption,
              weight: 700,
              letterSpacing: 0.6,
              color: tokens.color.textSecondary,
            ),
            const SizedBox(height: 6),
            // Typing past 130 %, 120 dp: in Bangla at 200 % the room between
            // the collapsed band and the pinned count line is 141, and a
            // fixed 150 put the field's top edge under the status bar. Its
            // text scrolls inside it either way (#590).
            SizedBox(
              height: typingLarge ? 120 : 150,
              child: TextField(
                controller: field,
                expands: true,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                // A tap on the task, the band or the chips closes the keyboard,
                // and *Previous* / *Submit text* come back: a multiline field
                // has no Done key, and iOS no back gesture that closes it
                // (#529). The umlaut keys are part of the field.
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                // An exam: the keyboard must not spell or complete the German,
                // as the runner's other typed answers don't let it.
                autocorrect: false,
                enableSuggestions: false,
                textAlignVertical: TextAlignVertical.top,
                style: SgText.styleFor(
                  tokens,
                  SgTextRole.body,
                ).copyWith(fontSize: 16, height: 22 / 16),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: tokens.surface.cardStrong,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: edge,
                  enabledBorder: edge,
                  focusedBorder: edge,
                  // "Your text" above is its own line; the hint is what a
                  // screen reader hears on the field, not a bare edit box.
                  hintText: l10n.examWritingFieldHint,
                ),
              ),
            ),
            if (!countPinned) ...<Widget>[
              const SizedBox(height: 6),
              ExamWritingCount(task: task, field: field),
            ],
          ],
        );
      },
    );
  }
}

/// Writing's live line: "N words · min 100", and the connectors found.
/// Under the field, or pinned above the keyboard while it is up (#529).
class ExamWritingCount extends StatelessWidget {
  const ExamWritingCount({required this.task, required this.field, super.key});

  final WritingTask task;
  final TextEditingController field;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: field,
      builder: (context, value, _) {
        final connectors = connectorsUsed(value.text, task.connectors);
        return Semantics(
          container: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SgText(
                l10n.examWritingCount(
                  textWords(value.text).length,
                  task.minWords,
                ),
                role: SgTextRole.caption,
                color: tokens.color.textSecondary,
              ),
              const SizedBox(width: 12),
              if (connectors.isNotEmpty)
                Expanded(
                  child: SgText(
                    l10n.examWritingConnectors(connectors.join(', ')),
                    role: SgTextRole.caption,
                    color: tokens.color.correctText,
                    textAlign: TextAlign.end,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A target word: an outline until the text uses it, then Lime with a tick.
class _Target extends StatelessWidget {
  const _Target({required this.word, required this.used});

  final String word;
  final bool used;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // Lime is light in both modes: its ink is Sun's, the dark one.
    final ink = used ? tokens.color.onAccent : tokens.color.ink;
    // A node each, so a screen reader steps through the words.
    return Semantics(
      container: true,
      label: used
          ? AppLocalizations.of(context).examWritingTargetUsed(word)
          : word,
      excludeSemantics: true,
      // The artboard's 26, grown with the text size: a fixed 26 cut
      // "Wohnung" at 150 % (#165).
      child: Container(
        height: SgScript.grow(context, 26),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: used ? tokens.color.easy : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: used ? ink : tokens.surface.outline,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (used) ...<Widget>[
              Icon(Icons.check, size: 12, color: ink),
              const SizedBox(width: 4),
            ],
            SgText(word, role: SgTextRole.caption, weight: 600, color: ink),
          ],
        ),
      ),
    );
  }
}
