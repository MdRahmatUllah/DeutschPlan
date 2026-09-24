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
  });

  final QuizItem item;

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
          state: speakerState(ref),
          semanticLabel: l10n.quizAskListening,
          onPressed: () => unawaited(say(ref, context, item.prompt)),
        ),
      ),
      QuizDirection.enDe => Column(
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
          Flexible(child: _German(item.prompt)),
          const SizedBox(width: 12),
          DpSpeakerButton(
            state: speakerState(ref),
            semanticLabel: l10n.quizPlay,
            onPressed: () => unawaited(say(ref, context, item.prompt)),
          ),
        ],
      ),
    };

    final Widget answer;
    if (item.direction == QuizDirection.articles) {
      answer = Row(
        children: <Widget>[
          for (final (index, article) in articles.indexed) ...<Widget>[
            if (index > 0) const SizedBox(width: 10),
            Expanded(child: _ArticleButton(article, this)),
          ],
        ],
      );
    } else if (item.tiles) {
      answer = Column(
        children: <Widget>[
          for (final option in item.options)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _Choice(
                selected: picked == option,
                onTap: () => onAnswer(option),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DpText(
                    option,
                    role: DpTextRole.bodyLarge,
                    weight: 600,
                  ),
                ),
              ),
            ),
        ],
      );
    } else {
      answer = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DpText(
            l10n.quizYourAnswer.toUpperCase(),
            role: DpTextRole.caption,
            weight: 700,
            letterSpacing: 0.6,
            color: tokens.color.textSecondary,
          ),
          const SizedBox(height: 8),
          StudyAnswerField(
            controller: field,
            hint: l10n.quizYourAnswer,
            onSubmitted: () => onAnswer(field.text),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[prompt, const SizedBox(height: 20), answer],
    );
  }
}

/// A German word with its article in the gender's colour, as the app writes
/// every noun.
class _German extends StatelessWidget {
  const _German(this.word);

  final String word;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final space = word.indexOf(' ');
    final article = space < 0 ? '' : word.substring(0, space);
    final colour = switch (article) {
      'der' => tokens.color.derText,
      'die' => tokens.color.dieText,
      'das' => tokens.color.dasText,
      _ => null,
    };
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          if (colour != null)
            TextSpan(
              text: '$article ',
              style: TextStyle(color: colour),
            ),
          TextSpan(text: colour == null ? word : word.substring(space + 1)),
        ],
      ),
      style: DpText.styleFor(
        tokens,
        DpTextRole.headline,
        color: tokens.color.ink,
      ).copyWith(fontWeight: FontWeight.w600),
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
  });

  final bool selected;
  final VoidCallback? onTap;
  final Widget child;
  final DpSurfaceKind kind;
  final double height;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    inMutuallyExclusiveGroup: true,
    child: DpSurface(
      kind: kind,
      selected: selected,
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

/// der, die or das: big, and in its gender's colour.
class _ArticleButton extends StatelessWidget {
  const _ArticleButton(this.article, this.view);

  final String article;
  final QuizItemView view;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final (fill, ink) = switch (article) {
      'der' => (tokens.color.der, tokens.color.derText),
      'die' => (tokens.color.die, tokens.color.dieText),
      _ => (tokens.color.das, tokens.color.dasText),
    };
    return _Choice(
      kind: DpSurfaceKind.tint(fill),
      height: 48,
      selected: view.picked == article,
      onTap: () => view.onAnswer(article),
      child: Center(
        child: DpText(
          article,
          role: DpTextRole.headline,
          weight: 700,
          color: ink,
        ),
      ),
    );
  }
}
