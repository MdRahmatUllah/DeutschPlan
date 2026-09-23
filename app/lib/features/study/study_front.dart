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

/// T2's word card, face up to the German (`StudyFront`).
///
/// The gender bar and, under glass, the card's tint are the article's
/// colour. The headword copies on a long-press, the speaker plays on a tap
/// and slowly on a long-press (FR-T2-09), and the word plays by itself when
/// `autoplay_headword` is on. With no German voice on the phone the speaker
/// shows slashed, and a tap says how to install one.
class StudyFrontCard extends ConsumerStatefulWidget {
  const StudyFrontCard({required this.word, super.key});

  final Word word;

  /// FR-T2-09's slow playback.
  static const double slow = 0.75;

  @override
  ConsumerState<StudyFrontCard> createState() => _StudyFrontCardState();
}

class _StudyFrontCardState extends ConsumerState<StudyFrontCard> {
  /// The phone said it has no German voice (accessibility-performance.md).
  /// Kept across cards: the state outlives each word, so the toast is once.
  bool _mute = false;

  @override
  void initState() {
    super.initState();
    _autoplay();
  }

  @override
  void didUpdateWidget(StudyFrontCard old) {
    super.didUpdateWidget(old);
    if (old.word.uid != widget.word.uid) _autoplay();
  }

  /// `autoplay_headword`: the word plays as its card appears.
  void _autoplay() {
    if (!ref.read(settingsProvider).read(SettingKeys.autoplayHeadword)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_mute) unawaited(_speak());
    });
  }

  Future<void> _speak({double pace = 1}) async {
    if (_mute) return _explain();
    final speed = ref.read(settingsProvider).read(SettingKeys.ttsSpeed);
    final spoke = await ref
        .read(systemTtsProvider)
        .speak(spokenForm(widget.word), rate: speed * pace);
    if (spoke || !mounted) return;
    setState(() => _mute = true);
    _explain();
  }

  void _explain() =>
      DpToast.show(context, AppLocalizations.of(context).studyNoVoice);

  void _copy() {
    final l10n = AppLocalizations.of(context);
    unawaited(Clipboard.setData(ClipboardData(text: spokenForm(widget.word))));
    DpToast.show(context, l10n.studyCopied(spokenForm(widget.word)));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final word = widget.word;
    final gender =
        tokens.color.forArticle(word.article) ?? tokens.surface.muted;
    final pron = ref.watch(settingsProvider).read(SettingKeys.showPronBn);
    final edge = tokens.isGlass ? 0.0 : 2.0;

    final face = Padding(
      padding: const EdgeInsets.fromLTRB(26, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: DpChip(label: word.sublevelCode),
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
                state: _mute ? DpSpeakerState.unavailable : DpSpeakerState.idle,
                onPressed: () => unawaited(_speak()),
                onLongPress: () => unawaited(_speak(pace: StudyFrontCard.slow)),
              ),
            ],
          ),
        ],
      ),
    );

    return DpSurface(
      // Paper: the artboard's 2 px ink card with its offset shadow. Glass:
      // the card itself takes the gender tint as well as the bar.
      kind: tokens.isGlass
          ? DpSurfaceKind.tint(gender, opacity: 0.22)
          : DpSurfaceKind.card,
      selected: !tokens.isGlass,
      padding: EdgeInsets.all(edge),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.shape.card - edge),
        child: Stack(
          children: <Widget>[
            // The 6 px gender bar down the left edge.
            PositionedDirectional(
              start: 0,
              top: 0,
              bottom: 0,
              width: 6,
              child: ColoredBox(color: gender),
            ),
            face,
          ],
        ),
      ),
    );
  }
}

/// Under the front: the hint and *Show meaning*. No rating bar before the
/// card is turned over.
class StudyFrontActions extends StatelessWidget {
  const StudyFrontActions({required this.onReveal, super.key});

  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DpText(
          l10n.studyHint,
          role: DpTextRole.caption,
          color: tokens.color.textSecondary,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
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
