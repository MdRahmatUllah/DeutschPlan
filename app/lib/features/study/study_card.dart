import 'dart:async';

import 'package:sogda/core/components/sg_button.dart';
import 'package:sogda/core/components/sg_chip.dart';
import 'package:sogda/core/components/sg_feedback.dart';
import 'package:sogda/core/components/sg_speaker_button.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/sg_surface.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/word_repository.dart' show customId;
import 'package:sogda/features/study/study_back.dart';
import 'package:sogda/features/words/speak.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
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
  /// The phone said it has no German voice (accessibility-performance.md), so
  /// a tap on this card's speaker explains instead of trying again. Each card
  /// has its own (the session keys every card afresh), so it can't keep the
  /// autoplay quiet across cards: [mayAutoplay] does (#646).
  bool _mute = false;

  @override
  void initState() {
    super.initState();
    _autoplay();
  }

  /// A new word is a new card, keyed afresh by the session (`StudyCardMotion`),
  /// so its autoplay is [initState]'s.
  @override
  void didUpdateWidget(StudyWordCard old) {
    super.didUpdateWidget(old);
    if (widget.revealed && !old.revealed) _autoplayExample();
  }

  /// `autoplay_headword`: the word plays as its card appears.
  void _autoplay() {
    if (!ref.read(settingsProvider).read(SettingKeys.autoplayHeadword)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_mute && mayAutoplay(ref)) {
        unawaited(_speak(quiet: true));
      }
    });
  }

  /// `autoplay_example`: the first example plays as the back appears.
  void _autoplayExample() {
    if (_mute || !mayAutoplay(ref)) return;
    if (!ref.read(settingsProvider).read(SettingKeys.autoplayExample)) return;
    final uid = widget.word.uid;
    // Best effort: a failed example query means no autoplay, not an
    // uncaught error.
    ref.read(studyBackProvider(uid).future).then((extras) {
      final first = extras.examples.firstOrNull;
      if (!mounted || first == null || widget.word.uid != uid) return;
      unawaited(_speak(text: first.german, quiet: true));
    }).ignore();
  }

  /// Says [text], the word with its article unless told otherwise. An
  /// auto-play is [quiet]: without a voice it says nothing (`say`, #646).
  Future<void> _speak({
    String? text,
    double pace = 1,
    bool quiet = false,
  }) async {
    if (_mute) return quiet ? null : _explain();
    final spoke = await say(
      ref,
      context,
      text ?? spokenForm(widget.word),
      pace: pace,
      lift: StudyFrontActions.clearanceOf(context),
      quiet: quiet,
    );
    if (!spoke && mounted) setState(() => _mute = true);
  }

  void _explain() => SgToast.show(
    context,
    AppLocalizations.of(context).speakerNoVoice,
    lift: StudyFrontActions.clearanceOf(context),
  );

  void _copy() {
    final l10n = AppLocalizations.of(context);
    unawaited(Clipboard.setData(ClipboardData(text: spokenForm(widget.word))));
    SgToast.show(
      context,
      l10n.studyCopied(spokenForm(widget.word)),
      lift: StudyFrontActions.clearanceOf(context),
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
    final updated =
        ref.watch(recentlyUpdatedProvider).value?.contains(word.uid) ?? false;
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
              // A word of the learner's own is in no step (#363).
              SgChip(
                label: customId(word.uid) == null
                    ? word.sublevelCode
                    : l10n.searchMyWord,
              ),
              if (widget.isNew) ...<Widget>[
                const SizedBox(width: 6),
                SgChip(label: l10n.studyNewChip, selected: true),
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
                    // accessibility-performance.md: after a rating the focus
                    // moves to the next card, which is a new one (T2's
                    // switcher), so a screen reader follows (#162).
                    Focus(
                      autofocus: true,
                      // FR-T2-09: a long-press copies the word.
                      child: Semantics(
                        onLongPressHint: l10n.studyCopyHint,
                        child: GestureDetector(
                          onLongPress: _copy,
                          child: SgHeadword(
                            word.german,
                            article: word.article,
                            plural: word.forms,
                            role: SgTextRole.display,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SgText(
                      // A long compound's forms break at a syllable, not at any
                      // letter; a shorter word wraps whole (#419).
                      SgScript.allowBreaks(
                        frontCaption(word, l10n, pron: pron),
                      ),
                      role: SgTextRole.caption,
                      color: tokens.color.textSecondary,
                      // Its Bangla pronunciation too, though no German in
                      // it is long (#504).
                      breakTooWide: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SgSpeakerButton(
                semanticLabel: l10n.studyPronounce,
                state: _mute
                    ? SgSpeakerState.unavailable
                    : speakerState(ref, spokenForm(word)),
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
                  updated: updated,
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
    return SgSurface(
      kind: tokens.isGlass
          ? SgSurfaceKind.tint(gender, opacity: 0.22)
          : SgSurfaceKind.card,
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
            child: SgButton(
              label: l10n.studyKnowIt,
              onPressed: onKnown,
              kind: SgButtonKind.text,
            ),
          ),
          if (onSkip != null)
            Expanded(
              child: SgButton(
                label: l10n.studySkip,
                onPressed: onSkip,
                kind: SgButtonKind.text,
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

  /// How far a snackbar floats up to clear these actions, and a new word's
  /// *I know it* and *Skip* in the hint's place: 32 + 56 (*Show meaning*) +
  /// 8 + 48 dp, and 8 clear, less the bar's own 10 px margin. The StudyNew
  /// artboard's `bottom: 128px` left the bar over the two (#742).
  // ponytail: one lift for both fronts; a revision's bar floats 24 dp higher
  // than it needs, over the card, not over anything to press.
  static const double clearance = 142;

  /// [clearance], grown with the text: at 200 % *Show meaning* and the hint
  /// are taller, and a fixed 118 left the Undo bar over them (#165).
  static double clearanceOf(BuildContext context) =>
      SgScript.grow(context, clearance);

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
          SgText(
            l10n.studyHint,
            role: SgTextRole.caption,
            color: tokens.color.textSecondary,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
        ],
        SgButton(
          label: l10n.studyShowMeaning,
          onPressed: onReveal,
          colour: tokens.surface.muted,
          onColour: tokens.color.ink,
        ),
      ],
    );
  }
}
