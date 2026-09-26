import 'dart:async';

import 'package:deutschplan/core/components/dp_speaker_button.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/domain/quiz_builder.dart';
import 'package:deutschplan/features/study/study_cloze.dart'
    show StudyAnswerField;
import 'package:deutschplan/features/words/speak.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// What an item asks, as its chip names it.
String askName(AppLocalizations l10n, QuizItem item) =>
    switch (item.direction) {
      QuizDirection.compare => l10n.quizAskCompare,
      _ when item.tiles => l10n.quizAskPick,
      QuizDirection.deEn || QuizDirection.deBn => l10n.quizAskMeaning,
      QuizDirection.enDe => l10n.quizAskGerman,
      QuizDirection.articles => l10n.quizAskArticle,
      QuizDirection.listening => l10n.quizAskListening,
      QuizDirection.forms || QuizDirection.mixed => l10n.quizAskForm,
    };

/// The three buttons of an articles item, in the order the app teaches them.
const List<String> articles = <String>['der', 'die', 'das'];

/// Whether the answer is typed German, which gets the umlaut row.
bool typesGerman(QuizItem item) => switch (item.direction) {
  QuizDirection.enDe || QuizDirection.listening || QuizDirection.forms => true,
  _ => false,
};

/// One quiz item as it is asked (`quiz.md`, #124): the prompt, and the way
/// to answer it — a field, four tiles (DE → বাংলা) or the three article
/// buttons. L8 shows it with a verdict under it; L12 (#130) without.
class QuizItemView extends ConsumerWidget {
  const QuizItemView({
    required this.item,
    required this.field,
    required this.onAnswer,
    super.key,
    this.picked,
    this.typing = false,
  });

  final QuizItem item;

  /// The keyboard is up at large text: the "YOUR ANSWER" caption gives its
  /// room to the prompt, as the field's hint says as much (#554).
  final bool typing;

  /// The typed answer; unused by tiles and article buttons.
  final TextEditingController field;

  /// A tile or an article button answers at once; the field on done.
  final ValueChanged<String> onAnswer;

  /// The tile or article picked, shown selected. The screen decides what a
  /// second tap means: L8 ignores it once graded; L12 lets it change the
  /// answer.
  final String? picked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);

    final prompt = switch (item.direction) {
      // The word is the answer, so it is only heard.
      QuizDirection.listening => Align(
        alignment: AlignmentDirectional.centerStart,
        child: DpSpeakerButton(
          size: 64,
          state: speakerState(ref, item.prompt),
          semanticLabel: l10n.quizAskListening,
          onPressed: () => unawaited(say(ref, context, item.prompt)),
        ),
      ),
      // A compare item's sentence, with the gap, over its English (FR-W2-03).
      QuizDirection.enDe || QuizDirection.compare => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          DpText(item.prompt, role: DpTextRole.headline, weight: 600),
          if (item.hint case final hint? when hint.isNotEmpty)
            DpText(
              hint,
              role: DpTextRole.bodyLarge,
              color: tokens.color.textSecondary,
            ),
        ],
      ),
      QuizDirection.forms => DpText(
        switch (item.form) {
          FormLabel.plural => l10n.quizFormPlural(item.prompt),
          FormLabel.thirdPerson => l10n.quizFormThirdPerson(item.prompt),
          FormLabel.perfekt => l10n.quizFormPerfekt(item.prompt),
          FormLabel.comparative => l10n.quizFormComparative(item.prompt),
          FormLabel.superlative => l10n.quizFormSuperlative(item.prompt),
          null => item.prompt,
        },
        role: DpTextRole.headline,
        weight: 600,
      ),
      // German: the word, and a speaker to hear it.
      _ => Row(
        children: <Widget>[
          Flexible(child: GermanWord(item.prompt)),
          const SizedBox(width: 12),
          DpSpeakerButton(
            state: speakerState(ref, item.prompt),
            semanticLabel: l10n.quizPlay,
            onPressed: () => unawaited(say(ref, context, item.prompt)),
          ),
        ],
      ),
    };

    final Widget answer;
    if (item.direction == QuizDirection.articles) {
      answer = ArticleButtons(picked: picked, onPick: onAnswer);
    } else if (item.tiles) {
      answer = ChoiceTiles(
        options: item.options,
        picked: picked,
        onPick: onAnswer,
      );
    } else {
      answer = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (!typing) ...<Widget>[
            DpText(
              l10n.quizYourAnswer.toUpperCase(),
              role: DpTextRole.caption,
              weight: 700,
              letterSpacing: 0.6,
              color: tokens.color.textSecondary,
            ),
            const SizedBox(height: 8),
          ],
          StudyAnswerField(
            controller: field,
            hint: l10n.quizYourAnswer,
            onSubmitted: () => onAnswer(field.text),
            dense: typing,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        prompt,
        // Typing past 130 %, 12 dp of the gap go to a two-line prompt, which
        // otherwise lost the top of its first line under the strip (#561).
        // A long meaning over its Bangla (three or four lines) fits too:
        // Check is a key on the umlaut row, the strip goes and the field's
        // padding closes (#568).
        // ponytail: past four lines at 200 % it still loses its top; the list
        // sits at its end then, so the next lever is the prompt's own size.
        SizedBox(height: typing ? 8 : 20),
        answer,
      ],
    );
  }
}

/// A German word with its article in the gender's colour, as the app writes
/// every noun: a [DpHeadword] at 600, so a long compound breaks at a soft
/// hyphen rather than mid-syllable, and is read out without it (#405).
class GermanWord extends StatelessWidget {
  const GermanWord(this.word, {super.key, this.role = DpTextRole.headline});

  final String word;
  final DpTextRole role;

  @override
  Widget build(BuildContext context) {
    final space = word.indexOf(' ');
    final first = space < 0 ? '' : word.substring(0, space);
    final article = const <String>{'der', 'die', 'das'}.contains(first)
        ? first
        : null;
    return DpHeadword(
      article == null ? word : word.substring(space + 1),
      article: article,
      role: role,
      weight: 600,
    );
  }
}

/// Four tiles to pick one of (L8's DE → বাংলা, L12's choices).
class ChoiceTiles extends StatelessWidget {
  const ChoiceTiles({
    required this.options,
    required this.picked,
    required this.onPick,
    super.key,
  });

  final List<String> options;

  /// The one picked, shown selected; null for none.
  final String? picked;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      for (final option in options)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _Choice(
            selected: picked == option,
            onTap: () => onPick(option),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: DpText(option, role: DpTextRole.bodyLarge, weight: 600),
            ),
          ),
        ),
    ],
  );
}

/// der · die · das: three big buttons in their genders' colours, as the
/// ExamRunner artboard draws them (L8's articles, L12's Articles).
class ArticleButtons extends StatelessWidget {
  const ArticleButtons({required this.picked, required this.onPick, super.key});

  /// The article picked, shown selected; null for none.
  final String? picked;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      children: <Widget>[
        for (final (index, article) in articles.indexed) ...<Widget>[
          if (index > 0) const SizedBox(width: 12),
          Expanded(
            child: _Choice(
              // Solid, not tinted: the artboard fills each button.
              kind: DpSurfaceKind.tint(switch (article) {
                'der' => tokens.color.der,
                'die' => tokens.color.die,
                _ => tokens.color.das,
              }, opacity: 1),
              height: 40,
              // Picked is pressed in, as the artboard draws it; glass has
              // no offset to collapse, so there it is the outline.
              pressed: picked == article,
              selected: tokens.isGlass && picked == article,
              onTap: () => onPick(article),
              child: Center(
                child: DpText(
                  article,
                  role: DpTextRole.title,
                  weight: 700,
                  // Cobalt takes white in light mode; Raspberry and Emerald
                  // take ink in both.
                  color: article == 'der'
                      ? tokens.color.onDer
                      : tokens.color.ink,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A tile to pick, as L1's placement draws its options.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.selected,
    required this.onTap,
    required this.child,
    this.kind = DpSurfaceKind.bar,
    this.height = 32,
    this.pressed = false,
  });

  final bool selected;

  /// Pushed into the paper: the ExamRunner artboard's picked article.
  final bool pressed;
  final VoidCallback? onTap;
  final Widget child;
  final DpSurfaceKind kind;
  final double height;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected || pressed,
    button: true,
    inMutuallyExclusiveGroup: true,
    child: DpSurface(
      kind: kind,
      selected: selected,
      pressed: pressed,
      radius: context.tokens.shape.button,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        child: child,
      ),
    ),
  );
}
