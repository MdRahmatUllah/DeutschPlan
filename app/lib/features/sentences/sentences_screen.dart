import 'dart:async';

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_speaker_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/plan_repository.dart'
    show ReviewSource;
import 'package:deutschplan/data/repositories/search_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/domain/cloze.dart';
import 'package:deutschplan/domain/fsrs.dart' show Rating;
import 'package:deutschplan/domain/sentence_picker.dart';
import 'package:deutschplan/domain/text_norm.dart' show searchKey;
import 'package:deutschplan/features/study/study_summary.dart';
import 'package:deutschplan/features/study/write_guard.dart';
import 'package:deutschplan/features/words/speak.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:url_launcher/url_launcher.dart';

part 'sentences_screen.g.dart';

/// One of the day's practice sentences, with its headword (for the
/// underline and its colour) and how it was rated, if it was.
@immutable
class PracticeSentence {
  const PracticeSentence({required this.sentence, this.word, this.rating});

  final SentenceCandidate sentence;
  final Word? word;

  /// `self_rating`: 3 Understood · 2 Partly · 1 Not yet.
  final int? rating;

  /// Where the headword sits in the sentence, to underline it.
  ClozeGap? get gap {
    final word = this.word;
    return word == null
        ? null
        : clozeGap(sentence.german, word.german, pos: word.pos);
  }

  PracticeSentence rated(int rating) =>
      PracticeSentence(sentence: sentence, word: word, rating: rating);
}

/// T5's answers, as `self_rating` writes them (`sentences.md`).
enum SentenceRating {
  understood(3),
  partly(2),
  notYet(1);

  const SentenceRating(this.value);

  final int value;
}

/// T5's sentences for today (FR-T5-01): what `SentencePicker.forDay` drew,
/// which `sentence_log` keeps stable for the day, with the ratings so far.
@riverpod
class PracticeSentences extends _$PracticeSentences {
  @override
  Future<List<PracticeSentence>> build() async {
    final date = ref.watch(todayProvider);
    final picked = await ref.watch(sentencePickerProvider).forDay(date);
    final ratings = await ref.watch(sentenceStoreProvider).ratings(date);
    final words = ref.watch(wordRepositoryProvider);
    return <PracticeSentence>[
      for (final sentence in picked)
        PracticeSentence(
          sentence: sentence,
          word: (await words.find(sentence.wordUid))?.word,
          rating: ratings[(sentence.wordUid, sentence.ord)],
        ),
    ];
  }

  /// FR-T5-02: records the answer; *Not yet* also rates the headword Hard,
  /// logged as from a sentence (BR-FSRS-04) — one transaction, both or
  /// neither. False when there was no list to rate in.
  Future<bool> rate(int index, SentenceRating rating) async {
    final list = state.value;
    if (list == null) return false;
    final item = list[index];
    final ratings = ref.read(ratingServiceProvider);
    await ref
        .read(sentenceStoreProvider)
        .rate(
          ref.read(todayProvider),
          item.sentence,
          rating.value,
          andThen: rating == SentenceRating.notYet
              ? () => ratings.rate(
                  item.sentence.wordUid,
                  Rating.hard,
                  source: ReviewSource.sentence,
                )
              : null,
        );
    state = AsyncData<List<PracticeSentence>>(<PracticeSentence>[
      for (var i = 0; i < list.length; i++)
        i == index ? item.rated(rating.value) : list[i],
    ]);
    return true;
  }
}

/// T5 · Practice sentences (`practice-sentences.md`): the day's learned
/// words in context, one sentence at a time.
class SentencesScreen extends ConsumerStatefulWidget {
  const SentencesScreen({super.key});

  @override
  ConsumerState<SentencesScreen> createState() => _SentencesScreenState();
}

class _SentencesScreenState extends ConsumerState<SentencesScreen> {
  PageController? _pages;
  int _page = 0;
  bool _leaving = false;

  /// One answer at a time: a double tap must not rate the word twice.
  bool _busy = false;

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  /// FR-T5-04: a rating moves on; the last one closes to T6 when the day is
  /// complete, else back to Today.
  Future<void> _rate(int index, int count, SentenceRating rating) async {
    if (_busy || _leaving) return;
    _busy = true;
    try {
      // A write that fails keeps the sentence, with Retry and Export (#174).
      final written = await guardWrite(
        context,
        () => ref.read(practiceSentencesProvider.notifier).rate(index, rating),
      );
      if (!written) return;
    } finally {
      _busy = false;
    }
    if (!mounted) return;
    final left = ref
        .read(practiceSentencesProvider)
        .value
        ?.indexWhere((s) => s.rating == null);
    if (left != null && left >= 0) {
      await _pages?.animateToPage(
        left,
        duration: MediaQuery.disableAnimationsOf(context)
            ? const Duration(milliseconds: 1)
            : context.tokens.motion.standard,
        curve: Curves.easeOutCubic,
      );
      return;
    }
    await _finish();
  }

  /// To sentence [page], as a swipe would: the dots' adjustable action.
  void _go(int page) => unawaited(
    _pages?.animateToPage(
      page,
      duration: MediaQuery.disableAnimationsOf(context)
          ? const Duration(milliseconds: 1)
          : context.tokens.motion.standard,
      curve: Curves.easeOutCubic,
    ),
  );

  Future<void> _finish() async {
    if (_leaving) return;
    _leaving = true;
    final today = ref.read(todayProvider);
    ref.invalidate(studyNextProvider(today));
    // Listened to while it answers: read alone, an auto-disposing provider
    // can go before its future does.
    final hold = ref.listenManual(studyNextProvider(today), (_, _) {});
    final next = await ref.read(studyNextProvider(today).future);
    hold.close();
    if (!mounted) return;
    if (next.dayDone && next.sentences == 0) {
      DayCompleteRoute.instead(context);
    } else {
      unawaited(Navigator.of(context).maybePop());
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final list = ref.watch(practiceSentencesProvider).value;
    if (list != null && _pages == null && list.isNotEmpty) {
      // Reopened: back at the first sentence not yet answered.
      final first = list.indexWhere((s) => s.rating == null);
      _page = first < 0 ? 0 : first;
      _pages = PageController(initialPage: _page);
    }
    final count = list?.length ?? 0;
    final answers = list == null || list.isEmpty
        ? const <Widget>[]
        : <Widget>[
            for (final (rating, label, colour)
                in <(SentenceRating, String, Color)>[
                  (
                    SentenceRating.understood,
                    l10n.sentencesUnderstood,
                    tokens.color.easy,
                  ),
                  (
                    SentenceRating.partly,
                    l10n.sentencesPartly,
                    tokens.color.hard,
                  ),
                  (
                    SentenceRating.notYet,
                    l10n.sentencesNotYet,
                    tokens.color.again,
                  ),
                ])
              _Answer(
                label: label,
                colour: colour,
                chosen: list[_page].rating == rating.value,
                onPressed: () => unawaited(_rate(_page, count, rating)),
              ),
          ];

    final ink = tokens.isGlass ? tokens.color.ink : tokens.color.onAccent;
    final bar = SafeArea(
      bottom: false,
      child: SizedBox(
        height: 56,
        child: Row(
          children: <Widget>[
            const SizedBox(width: 8),
            _IconButton(
              icon: Icons.arrow_back,
              label: l10n.sentencesClose,
              colour: ink,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              // The dots below say it, as a value a screen reader can change
              // (#164): once is enough.
              child: ExcludeSemantics(
                child: DpText(
                  count == 0 ? '' : l10n.sentencesPlace(_page + 1, count),
                  role: DpTextRole.body,
                  weight: 600,
                  textAlign: TextAlign.center,
                  color: ink,
                ),
              ),
            ),
            const SizedBox(width: 56),
          ],
        ),
      ),
    );
    // The Raspberry band: solid on paper, a tint under glass.
    final band = tokens.isGlass
        ? DpSurface(
            kind: DpSurfaceKind.tint(tokens.color.die),
            radius: 0,
            child: bar,
          )
        : ColoredBox(color: tokens.color.die, child: bar);

    return AdaptiveScaffold(
      backgroundColor: tokens.surface.paper,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          band,
          if (list != null && list.isNotEmpty) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: _Dots(
                count: count,
                current: _page,
                place: (index) => l10n.sentencesPlace(index + 1, count),
                onGo: _go,
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: count,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (context, index) =>
                    _SentencePage(item: list[index]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  DpText(
                    l10n.sentencesAsk.toUpperCase(),
                    role: DpTextRole.caption,
                    weight: 700,
                    letterSpacing: 0.6,
                    color: tokens.color.textSecondary,
                  ),
                  const SizedBox(height: 10),
                  // Past 130 % text three abreast broke "Understood"
                  // mid-word (#165): they stack, full width.
                  if (DpScript.large(context))
                    for (final (i, answer) in answers.indexed) ...<Widget>[
                      if (i > 0) const SizedBox(height: 10),
                      answer,
                    ]
                  else
                    Row(
                      children: <Widget>[
                        for (final (i, answer) in answers.indexed) ...<Widget>[
                          if (i > 0) const SizedBox(width: 10),
                          Expanded(child: answer),
                        ],
                      ],
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Sentence 1 of 3" as dots: the current one long and Raspberry.
///
/// #164: every swipe has a button's equivalent. Rating moves on (FR-T5-04's
/// *Next*); the dots are an adjustable control too, so a screen reader or
/// switch pages either way without a swipe.
class _Dots extends StatelessWidget {
  const _Dots({
    required this.count,
    required this.current,
    required this.place,
    required this.onGo,
  });

  final int count;
  final int current;

  /// "Sentence 2 of 3" for a 0-based index.
  final String Function(int) place;
  final ValueChanged<int> onGo;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final more = current < count - 1;
    final less = current > 0;
    return Semantics(
      value: place(current),
      increasedValue: more ? place(current + 1) : null,
      decreasedValue: less ? place(current - 1) : null,
      onIncrease: more ? () => onGo(current + 1) : null,
      onDecrease: less ? () => onGo(current - 1) : null,
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          for (var i = 0; i < count; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 6),
            AnimatedContainer(
              // #164: reduce motion keeps the dot still.
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : tokens.motion.quick,
              width: i == current ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == current ? tokens.color.die : null,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: tokens.color.ink, width: 1.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One sentence: its words to tap, the headword underlined in its gender
/// colour, the big play button, the translation on request, and the hint.
class _SentencePage extends ConsumerStatefulWidget {
  const _SentencePage({required this.item});

  final PracticeSentence item;

  @override
  ConsumerState<_SentencePage> createState() => _SentencePageState();
}

class _SentencePageState extends ConsumerState<_SentencePage> {
  final List<TapGestureRecognizer> _taps = <TapGestureRecognizer>[];
  bool _translated = false;

  @override
  void dispose() {
    for (final tap in _taps) {
      tap.dispose();
    }
    super.dispose();
  }

  void _play({double pace = 1}) =>
      unawaited(say(ref, context, widget.item.sentence.german, pace: pace));

  /// FR-T5-03: the word's course meaning, or a way to look it up.
  Future<void> _lookUp(String token) async {
    final word = await ref
        .read(contentDaoProvider)
        .wordForToken(searchKey(token, stripArticle: false));
    if (!mounted) return;
    await Adaptive.showSheet<void>(
      context: context,
      builder: (sheet) => _TokenSheet(token: token, word: word),
    );
  }

  List<TextSpan> _spans(TextStyle style, Color underline) {
    for (final tap in _taps) {
      tap.dispose();
    }
    _taps.clear();
    final text = widget.item.sentence.german;
    final gap = widget.item.gap;
    final spans = <TextSpan>[];
    var at = 0;
    for (final match in RegExp(r'\p{L}+', unicode: true).allMatches(text)) {
      if (match.start > at) {
        spans.add(TextSpan(text: text.substring(at, match.start)));
      }
      final token = match[0]!;
      final tap = TapGestureRecognizer()
        ..onTap = () => unawaited(_lookUp(token));
      _taps.add(tap);
      final target =
          gap != null && match.start >= gap.start && match.end <= gap.end;
      spans.add(
        TextSpan(
          text: token,
          recognizer: tap,
          style: target
              ? style.copyWith(
                  decoration: TextDecoration.underline,
                  decorationColor: underline,
                  decorationThickness: 3,
                )
              : null,
        ),
      );
      at = match.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final style = DpText.styleFor(
      tokens,
      DpTextRole.title,
    ).copyWith(fontWeight: FontWeight.w500);
    final english = widget.item.sentence.english;
    final underline =
        tokens.color.forArticle(widget.item.word?.article) ??
        tokens.color.primary;

    // Centred in the page, as the artboard has it; scrolled when it will
    // not fit (a long sentence, a large text size).
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight - 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // Read in a German voice (#162); a long compound breaks at a
              // syllable at 200 % (#539).
              DpGermanRuns(
                _spans(style, underline),
                style: style,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              DpSpeakerButton(
                size: 72,
                semanticLabel: l10n.studyPlaySentence,
                state: speakerState(ref, widget.item.sentence.german),
                onPressed: _play,
                onLongPress: () => _play(pace: 0.75),
              ),
              const SizedBox(height: 6),
              DpText(
                l10n.sentencesSlow,
                role: DpTextRole.caption,
                color: tokens.color.textSecondary,
              ),
              const SizedBox(height: 16),
              if (english != null)
                AnimatedSize(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? const Duration(milliseconds: 1)
                      : tokens.motion.quick,
                  child: _translated
                      ? Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.surface.muted,
                            borderRadius: BorderRadius.circular(
                              tokens.shape.button,
                            ),
                          ),
                          child: DpText(
                            english,
                            role: DpTextRole.body,
                            textAlign: TextAlign.center,
                          ),
                        )
                      : DpButton(
                          label: l10n.sentencesShowTranslation,
                          kind: DpButtonKind.text,
                          expand: false,
                          onPressed: () => setState(() => _translated = true),
                        ),
                ),
              const SizedBox(height: 16),
              DpText(
                l10n.sentencesHint,
                role: DpTextRole.caption,
                color: tokens.color.textSecondary,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// FR-T5-03's mini sheet: a course word's meaning and a way to it, or — for
/// a word the course lacks — Duden. ponytail: the translation model's path
/// ("translation if `mt_enabled`") waits for M6's translator; until then
/// `mt_enabled` cannot be on, and Duden is what there is.
class _TokenSheet extends ConsumerWidget {
  const _TokenSheet({required this.token, required this.word});

  final String token;
  final Word? word;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final word = this.word;
    final bangla =
        ref.watch(settingsProvider).read(SettingKeys.meaningLanguage) ==
        MeaningLanguage.bangla;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (word != null) ...<Widget>[
            DpHeadword(
              word.german,
              article: word.article,
              plural: word.forms,
              role: DpTextRole.title,
            ),
            const SizedBox(height: 6),
            DpText(
              bangla ? word.bangla ?? word.english : word.english,
              role: DpTextRole.bodyLarge,
              color: tokens.color.textSecondary,
            ),
            const SizedBox(height: 12),
            DpButton(
              label: l10n.sentencesOpenWord,
              kind: DpButtonKind.secondary,
              onPressed: () {
                Navigator.of(context).pop();
                WordRoute.open(context, word.uid);
              },
            ),
          ] else ...<Widget>[
            DpText(token, role: DpTextRole.title, german: true),
            const SizedBox(height: 6),
            DpText(
              l10n.sentencesNotInCourse,
              role: DpTextRole.body,
              color: tokens.color.textSecondary,
            ),
            const SizedBox(height: 12),
            DpButton(
              label: l10n.sentencesDuden,
              kind: DpButtonKind.secondary,
              onPressed: () {
                Navigator.of(context).pop();
                unawaited(
                  launchUrl(
                    SearchRepository.webLinks(token)[WebSource.duden]!,
                    mode: LaunchMode.externalApplication,
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// A rating chip: 48 dp, filled in its colour, the ink edge and the hard
/// shadow of the Paper & Ink buttons.
class _Answer extends StatelessWidget {
  const _Answer({
    required this.label,
    required this.colour,
    required this.chosen,
    required this.onPressed,
  });

  final String label;
  final Color colour;
  final bool chosen;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      button: true,
      selected: chosen,
      label: label,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onPressed,
          behavior: HitTestBehavior.opaque,
          // 48, grown with the text size: a fixed 48 cut "Understood" at
          // 150 % (#165).
          child: Container(
            height: DpScript.grow(context, 48),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colour,
              borderRadius: BorderRadius.circular(tokens.shape.button),
              border: Border.all(
                color: tokens.isGlass
                    ? tokens.surface.outline
                    : tokens.color.ink,
                width: 2,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: tokens.surface.shadow,
                  offset: tokens.surface.shadowOffset,
                  blurRadius: tokens.surface.shadowBlur,
                ),
              ],
            ),
            child: DpText(
              label,
              role: DpTextRole.body,
              weight: 600,
              color: tokens.color.onAccent,
            ),
          ),
        ),
      ),
    );
  }
}

/// A plain icon button on the band.
class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.label,
    required this.colour,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color colour;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: AdaptiveTooltip(
      message: label,
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: colour),
        ),
      ),
    ),
  );
}
