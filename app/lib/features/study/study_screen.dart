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
import 'package:deutschplan/features/study/study_card.dart';
import 'package:deutschplan/features/study/study_session.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:url_launcher/url_launcher.dart';

part 'study_screen.g.dart';

/// A word, for the card showing it.
@riverpod
Future<WordWithState?> studyWord(Ref ref, String uid) =>
    ref.watch(wordRepositoryProvider).find(uid);

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

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  /// FR-T2-07: no prompt. Every card was written as it was rated, so there
  /// is nothing to lose, and Today continues from what is left. The session
  /// is cleared on the way out, whichever way out — see [build].
  void _close() => Navigator.of(context).maybePop();

  /// FR-T2-04 *I know it* or FR-T2-03 *Skip → backlog*, each with its
  /// 4 s *Undo*.
  Future<void> _act(StudyItem item, {required bool known}) async {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(studySessionProvider(widget.args).notifier);
    final word = ref.read(studyWordProvider(item.uid)).value?.word;
    final name = word == null ? item.uid : spokenForm(word);
    await (known ? notifier.knewIt() : notifier.skip());
    if (!mounted) return;
    DpUndo.show(
      context,
      message: known ? l10n.studyKnown(name) : l10n.studySkipped(name),
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
      if (session == null) return;
      // The last card done: back to Today until the summary (#107) exists.
      if (session.finished) {
        _close();
        return;
      }
      _playBanner(session);
    });
    final session = ref.watch(provider).value;
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
          };
    final item = session?.current;
    final revealed = session?.revealed ?? false;

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
                if (item != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
                        child: StudyCardSlot(
                          item: item,
                          revealed: revealed,
                          onReveal: _reveal,
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
                    },
                  ),
              ],
            ),
          ),
          // The thumb zone. Face down: the hint and *Show meaning*, and no
          // rating bar until the card is turned over.
          if (item != null &&
              item.kind != SessionBlockKind.grammar &&
              !revealed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (item.kind == SessionBlockKind.newWords)
                    StudyNewActions(
                      onKnown: () => _act(item, known: true),
                      onSkip: () => _act(item, known: false),
                    ),
                  StudyFrontActions(
                    onReveal: _reveal,
                    hint: item.kind != SessionBlockKind.newWords,
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    // Every way out clears the session: the X, Android's back, the iOS swipe.
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) ref.invalidate(studySessionProvider(widget.args));
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
                child: body,
              )
            : body,
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

/// One segment per block, filling per card: Revise Lagoon, New Sun, Grammar
/// a darker Oat.
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
                    color: tokens.surface.muted,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FractionallySizedBox(
                        widthFactor: blocks[i].done / blocks[i].size,
                        heightFactor: 1,
                        child: ColoredBox(
                          color: switch (blocks[i].kind) {
                            SessionBlockKind.revise => tokens.color.primary,
                            SessionBlockKind.newWords => tokens.color.accent,
                            SessionBlockKind.grammar =>
                              tokens.color.textSecondary.withValues(alpha: 0.5),
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
                        SessionBlockKind.newWords => tokens.color.accent,
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
    if (word != null) {
      return StudyWordCard(
        word: word,
        revealed: revealed,
        onReveal: onReveal,
        isNew: item.kind == SessionBlockKind.newWords,
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
                WordRoute.open(context, widget.item.uid);
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
