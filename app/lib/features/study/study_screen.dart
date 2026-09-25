import 'dart:async';

import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/fsrs.dart' show Rating;
import 'package:deutschplan/data/repositories/rating_service.dart'
    show CardMode;
import 'package:deutschplan/features/study/study_back.dart';
import 'package:deutschplan/features/study/study_card.dart';
import 'package:deutschplan/features/study/study_cloze.dart';
import 'package:deutschplan/features/study/study_motion.dart';
import 'package:deutschplan/features/study/study_rating.dart';
import 'package:deutschplan/features/study/study_session.dart';
import 'package:deutschplan/features/study/study_summary.dart';
import 'package:deutschplan/router/cross_tab.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:url_launcher/url_launcher.dart';

part 'study_screen.g.dart';

/// A word, for the card showing it.
@riverpod
Future<WordWithState?> studyWord(Ref ref, String uid) =>
    ref.watch(wordRepositoryProvider).find(uid);

/// FR-T2-10: the cloze a word's card shows instead of its front, or null for
/// the plain card — its `card_mode` is plain, or no example holds the word.
@riverpod
Future<StudyCloze?> studyCloze(Ref ref, String uid) async {
  // A word of the learner's own keeps the plain card (#363): the cloze's
  // footnote sends the learner to W1's card toggle, which R2 doesn't have.
  if (customId(uid) != null) return null;
  final found = await ref.watch(studyWordProvider(uid).future);
  if (found == null || found.state?.cardMode != CardMode.cloze.name) {
    return null;
  }
  final back = await ref.watch(studyBackProvider(uid).future);
  return clozeOf(found.word, back.examples);
}

/// #430: what the session's cards will say, in their order: each word with
/// its article, then its first example when `autoplay_example` is on. The
/// voice makes these clips ahead, so a card's first sound doesn't wait for
/// its synthesis.
@riverpod
Future<List<String>> studySayings(Ref ref, SessionArgs args) async {
  // Read once, not watched: the session moves at every rating, and the
  // cards' own providers must not be held with what they were at its start
  // (a card mode changed mid-session is the card's to see).
  final session = await ref.read(studySessionProvider(args).future);
  final words = ref.read(wordRepositoryProvider);
  final dao = ref.read(contentDaoProvider);
  final examples = ref.read(settingsProvider).read(SettingKeys.autoplayExample);
  final sayings = <String>[];
  for (final item in session.items) {
    if (item.kind == SessionBlockKind.grammar) continue;
    final found = await words.find(item.uid);
    if (found == null) continue;
    sayings.add(spokenForm(found.word));
    // ponytail: the course's first example, as `studyBack` gives it; a word
    // of the learner's own plays its example unprepared.
    if (examples && customId(item.uid) == null) {
      final first = (await dao.examplesForWord(item.uid).get()).firstOrNull;
      if (first != null) sayings.add(first.german);
    }
  }
  return sayings;
}

/// The category most of the session's new words share, for the New block's
/// banner: "Neue Wörter · Wohnen & Haushalt".
@riverpod
Future<String?> studyCategory(Ref ref, SessionArgs args) =>
    ref.watch(contentDaoProvider).mainCategory(<String>[
      for (final block in args.blocks)
        if (block.kind == SessionBlockKind.newWords) ...block.uids,
    ]);

/// T2 · Study session, the shell (`docs/04-screens/study-session.md`).
///
/// The top bar, the per-block progress strip, the block banner, and the card
/// slot the card states fill (#101–#104).
class StudyScreen extends ConsumerStatefulWidget {
  const StudyScreen({required this.args, super.key});

  final SessionArgs args;

  /// FR-T2-06: how long a block's banner shows.
  static const Duration bannerTime = Duration(seconds: 1);

  @override
  ConsumerState<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends ConsumerState<StudyScreen> {
  /// The position whose banner last played, so each block plays it once.
  int? _bannered;
  bool _banner = false;
  Timer? _hide;

  /// Held for [dispose], where `ref` can no longer be used.
  late final ProviderContainer _container = ProviderScope.containerOf(
    context,
    listen: false,
  );

  /// What the session's cards will say, as it is known; closed in [dispose]
  /// before the session goes, which would otherwise ask it to rebuild.
  ProviderSubscription<AsyncValue<List<String>>>? _sayings;

  @override
  void initState() {
    super.initState();
    // #430: the session's clips, made ahead while its first card shows.
    _sayings = ref.listenManual(studySayingsProvider(widget.args), (_, next) {
      if (next.value case final sayings?) {
        unawaited(ref.read(ttsProvider).prepare(sayings));
      }
    }, fireImmediately: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container;
  }

  @override
  void dispose() {
    _hide?.cancel();
    _sayings?.close();
    // What is left to make is for a session no longer open.
    unawaited(_container.read(ttsProvider).prepare(const <String>[]));
    // A next step from T3 replaces this screen rather than popping it, so
    // the pop handler never runs: the session is cleared here too.
    _container.invalidate(studySessionProvider(widget.args));
    super.dispose();
  }

  /// FR-T2-07: no prompt. Every card was written as it was rated, so there
  /// is nothing to lose, and Today continues from what is left. The session
  /// is cleared on the way out, whichever way out — see [build].
  void _close() => Navigator.of(context).maybePop();

  /// Set once the screen is on its way out, so a rebuild does not send it
  /// twice.
  bool _leaving = false;

  void _once(VoidCallback go) {
    if (_leaving) return;
    _leaving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) go();
    });
  }

  /// Out to another screen in this one's place. No pop runs, so the undo
  /// bar goes here; the session is cleared in [dispose].
  void _leave(VoidCallback go) {
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    go();
  }

  /// T3's next step (FR-T3-02, FR-T3-03). The day's next word block is a
  /// new session in this one's place (#328).
  void _step(StudyNextStep step, StudySessionState session, [StudyNext? next]) {
    void block(SessionBlockKind kind, List<String> uids) => _leave(
      () => StudyRoute.instead(
        context,
        SessionArgs(
          planDate: widget.args.planDate,
          blocks: <SessionBlock>[SessionBlock(kind, uids)],
        ),
      ),
    );
    switch (step) {
      case StudyNextStep.done:
        _close();
      case StudyNextStep.revise:
        block(SessionBlockKind.revise, next!.revise);
      case StudyNextStep.newWords:
        block(SessionBlockKind.newWords, next!.newWords);
      case StudyNextStep.grammar:
        final topics = StudySummarySheet.grammarFor(session, next);
        _leave(
          () => GrammarPracticeRoute.instead(
            context,
            GrammarPracticeArgs(topicUids: topics),
          ),
        );
      case StudyNextStep.sentences:
        _leave(() => SentencesRoute.instead(context));
      case StudyNextStep.backlog:
        _leave(() => context.jumpToTab(const BacklogRoute()));
    }
  }

  /// FR-T2-04 *I know it* or FR-T2-03 *Skip → backlog*, each with its
  /// 4 s *Undo*.
  Future<void> _act(StudyItem item, {required bool known}) {
    final notifier = ref.read(studySessionProvider(widget.args).notifier);
    final l10n = AppLocalizations.of(context);
    return _withUndo(
      item,
      known ? notifier.knewIt() : notifier.skip(),
      (name) => known ? l10n.studyKnown(name) : l10n.studySkipped(name),
    );
  }

  /// FR-T2-02: a rating, written and moved past, with its 4 s *Undo*. The
  /// haptic comes first, as the finger lifts: light, and medium for Again.
  Future<void> _rate(StudyItem item, Rating rating) {
    unawaited(
      rating == Rating.again
          ? HapticFeedback.mediumImpact()
          : HapticFeedback.lightImpact(),
    );
    final notifier = ref.read(studySessionProvider(widget.args).notifier);
    final l10n = AppLocalizations.of(context);
    final label = switch (rating) {
      Rating.again => l10n.ratingAgain,
      Rating.hard => l10n.ratingHard,
      Rating.good => l10n.ratingGood,
      Rating.easy => l10n.ratingEasy,
    };
    return _withUndo(
      item,
      notifier.rate(rating),
      (name) => l10n.studyRated(name, label),
    );
  }

  /// Waits for [write], then offers its *Undo* — the same bar for every
  /// card action (DpUndo).
  Future<void> _withUndo(
    StudyItem item,
    Future<void> write,
    String Function(String word) message,
  ) async {
    final notifier = ref.read(studySessionProvider(widget.args).notifier);
    final word = ref.read(studyWordProvider(item.uid)).value?.word;
    await write;
    if (!mounted) return;
    DpUndo.show(
      context,
      message: message(word == null ? item.uid : spokenForm(word)),
      lift: StudyFrontActions.clearance,
      onUndo: () => unawaited(notifier.undo()),
    );
  }

  /// FR-T2-01: *Show meaning*, or a tap on the card.
  void _reveal() =>
      ref.read(studySessionProvider(widget.args).notifier).reveal();

  void _playBanner(StudySessionState session) {
    if (!session.startsBlock || _bannered == session.position) return;
    _bannered = session.position;
    _hide?.cancel();
    setState(() => _banner = true);
    _hide = Timer(StudyScreen.bannerTime, () {
      if (mounted) setState(() => _banner = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final provider = studySessionProvider(widget.args);

    ref.listen(provider, (_, next) {
      final session = next.value;
      if (session != null && !session.finished) _playBanner(session);
    });
    final session = ref.watch(provider).value;

    // The words done: T3's summary over the session — or T6 in its place
    // when the day is complete and no sentences are open. A session that
    // did nothing (everything already done) just closes.
    final date = widget.args.planDate;
    final over =
        session != null && session.wordsDone && session.results.isNotEmpty;
    final nextState = over && date != null
        ? ref.watch(studyNextProvider(date))
        : null;
    final next = nextState?.value;
    final ready = over && (nextState == null || !nextState.isLoading);
    final dayComplete =
        ready &&
        session.grammarLeft.isEmpty &&
        next != null &&
        next.dayDone &&
        next.sentences == 0;
    if (session != null && session.wordsDone && session.results.isEmpty) {
      // Nothing studied: no summary of it. Grammar waiting goes straight to
      // L15; nothing at all, and the session just closes.
      _once(
        session.grammarLeft.isEmpty
            ? _close
            : () => _step(StudyNextStep.grammar, session),
      );
    } else if (dayComplete) {
      _once(() => _leave(() => DayCompleteRoute.instead(context)));
    }
    if (session != null && _bannered == null && session.startsBlock) {
      // The first block's banner, once the queue has been built.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _playBanner(session);
      });
    }

    final place = session?.place;
    final label = place == null
        ? ''
        : switch (place.kind) {
            SessionBlockKind.revise => l10n.studyBlockRevise(
              place.index,
              place.size,
            ),
            SessionBlockKind.newWords => l10n.studyBlockNew(
              place.index,
              place.size,
            ),
            SessionBlockKind.grammar => l10n.studyBlockGrammar(
              place.index,
              place.size,
            ),
            SessionBlockKind.backlog => l10n.studyBlockBacklog(
              place.index,
              place.size,
            ),
          };
    final item = session?.current;
    final revealed = session?.revealed ?? false;
    // A word met for the first time: today's new, or the backlog's.
    final fresh =
        item?.kind == SessionBlockKind.newWords ||
        item?.kind == SessionBlockKind.backlog;
    // Settled before the thumb zone chooses: a cloze card has no *Show
    // meaning*, and a flash of one is a button pressed by mistake.
    final clozeState = item == null || item.kind == SessionBlockKind.grammar
        ? null
        : ref.watch(studyClozeProvider(item.uid));
    final settled = clozeState == null || !clozeState.isLoading;
    final cloze = clozeState?.value;

    final body = SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _TopBar(
            label: label,
            onClose: _close,
            onMenu: item == null
                ? null
                : () => Adaptive.showSheet<void>(
                    context: context,
                    builder: (_) => StudyMenu(item: item),
                  ),
          ),
          if (session != null) _ProgressStrip(blocks: session.blocks),
          Expanded(
            child: Stack(
              children: <Widget>[
                if (item != null && session != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: StudyCardMotion(
                      position: session.position,
                      left: session.results[session.position - 1],
                      // Face down the card sits in the middle; turned over it
                      // rises to the top to make room for its back.
                      child: AnimatedAlign(
                        alignment: revealed
                            ? Alignment.topCenter
                            : Alignment.center,
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : tokens.motion.quick,
                        curve: Curves.easeOut,
                        child: SingleChildScrollView(
                          child: StudySwipeToRate(
                            enabled:
                                revealed &&
                                item.kind != SessionBlockKind.grammar &&
                                ref
                                    .watch(settingsProvider)
                                    .read(SettingKeys.swipeToRate),
                            onRated: (rating) => _rate(item, rating),
                            child: StudyCardSlot(
                              item: item,
                              revealed: revealed,
                              onReveal: _reveal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (item != null)
                  _BlockBanner(
                    visible: _banner,
                    kind: item.kind,
                    label: switch (item.kind) {
                      SessionBlockKind.revise => l10n.studyBannerRevise,
                      SessionBlockKind.newWords => switch (ref
                          .watch(studyCategoryProvider(widget.args))
                          .value) {
                        final category? => l10n.studyBannerNewCategory(
                          category,
                        ),
                        null => l10n.studyBannerNew,
                      },
                      SessionBlockKind.grammar => l10n.studyBannerGrammar,
                      SessionBlockKind.backlog => l10n.studyBannerBacklog,
                    },
                  ),
              ],
            ),
          ),
          // The thumb zone. Face down: the hint and *Show meaning*, and no
          // rating bar until the card is turned over.
          if (item != null &&
              item.kind != SessionBlockKind.grammar &&
              !revealed &&
              settled &&
              cloze == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (fresh)
                    StudyNewActions(
                      onKnown: () => _act(item, known: true),
                      // Already in the backlog: nowhere to skip it to.
                      onSkip: item.kind == SessionBlockKind.backlog
                          ? null
                          : () => _act(item, known: false),
                    ),
                  StudyFrontActions(onReveal: _reveal, hint: !fresh),
                ],
              ),
            ),
          // Turned over: the prompt and the rating bar (FR-T2-02, FR-T2-05).
          if (item != null && item.kind != SessionBlockKind.grammar && revealed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: StudyRatingActions(
                uid: item.uid,
                prompt: cloze == null
                    ? l10n.studyRatePrompt
                    : l10n.studyClozeRatePrompt,
                onRated: (rating) => _rate(item, rating),
              ),
            ),
        ],
      ),
    );

    final summary = ready && !dayComplete
        ? StudySummaryOverlay(
            child: StudySummarySheet(
              session: session,
              next: next,
              onStep: (step) => _step(step, session, next),
            ),
          )
        : null;
    final page = summary == null
        ? body
        : Stack(
            children: <Widget>[
              Positioned.fill(child: body),
              summary,
            ],
          );

    // Every way out clears the session: the X, Android's back, the iOS swipe.
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return;
        // The undo bar belongs to the app's messenger, not this route: left
        // up, its *Undo* would reach a session that no longer exists.
        ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
        ref.invalidate(studySessionProvider(widget.args));
      },
      child: AdaptiveScaffold(
        backgroundColor: tokens.isGlass
            ? tokens.surface.paper.withValues(alpha: 0)
            : tokens.surface.paper,
        body: tokens.isGlass
            ? AuroraBackdrop(
                // study-session.md: under glass the aurora leads with the
                // word's gender colour.
                leading:
                    tokens.color.forArticle(
                      item == null || item.kind == SessionBlockKind.grammar
                          ? null
                          : ref
                                .watch(studyWordProvider(item.uid))
                                .value
                                ?.word
                                .article,
                    ) ??
                    tokens.color.primary,
                child: page,
              )
            : page,
      ),
    );
  }
}

/// Close · "Revise · 4 / 10" · the overflow menu.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.label, required this.onClose, this.onMenu});

  final String label;
  final VoidCallback onClose;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    Widget action(IconData icon, String semantic, VoidCallback? onTap) =>
        Semantics(
          button: true,
          label: semantic,
          excludeSemantics: true,
          onTap: onTap,
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: SizedBox.square(
              dimension: 48,
              child: Icon(icon, color: tokens.color.ink),
            ),
          ),
        );

    return SizedBox(
      height: 56,
      child: Row(
        children: <Widget>[
          const SizedBox(width: 8),
          action(Icons.close, l10n.studyClose, onClose),
          const SizedBox(width: 4),
          Expanded(
            child: DpText(
              label,
              role: DpTextRole.bodyLarge,
              weight: 600,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 4),
          action(Icons.more_horiz, l10n.studyMenu, onMenu),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// One segment per block, filling per card over the track: Revise Lagoon, New
/// Sun, Grammar the secondary text's Slate, a step past the track (#437).
class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip({required this.blocks});

  final List<StudyBlock> blocks;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: <Widget>[
          for (var i = 0; i < blocks.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              flex: blocks[i].size,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 6,
                  child: ColoredBox(
                    color: tokens.surface.track,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FractionallySizedBox(
                        widthFactor: blocks[i].done / blocks[i].size,
                        heightFactor: 1,
                        child: ColoredBox(
                          color: switch (blocks[i].kind) {
                            SessionBlockKind.revise => tokens.color.primary,
                            SessionBlockKind.newWords ||
                            SessionBlockKind.backlog => tokens.color.accent,
                            SessionBlockKind.grammar =>
                              tokens.color.textSecondary,
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// FR-T2-06: the block's name, sliding in for a second as the block starts.
class _BlockBanner extends StatelessWidget {
  const _BlockBanner({
    required this.visible,
    required this.kind,
    required this.label,
  });

  final bool visible;
  final SessionBlockKind kind;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final still = MediaQuery.disableAnimationsOf(context);
    final duration = still ? Duration.zero : const Duration(milliseconds: 220);
    return Align(
      alignment: Alignment.topCenter,
      child: IgnorePointer(
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, -0.4),
          duration: duration,
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: duration,
            // The StudyNew artboard's strip: the block's colour from the
            // progress strip, a 1.5 px ink edge, 8 px corners, full width.
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Semantics(
                liveRegion: true,
                child: SizedBox(
                  width: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: switch (kind) {
                        SessionBlockKind.revise => tokens.color.primary,
                        SessionBlockKind.newWords ||
                        SessionBlockKind.backlog => tokens.color.accent,
                        SessionBlockKind.grammar => tokens.surface.muted,
                      },
                      borderRadius: BorderRadius.circular(tokens.shape.chip),
                      border: Border.all(
                        color: tokens.color.ink,
                        width: tokens.surface.outlineWidth + 0.5,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: DpText(
                        label,
                        role: DpTextRole.label,
                        weight: 700,
                        textAlign: TextAlign.center,
                        color: kind == SessionBlockKind.grammar
                            ? tokens.color.ink
                            : tokens.color.onAccent,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The card slot: the word card, front and back (#101, #102); the new-word
/// card and the cloze card follow (#103, #104). A grammar set shows its topic
/// until L15 exists.
class StudyCardSlot extends ConsumerWidget {
  const StudyCardSlot({
    required this.item,
    super.key,
    this.revealed = false,
    this.onReveal,
  });

  final StudyItem item;
  final bool revealed;
  final VoidCallback? onReveal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final word = item.kind == SessionBlockKind.grammar
        ? null
        : ref.watch(studyWordProvider(item.uid)).value?.word;
    final cloze = word == null ? null : ref.watch(studyClozeProvider(item.uid));
    if (word != null && cloze != null && !cloze.isLoading) {
      final gap = cloze.value;
      if (gap != null) {
        return StudyClozeCard(
          // A clean gap for every word, whatever was built before it.
          key: ValueKey<String>(word.uid),
          word: word,
          cloze: gap,
          onChecked: () => onReveal?.call(),
        );
      }
      return StudyWordCard(
        word: word,
        revealed: revealed,
        onReveal: onReveal,
        isNew:
            item.kind == SessionBlockKind.newWords ||
            item.kind == SessionBlockKind.backlog,
      );
    }
    return DpSurface(
      selected: !tokens.isGlass,
      padding: const EdgeInsets.fromLTRB(26, 20, 20, 20),
      child: SizedBox(
        width: double.infinity,
        child: const SizedBox(height: 48),
      ),
    );
  }
}

/// The overflow menu: auto-play, speech speed, the word's details, and a
/// report.
class StudyMenu extends ConsumerStatefulWidget {
  const StudyMenu({required this.item, super.key});

  final StudyItem item;

  /// Where a report goes: a new issue on the project, filled in.
  static Uri reportUri(StudyItem item) => Uri.https(
    'github.com',
    '/MdRahmatUllah/DeutschPlan/issues/new',
    <String, String>{
      'title': 'Problem with ${item.kind.name} card ${item.uid}',
      'body':
          'Card: ${item.uid} (${item.kind.name})\n\n'
          'What is wrong with it:\n',
    },
  );

  @override
  ConsumerState<StudyMenu> createState() => _StudyMenuState();
}

class _StudyMenuState extends ConsumerState<StudyMenu> {
  static final Map<double, String> _speeds = <double, String>{
    0.75: '0.75×',
    1.0: '1×',
    1.25: '1.25×',
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final autoplay = settings.read(SettingKeys.autoplayHeadword);
    final speed = settings.read(SettingKeys.ttsSpeed);
    final word = widget.item.kind != SessionBlockKind.grammar;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: DpText(l10n.studyMenuAutoplay, role: DpTextRole.body),
              ),
              AdaptiveSwitch(
                value: autoplay,
                semanticLabel: l10n.studyMenuAutoplay,
                onChanged: (on) async {
                  await settings.write(SettingKeys.autoplayHeadword, on);
                  setState(() {});
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          DpText(l10n.studyMenuSpeed, role: DpTextRole.body),
          const SizedBox(height: 8),
          AdaptiveSegmented<double>(
            segments: _speeds,
            value: _speeds.containsKey(speed) ? speed : 1.0,
            onChanged: (value) async {
              await settings.write(SettingKeys.ttsSpeed, value);
              setState(() {});
            },
          ),
          const SizedBox(height: 8),
          if (word)
            DpButton(
              label: l10n.studyMenuWordDetails,
              kind: DpButtonKind.text,
              onPressed: () {
                Navigator.of(context).pop();
                // A word of the learner's own opens where it was written:
                // R2 (#363).
                if (customId(widget.item.uid) case final id?) {
                  EditCustomWordRoute.open(context, id);
                } else {
                  WordRoute.open(context, widget.item.uid);
                }
              },
            ),
          DpButton(
            label: l10n.studyMenuReport,
            kind: DpButtonKind.text,
            onPressed: () {
              Navigator.of(context).pop();
              unawaited(
                launchUrl(
                  StudyMenu.reportUri(widget.item),
                  mode: LaunchMode.externalApplication,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
