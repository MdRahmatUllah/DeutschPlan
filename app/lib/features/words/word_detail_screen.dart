import 'dart:async';
import 'dart:math' as math;

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/components/dp_speaker_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/compare_set.dart' show comparesSet;
import 'package:deutschplan/domain/fsrs.dart' show Rating;
import 'package:deutschplan/domain/plan_engine.dart' show daysBetween;
import 'package:deutschplan/features/study/study_back.dart';
import 'package:deutschplan/features/study/study_card.dart';
import 'package:deutschplan/features/today/today_providers.dart';
import 'package:deutschplan/features/words/speak.dart';
import 'package:deutschplan/features/words/word_row.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/router/cross_tab.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/data/repositories/rating_service.dart'
    show CardMode;
import 'package:deutschplan/data/repositories/search_repository.dart';
import 'package:deutschplan/data/repositories/word_actions.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

part 'word_detail_screen.g.dart';

/// W1's word: the word with the learner's state, all its examples and its
/// interference tip (`word-detail.md`, Data). Again whenever the state
/// changes, so #141's actions show at once.
@immutable
class WordDetail {
  const WordDetail({
    required this.word,
    required this.examples,
    required this.meaning,
    required this.pron,
    this.tip,
    this.translate = false,
  });

  final WordWithState word;
  final List<StudyExample> examples;
  final StudyTip? tip;

  /// The learner's `meaning_language` and `show_pron_bn`, read here like
  /// L2's rows read theirs, so the view itself reads no settings.
  final MeaningLanguage meaning;
  final bool pron;

  /// `mt_enabled`: whether *Translate* is offered (FR-W1-05).
  final bool translate;
}

@riverpod
Stream<WordDetail?> wordDetail(Ref ref, String uid) async* {
  // Everything the provider watches is read before the first await: a sheet
  // closed mid-query disposes it, and a ref used after that throws.
  final dao = ref.watch(contentDaoProvider);
  final settings = ref.watch(settingsProvider);
  final words = ref.watch(wordRepositoryProvider);
  // The course is read-only, so its part is read once; the state is watched.
  final examples = <StudyExample>[
    for (final e in await dao.examplesForWord(uid).get())
      (german: e.german, english: e.english),
  ];
  final tips = await dao.tipsForWord(uid).get();
  final StudyTip? tip = tips.isEmpty
      ? null
      : (en: tips.first.tipEn, bn: tips.first.tipBn);
  yield* words
      .watchWord(uid)
      .map(
        (word) => word == null
            ? null
            : WordDetail(
                word: word,
                examples: examples,
                tip: tip,
                meaning: settings.read(SettingKeys.meaningLanguage),
                pron: settings.read(SettingKeys.showPronBn),
                translate: settings.read(SettingKeys.mtEnabled),
              ),
      );
}

/// FR-W1-05: the examples [ExampleTranslations.translate] has translated,
/// by their German, shown under each until the sheet closes.
@riverpod
class ExampleTranslations extends _$ExampleTranslations {
  @override
  Map<String, String> build(String uid) => const <String, String>{};

  /// Runs [germans] through the translator, cached, into [to].
  Future<void> translate(List<String> germans, {required String to}) async {
    final translations = ref.read(translationRepositoryProvider);
    final found = <String, String>{...state};
    for (final german in germans) {
      final result = await translations.translate(german, from: 'de', to: to);
      if (result != null) found[german] = result;
    }
    if (ref.mounted) state = found;
  }
}

/// The history caption's counts, from `review_log`.
@riverpod
Stream<ReviewHistory> wordHistory(Ref ref, String uid) =>
    ref.watch(wordRepositoryProvider).watchHistory(uid);

/// Where W1 is showing, which decides its top edge.
enum WordDetailPresentation {
  /// A phone's bottom sheet: a drag handle over the header.
  sheet,

  /// A tablet's right-hand pane.
  pane,

  /// A deep link's full page: a back button in the header.
  page,
}

/// W1 · Word detail over whatever is showing (`word-detail.md`,
/// Presentation): a sheet with medium and large detents on a phone, a
/// right-hand pane on a tablet. The opener stays mounted underneath, so
/// closing W1 finds it exactly where it was, scroll and all.
void showWordDetail(BuildContext context, String uid) {
  if (MediaQuery.sizeOf(context).shortestSide >= WordDetailView.tabletFrom) {
    unawaited(
      Adaptive.showPane<void>(
        context: context,
        builder: (_) =>
            WordDetailView(uid: uid, presentation: WordDetailPresentation.pane),
      ),
    );
    return;
  }
  unawaited(
    Adaptive.showSheet<void>(
      context: context,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: WordDetailView.large,
        maxChildSize: WordDetailView.large,
        minChildSize: WordDetailView.closed,
        snap: true,
        snapSizes: const <double>[WordDetailView.medium],
        builder: (sheet, scroll) {
          final view = AdaptiveToastScope(
            child: WordDetailView(
              uid: uid,
              scroll: scroll,
              presentation: WordDetailPresentation.sheet,
            ),
          );
          if (!sheet.isCupertino) return view;
          // Material's bottom sheet closes itself when the sheet is dragged to
          // its smallest; a Cupertino popup does not, and would sit there a
          // quarter open.
          return NotificationListener<DraggableScrollableNotification>(
            onNotification: (notification) {
              if (notification.extent <= notification.minExtent + 0.001) {
                Navigator.of(sheet).maybePop();
              }
              return false;
            },
            child: view,
          );
        },
      ),
    ),
  );
}

/// W1 as a page of its own: `deutschplan://word/<uid>`, and the widget's
/// *Pronounce* with `?speak=1` (FR-X1-02), which plays the headword on
/// arrival.
class WordDetailScreen extends StatelessWidget {
  const WordDetailScreen({
    required this.uid,
    super.key,
    this.speak = false,
    this.arrival,
  });

  final String uid;
  final bool speak;

  /// Which *Pronounce* opened this ([WordDetailView.arrival]).
  final String? arrival;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scaffold = AdaptiveScaffold(
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
      body: WordDetailView(
        uid: uid,
        speak: speak,
        arrival: arrival,
        presentation: WordDetailPresentation.page,
      ),
    );
    // A link opens this page alone, with nothing under it to go back to:
    // back goes to Today rather than out of the app.
    return PopScope(
      canPop: Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) leaveWordPage(context);
      },
      child: tokens.isGlass
          ? AuroraBackdrop(leading: tokens.color.die, child: scaffold)
          : scaffold,
    );
  }
}

/// Back from W1's page: to where the learner came from, or to Today when a
/// link opened it cold.
void leaveWordPage(BuildContext context) {
  if (Navigator.of(context).canPop()) {
    unawaited(Navigator.of(context).maybePop());
  } else {
    context.jumpToTab(const TodayRoute());
  }
}

/// Everything about one word: the gender-tinted header with its speaker and
/// chips, the caption, the meanings, every example with play, the
/// collocations and register, the interference tip, *Compare* (FR-W1-06) and
/// the history caption. The actions row is #141's.
class WordDetailView extends ConsumerStatefulWidget {
  const WordDetailView({
    required this.uid,
    required this.presentation,
    super.key,
    this.scroll,
    this.speak = false,
    this.arrival,
  });

  final String uid;
  final WordDetailPresentation presentation;

  /// The sheet's, so dragging the content drags the sheet between detents.
  final ScrollController? scroll;

  /// Play the headword once it has loaded (`?speak=1`).
  final bool speak;

  /// Which *Pronounce* this is. A link onto the word already open keeps this
  /// view: a new [speak], or a new arrival with it, plays again (#442).
  final String? arrival;

  /// The artboard's sheet: 740 of 844 px.
  static const double large = 740 / 844;
  static const double medium = 0.5;

  /// Dragged below [medium], the sheet closes.
  static const double closed = 0.25;

  /// A tablet by its shortest side, so turning it does not swap the pane for
  /// a sheet.
  static const double tabletFrom = 600;

  @override
  ConsumerState<WordDetailView> createState() => _WordDetailViewState();
}

class _WordDetailViewState extends ConsumerState<WordDetailView> {
  /// Once, when the word is there to say — not on every state change. A flag
  /// rather than closing the subscription: with the data already there, the
  /// listener runs before `listenManual` has returned it.
  bool _spoken = false;
  ProviderSubscription<AsyncValue<WordDetail?>>? _waiting;

  @override
  void initState() {
    super.initState();
    if (widget.speak) _speakOnceLoaded();
  }

  @override
  void didUpdateWidget(WordDetailView old) {
    super.didUpdateWidget(old);
    if (widget.speak && (!old.speak || widget.arrival != old.arrival)) {
      _speakOnceLoaded();
    }
  }

  void _speakOnceLoaded() {
    _spoken = false;
    _waiting?.close();
    _waiting = ref.listenManual(wordDetailProvider(widget.uid), (_, next) {
      final word = next.value?.word.word;
      if (word == null || _spoken) return;
      _spoken = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(say(ref, context, spokenForm(word)));
      });
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final detail = ref.watch(wordDetailProvider(widget.uid));

    final Widget body;
    if (detail.hasError) {
      body = _Message(
        child: DpErrorPanel(
          message: l10n.wordLoadFailed,
          retryLabel: l10n.retry,
          onRetry: () => ref.invalidate(wordDetailProvider(widget.uid)),
        ),
      );
    } else if (detail.value case final value?) {
      body = _Body(detail: value);
    } else if (detail.hasValue) {
      body = _Message(
        child: DpText(
          l10n.wordNotFound,
          role: DpTextRole.body,
          textAlign: TextAlign.center,
        ),
      );
    } else {
      body = const SizedBox.shrink();
    }

    final loaded = detail.value;
    return ListView(
      controller: widget.scroll,
      padding: EdgeInsets.zero,
      children: <Widget>[
        if (widget.presentation == WordDetailPresentation.sheet)
          const _Handle(),
        if (loaded != null)
          _Header(word: loaded.word, presentation: widget.presentation)
        else if (widget.presentation == WordDetailPresentation.page)
          const _BackRow(),
        body,
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(20), child: child);
}

/// The sheet's grabber: 36 × 5, with 8 above and 12 below.
class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Center(
        child: Container(
          width: 36,
          height: 5,
          decoration: BoxDecoration(
            color: tokens.isGlass
                ? tokens.surface.outline
                : tokens.surface.muted,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}

/// The page's way back, under the status bar.
class _BackRow extends StatelessWidget {
  const _BackRow({this.colour});

  final Color? colour;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      SizedBox(height: MediaQuery.paddingOf(context).top),
      // The bar's height, or the back button's when larger text makes
      // its label taller (#404).
      SizedBox(
        height: math.max(
          context.isCupertino
              ? AdaptiveScaffold.cupertinoBarHeight
              : AdaptiveScaffold.materialBarHeight,
          AdaptiveBackButton.heightOf(context),
        ),
        child: Row(
          children: <Widget>[
            const SizedBox(width: 4),
            AdaptiveBackButton(
              colour: context.isCupertino ? null : colour,
              onPressed: () => leaveWordPage(context),
            ),
          ],
        ),
      ),
    ],
  );
}

/// The gender-tinted strip: article and headword, the speaker, the step and
/// status chips.
///
/// On paper the strip is the gender's own colour and everything on it takes
/// that colour's ink — the article too, which is still printed, so the gender
/// is never colour alone. Under glass it is a wash, and the headword keeps
/// its usual article colour. A word with no article sits on Oat.
class _Header extends ConsumerWidget {
  const _Header({required this.word, required this.presentation});

  final WordWithState word;
  final WordDetailPresentation presentation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final article = word.word.article;
    final gender = tokens.color.forArticle(article);
    final onFill = gender == null || tokens.isGlass
        ? null
        : gender == tokens.color.der
        ? tokens.color.onDer
        : tokens.color.onPrimary;

    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        switch (presentation) {
          WordDetailPresentation.sheet => 4,
          WordDetailPresentation.pane => 20,
          WordDetailPresentation.page => 0,
        },
        20,
        16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: DpHeadword(
                  word.word.german,
                  article: article,
                  colour: onFill,
                ),
              ),
              const SizedBox(width: 12),
              DpSpeakerButton(
                semanticLabel: l10n.wordPronounce(spokenForm(word.word)),
                state: speakerState(ref, spokenForm(word.word)),
                onPressed: () =>
                    unawaited(say(ref, context, spokenForm(word.word))),
                onLongPress: () => unawaited(
                  say(ref, context, spokenForm(word.word), pace: 0.75),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              DpChip(label: word.word.sublevelCode, ink: onFill),
              WordStatusChip(word.status),
            ],
          ),
        ],
      ),
    );

    final framed = presentation == WordDetailPresentation.page
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _BackRow(colour: onFill),
              content,
            ],
          )
        : content;

    if (tokens.isGlass) {
      return DpSurface(
        kind: gender == null ? DpSurfaceKind.bar : DpSurfaceKind.tint(gender),
        radius: 0,
        child: framed,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: gender ?? tokens.surface.muted,
        border: Border(bottom: BorderSide(color: tokens.color.ink, width: 2)),
      ),
      child: framed,
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.detail});

  final WordDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final word = detail.word.word;
    final meaning = detail.meaning;
    final (:english, :bangla) = meaningsFor(word, meaning);
    final history = ref.watch(wordHistoryProvider(word.uid)).value;
    final caption = history == null
        ? null
        : historyCaption(detail.word, history, ref.watch(todayProvider), l10n);
    final collocations = word.collocations;
    final register = word.synonymsRegister;
    final notes = <String>[
      if (collocations != null && collocations.isNotEmpty)
        // The course separates them with semicolons; the artboard with dots.
        l10n.studyCollocations(collocations.split('; ').join(' · ')),
      if (register != null && register.isNotEmpty) l10n.studyRegister(register),
    ];
    final compare = comparesSet(word.german);
    final translated = ref.watch(exampleTranslationsProvider(word.uid));
    final tip = detail.tip;

    Widget gap(double height) => SizedBox(height: height);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DpText(
            frontCaption(word, l10n, pron: detail.pron),
            role: DpTextRole.caption,
            color: tokens.color.textSecondary,
          ),
          gap(12),
          if (english != null)
            DpText(english, role: DpTextRole.bodyLarge, weight: 500),
          if (english != null && bangla != null) gap(2),
          if (bangla != null)
            DpText(
              bangla,
              role: DpTextRole.bodyLarge,
              color: english == null ? null : tokens.color.textSecondary,
            ),
          if (detail.examples.isNotEmpty) ...<Widget>[
            gap(12),
            DpText(
              l10n.wordExamples.toUpperCase(),
              role: DpTextRole.caption,
              weight: 700,
              letterSpacing: 0.6,
              color: tokens.color.textSecondary,
            ),
            for (final example in detail.examples) ...<Widget>[
              gap(8),
              StudyExampleRow(
                example,
                onPlay: () => unawaited(say(ref, context, example.german)),
              ),
              if (translated[example.german] case final line?)
                Padding(
                  padding: const EdgeInsets.only(left: 42, top: 2),
                  child: DpText(
                    line,
                    role: DpTextRole.body,
                    color: tokens.color.textSecondary,
                  ),
                ),
            ],
          ],
          if (tip != null) ...<Widget>[
            gap(12),
            DpCallout.text(l10n.studyTip(tipText(tip, meaning))),
          ],
          if (notes.isNotEmpty || compare) ...<Widget>[
            gap(12),
            _Notes(
              notes: notes,
              compareUid: compare ? word.uid : null,
              set: word.german,
            ),
          ],
          if (caption != null) ...<Widget>[
            gap(12),
            DpText(
              caption,
              role: DpTextRole.caption,
              color: tokens.color.textSecondary,
            ),
          ],
          gap(12),
          _Actions(detail: detail),
        ],
      ),
    );
  }
}

/// FR-W1-01…05: what the learner can do with the word, each with *Undo* in
/// the snackbar (FR-W1-04); the card-mode toggle; and the web chips.
class _Actions extends ConsumerStatefulWidget {
  const _Actions({required this.detail});

  final WordDetail detail;

  @override
  ConsumerState<_Actions> createState() => _ActionsState();
}

class _ActionsState extends ConsumerState<_Actions> {
  /// One action at a time: a double tap on *Mark known* must not rate twice,
  /// and its *Undo* must undo the one it names.
  bool _busy = false;

  WordWithState get _word => widget.detail.word;

  Future<void> _run(
    Future<Undo> Function(WordActions actions) action,
    String message,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    // Today's plan is read once, when the day opens: a row W1 adds, closes
    // or drops reaches Today's list and ring only when it is read again. The
    // container, because *Undo* can come after the sheet has gone.
    final container = ProviderScope.containerOf(context, listen: false);
    void replan() => container.invalidate(todayPlanProvider);
    try {
      final undo = await action(ref.read(wordActionsProvider));
      replan();
      if (!mounted) return;
      DpUndo.show(
        context,
        message: message,
        onUndo: () => unawaited(undo().then((_) => replan())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// FR-W1-02: a reset clears the word's progress, so it asks first.
  Future<void> _reset(String name) async {
    final l10n = AppLocalizations.of(context);
    final sure = await Adaptive.showConfirm(
      context: context,
      title: l10n.wordResetTitle(name),
      message: l10n.wordResetBody,
      confirmLabel: l10n.wordResetConfirm,
      cancelLabel: l10n.wordResetCancel,
      destructive: true,
    );
    if (sure != true || !mounted) return;
    await _run(
      (actions) => actions.reset(_word.uid, today: ref.read(todayProvider)),
      l10n.wordWasReset(name),
    );
  }

  void _translate() {
    final detail = widget.detail;
    unawaited(
      ref.read(exampleTranslationsProvider(_word.uid).notifier).translate(
        <String>[for (final example in detail.examples) example.german],
        // Into the meaning language (`translation.md`): Bangla, since an
        // English learner is not offered it.
        to: 'bn',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final word = _word;
    final uid = word.uid;
    final name = spokenForm(word.word);
    final cloze = word.state?.cardMode == CardMode.cloze.name;
    final detail = widget.detail;

    Widget button(IconData icon, String label, VoidCallback onPressed) =>
        DpButton(
          label: label,
          kind: DpButtonKind.secondary,
          compact: true,
          expand: false,
          icon: Icon(icon, size: 18),
          onPressed: _busy ? null : onPressed,
        );

    void act(Future<Undo> Function(WordActions actions) action, String done) =>
        unawaited(_run(action, done));

    void mode(CardMode to) => act(
      (actions) => actions.setCardMode(uid, to),
      to == CardMode.cloze ? l10n.wordNowCloze(name) : l10n.wordNowPlain(name),
    );

    final links = SearchRepository.webLinks(word.word.german);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            if (word.status == WordStatus.todo)
              button(
                Icons.add,
                l10n.wordAddToday,
                () => act(
                  (actions) => actions.addToToday(
                    uid,
                    today: ref.read(todayProvider),
                    step: word.word.sublevelCode,
                  ),
                  l10n.wordAddedToday(name),
                ),
              ),
            // A suspended word is out of review until resumed (BR-STATUS-03).
            if (!word.isSuspended)
              button(
                Icons.check,
                l10n.wordMarkKnown,
                () => act(
                  (actions) =>
                      actions.markKnown(uid, today: ref.read(todayProvider)),
                  l10n.wordMarkedKnown(name),
                ),
              ),
            if (word.isSuspended)
              button(
                Icons.play_arrow,
                l10n.wordResume,
                () => act(
                  (actions) => actions.resume(uid),
                  l10n.wordResumed(name),
                ),
              )
            else
              button(
                Icons.pause,
                l10n.wordSuspend,
                () => act(
                  (actions) =>
                      actions.suspend(uid, today: ref.read(todayProvider)),
                  l10n.wordSuspended(name),
                ),
              ),
            if (word.state != null)
              button(
                Icons.restart_alt,
                l10n.wordReset,
                () => unawaited(_reset(name)),
              ),
            button(Icons.copy, l10n.wordCopy, () {
              unawaited(Clipboard.setData(ClipboardData(text: name)));
              DpToast.show(context, l10n.wordCopied(name));
            }),
            // An English learner's examples come translated already.
            if (detail.translate &&
                detail.meaning != MeaningLanguage.english &&
                detail.examples.isNotEmpty)
              button(Icons.translate, l10n.wordTranslate, _translate),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            DpChip(
              label: l10n.wordPlainCard,
              kind: DpChipKind.filter,
              selected: !cloze,
              onTap: cloze && !_busy ? () => mode(CardMode.plain) : null,
            ),
            DpChip(
              label: l10n.wordClozeCard,
              kind: DpChipKind.filter,
              selected: cloze,
              onTap: !cloze && !_busy ? () => mode(CardMode.cloze) : null,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final source in <WebSource>[
              WebSource.duden,
              WebSource.dwds,
              WebSource.wiktionary,
            ])
              DpChip(
                label: source.label,
                kind: DpChipKind.webLink,
                semanticLabel: l10n.searchOpenWeb(source.label),
                onTap: () =>
                    unawaited(ref.read(openWebProvider)(links[source]!)),
              ),
          ],
        ),
      ],
    );
  }
}

/// The Oat box under the examples: collocations (⟶), register (≈) and, for a
/// headword that names a set, the way to W2.
class _Notes extends StatelessWidget {
  const _Notes({required this.notes, required this.set, this.compareUid});

  final List<String> notes;
  final String set;
  final String? compareUid;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final uid = compareUid;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface.muted,
        borderRadius: BorderRadius.circular(tokens.shape.button),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final (index, note) in notes.indexed) ...<Widget>[
              if (index > 0) const SizedBox(height: 4),
              DpText(note, role: DpTextRole.caption),
            ],
            if (uid != null) _CompareLink(uid: uid, set: set),
          ],
        ),
      ),
    );
  }
}

/// FR-W1-06: *Compare a synonym set (…)*, to W2.
class _CompareLink extends StatelessWidget {
  const _CompareLink({required this.uid, required this.set});

  final String uid;
  final String set;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final label = AppLocalizations.of(context).wordCompare(set);
    void open() => CompareRoute.open(context, uid);
    return Semantics(
      button: true,
      label: label,
      onTap: open,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: open,
        child: ConstrainedBox(
          // 48 dp to hit, however short the line is drawn.
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: <Widget>[
              Flexible(
                child: DpText(
                  label,
                  role: DpTextRole.caption,
                  weight: 700,
                  color: tokens.color.link,
                ),
              ),
              Icon(Icons.chevron_right, size: 16, color: tokens.color.link),
            ],
          ),
        ),
      ),
    );
  }
}

/// W1's history caption — "Next review in 8 days · reviewed 5 times · last:
/// Good" — or null for a word never reviewed, which has no history to tell.
/// A suspended word has no next review, so that part is left out.
String? historyCaption(
  WordWithState word,
  ReviewHistory history,
  String today,
  AppLocalizations l10n,
) {
  if (history.reviews == 0) return null;
  final due = word.state?.due;
  final last = history.last;
  return <String>[
    if (due != null && !word.isSuspended)
      switch (daysBetween(today, due)) {
        <= 0 => l10n.wordDueToday,
        final days => l10n.wordNextReview(days),
      },
    l10n.wordReviewed(history.reviews),
    if (last != null)
      l10n.wordLastRating(switch (last) {
        Rating.again => l10n.ratingAgain,
        Rating.hard => l10n.ratingHard,
        Rating.good => l10n.ratingGood,
        Rating.easy => l10n.ratingEasy,
      }),
  ].join(' · ');
}
