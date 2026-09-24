import 'dart:async';

import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/components/dp_speaker_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/features/study/study_back.dart';
import 'package:deutschplan/features/words/speak.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// What the speaker says for [word]: the article with it, as it is learned.
String spokenForm(Word word) =>
    word.article == null ? word.german : '${word.article} ${word.german}';

/// "Nomen · die Rechnung, Rechnungen · /রেশনুং/": the part of speech in
/// German, the forms, and the Bangla pronunciation when it is switched on.
String frontCaption(Word word, AppLocalizations l10n, {required bool pron}) {
  final pos = switch (word.pos) {
    'noun' => l10n.studyPosNoun,
    'verb' => l10n.studyPosVerb,
    'adj' => l10n.studyPosAdjective,
    'adv' => l10n.studyPosAdverb,
    'prep' => l10n.studyPosPreposition,
    'conj' => l10n.studyPosConjunction,
    'pron' => l10n.studyPosPronoun,
    'num' => l10n.studyPosNumber,
    'particle' => l10n.studyPosParticle,
    'art' => l10n.studyPosArticle,
    'phrase' => l10n.studyPosPhrase,
    _ => null,
  };
  final forms = word.forms;
  return <String>[
    ?pos,
    // A noun's forms are its plural, shown after the word as a dictionary
    // does; any other part of speech's forms stand on their own.
    if (forms != null && forms.isNotEmpty)
      word.pos == 'noun' ? '${spokenForm(word)}, $forms' : forms,
    if (pron && (word.pronBn?.isNotEmpty ?? false)) '/${word.pronBn}/',
  ].join(' · ');
}

/// T2's word card: face up to the German (`StudyFront`) and, once
/// [revealed], with its back unfolded under the headword (`StudyBack`).
///
/// The gender bar and, under glass, the card's tint are the article's
/// colour. The headword copies on a long-press, the speaker plays on a tap
/// and slowly on a long-press (FR-T2-09), and the word plays by itself when
/// `autoplay_headword` is on. With no German voice on the phone the speaker
/// shows slashed, and a tap says how to install one.
class StudyWordCard extends ConsumerStatefulWidget {
  const StudyWordCard({
    required this.word,
    super.key,
    this.revealed = false,
    this.onReveal,
    this.isNew = false,
  });

  final Word word;

  /// A word met for the first time (`StudyNew`): the *New* chip.
  final bool isNew;

  /// The back is showing (FR-T2-01).
  final bool revealed;

  /// FR-T2-01: a tap on the card, like *Show meaning*, turns it over.
  final VoidCallback? onReveal;

  /// FR-T2-09's slow playback.
  static const double slow = 0.75;

  @override
  ConsumerState<StudyWordCard> createState() => _StudyWordCardState();
}

class _StudyWordCardState extends ConsumerState<StudyWordCard> {
  /// The phone said it has no German voice (accessibility-performance.md).
  /// Kept across cards: the state outlives each word, so the toast is once.
  bool _mute = false;

  @override
  void initState() {
    super.initState();
    _autoplay();
  }

  @override
  void didUpdateWidget(StudyWordCard old) {
    super.didUpdateWidget(old);
    if (old.word.uid != widget.word.uid) _autoplay();
    if (widget.revealed && !old.revealed) _autoplayExample();
  }

  /// `autoplay_headword`: the word plays as its card appears.
  void _autoplay() {
    if (!ref.read(settingsProvider).read(SettingKeys.autoplayHeadword)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_mute) unawaited(_speak());
    });
  }

  /// `autoplay_example`: the first example plays as the back appears.
  void _autoplayExample() {
    if (_mute) return;
    if (!ref.read(settingsProvider).read(SettingKeys.autoplayExample)) return;
    final uid = widget.word.uid;
    // Best effort: a failed example query means no autoplay, not an
    // uncaught error.
    ref.read(studyBackProvider(uid).future).then((extras) {
      final first = extras.examples.firstOrNull;
      if (!mounted || first == null || widget.word.uid != uid) return;
      unawaited(_speak(text: first.german));
    }).ignore();
  }

  /// Says [text], the word with its article unless told otherwise.
  Future<void> _speak({String? text, double pace = 1}) async {
    if (_mute) return _explain();
    final spoke = await say(
      ref,
      context,
      text ?? spokenForm(widget.word),
      pace: pace,
      lift: StudyFrontActions.clearance,
    );
    if (!spoke && mounted) setState(() => _mute = true);
  }

  void _explain() => DpToast.show(
    context,
    AppLocalizations.of(context).speakerNoVoice,
    lift: StudyFrontActions.clearance,
  );

  void _copy() {
    final l10n = AppLocalizations.of(context);
    unawaited(Clipboard.setData(ClipboardData(text: spokenForm(widget.word))));
    DpToast.show(
      context,
      l10n.studyCopied(spokenForm(widget.word)),
      lift: StudyFrontActions.clearance,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final word = widget.word;
    final settings = ref.watch(settingsProvider);
    final pron = settings.read(SettingKeys.showPronBn);
    // Watched from the front, so the back has its examples when it opens.
    final extras = ref.watch(studyBackProvider(word.uid)).value;
    final still = MediaQuery.disableAnimationsOf(context);
    final quick = still ? Duration.zero : tokens.motion.quick;

    final face = Padding(
      padding: const EdgeInsets.fromLTRB(26, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              DpChip(label: word.sublevelCode),
              if (widget.isNew) ...<Widget>[
                const SizedBox(width: 6),
                DpChip(label: l10n.studyNewChip, selected: true),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // FR-T2-09: a long-press copies the word.
                    Semantics(
                      onLongPressHint: l10n.studyCopyHint,
                      child: GestureDetector(
                        onLongPress: _copy,
                        child: DpHeadword(
                          word.german,
                          article: word.article,
                          role: DpTextRole.display,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    DpText(
                      frontCaption(word, l10n, pron: pron),
                      role: DpTextRole.caption,
                      color: tokens.color.textSecondary,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              DpSpeakerButton(
                semanticLabel: l10n.studyPronounce,
                state: _mute ? DpSpeakerState.unavailable : speakerState(ref),
                onPressed: () => unawaited(_speak()),
                onLongPress: () => unawaited(_speak(pace: StudyWordCard.slow)),
              ),
            ],
          ),
          if (widget.revealed)
            // The reveal: the back fades in and slides up 4 px while the card
            // grows to hold it (study-session.md, Motion).
            TweenAnimationBuilder<double>(
              key: ValueKey<String>(word.uid),
              tween: Tween<double>(begin: 0, end: 1),
              duration: quick,
              curve: Curves.easeOut,
              builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, 4 * (1 - t)),
                  child: child,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: StudyBack(
                  word: word,
                  meaning: settings.read(SettingKeys.meaningLanguage),
                  extras: extras,
                  onPlay: (sentence) => unawaited(_speak(text: sentence)),
                ),
              ),
            ),
        ],
      ),
    );

    final card = StudyCardFrame(
      article: word.article,
      // Reduced motion: no growing at all. AnimatedSize cannot take a zero
      // duration — it re-dirties itself during layout.
      child: still
          ? face
          : AnimatedSize(
              duration: quick,
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: face,
            ),
    );

    // *Show meaning* is the labelled way to turn it; the tap is a shortcut.
    return GestureDetector(
      onTap: widget.revealed ? null : widget.onReveal,
      excludeFromSemantics: true,
      child: card,
    );
  }
}

/// The word card's frame: the article's 6 px gender bar down the left edge.
/// On paper, the artboard's 2 px ink card with its offset shadow; under
/// glass, the card itself takes the gender tint as well as the bar.
class StudyCardFrame extends StatelessWidget {
  const StudyCardFrame({required this.article, required this.child, super.key});

  final String? article;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final gender = tokens.color.forArticle(article) ?? tokens.surface.muted;
    final edge = tokens.isGlass ? 0.0 : 2.0;
    return DpSurface(
      kind: tokens.isGlass
          ? DpSurfaceKind.tint(gender, opacity: 0.22)
          : DpSurfaceKind.card,
      selected: !tokens.isGlass,
      padding: EdgeInsets.all(edge),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.shape.card - edge),
        child: Stack(
          children: <Widget>[
            PositionedDirectional(
              start: 0,
              top: 0,
              bottom: 0,
              width: 6,
              child: ColoredBox(color: gender),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

/// Above *Show meaning* on a new word (`StudyNew`): *I know it* and
/// *Skip → backlog*, as text buttons side by side.
class StudyNewActions extends StatelessWidget {
  const StudyNewActions({
    required this.onKnown,
    required this.onSkip,
    super.key,
  });

  final VoidCallback onKnown;

  /// Null leaves *Skip → backlog* out: a backlog word is already there.
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: DpButton(
              label: l10n.studyKnowIt,
              onPressed: onKnown,
              kind: DpButtonKind.text,
            ),
          ),
          if (onSkip != null)
            Expanded(
              child: DpButton(
                label: l10n.studySkip,
                onPressed: onSkip,
                kind: DpButtonKind.text,
              ),
            ),
        ],
      ),
    );
  }
}

/// Under the front: the hint and *Show meaning*. No rating bar before the
/// card is turned over.
class StudyFrontActions extends StatelessWidget {
  const StudyFrontActions({
    required this.onReveal,
    super.key,
    this.hint = true,
  });

  final VoidCallback onReveal;

  /// How far a snackbar floats up to clear these actions: the StudyNew
  /// artboard's `bottom: 128px`, less the bar's own 10 px margin.
  static const double clearance = 118;

  /// The hint line. A new word's two buttons take its place (StudyNew).
  final bool hint;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (hint) ...<Widget>[
          DpText(
            l10n.studyHint,
            role: DpTextRole.caption,
            color: tokens.color.textSecondary,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
        ],
        DpButton(
          label: l10n.studyShowMeaning,
          onPressed: onReveal,
          colour: tokens.surface.muted,
          onColour: tokens.color.ink,
        ),
      ],
    );
  }
}
