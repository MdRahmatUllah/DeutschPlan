import 'dart:async';
import 'dart:math' as math;

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/plan_repository.dart'
    show PlanKind;
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/compare_set.dart';
import 'package:deutschplan/domain/quiz_builder.dart';
import 'package:deutschplan/features/study/study_back.dart'
    show StudyPlayButton;
import 'package:deutschplan/features/today/today_providers.dart';
import 'package:deutschplan/features/words/speak.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'compare_screen.g.dart';

/// W2's set, as the screen draws it (`compare.md`).
@immutable
class CompareView {
  const CompareView({
    required this.set,
    required this.members,
    required this.todo,
    required this.quizItems,
  });

  /// The set word: "Grund / Ursache / Anlass".
  final CompareWord set;
  final List<CompareMember> members;

  /// The members' words still To do, which *Add all* adds (as W1's *Add to
  /// today* is offered, FR-W1-01).
  final List<WordWithState> todo;

  /// How many items *Quiz these* asks, [CompareScreen.quizLength] at most.
  final int quizItems;
}

/// W2's set: read once, as the course is read-only, with its members'
/// words watched, so *Add all* follows their status.
@riverpod
Stream<CompareView?> compareView(Ref ref, String uid) async* {
  // Everything watched is read before the first await, as W1's provider.
  final dao = ref.watch(contentDaoProvider);
  final words = ref.watch(wordRepositoryProvider);
  final set = await dao.compareSet(uid);
  if (set == null) {
    yield null;
    return;
  }
  final members = compareMembers(set);
  final quizItems = compareQuizItems(
    members,
    setUid: uid,
    seed: 0,
    length: CompareScreen.quizLength,
  ).length;
  yield* words
      .watchWords(<String>[for (final member in members) ?member.uid])
      .map(
        (states) => CompareView(
          set: set.word,
          members: members,
          todo: <WordWithState>[
            for (final word in states)
              if (word.status == WordStatus.todo) word,
          ],
          quizItems: quizItems,
        ),
      );
}

/// FR-W2-03: the quiz *Quiz these* starts, from set [uid]'s sentences.
QuizArgs compareQuiz(String uid) => QuizArgs(
  direction: QuizDirection.compare.name,
  source: QuizSource.compareSet.name,
  sourceRef: uid,
  length: CompareScreen.quizLength,
  seed: math.Random().nextInt(1 << 31),
);

/// W2 · Compare words (`compare.md`, `Compare-android.html`, #142): a
/// near-synonym set side by side — the first column pinned while the members
/// scroll sideways on a phone, every column at once on a tablet — with
/// *Quiz these* and *Add all to today*.
class CompareScreen extends ConsumerStatefulWidget {
  const CompareScreen({required this.uid, super.key});

  /// The set word's.
  final String uid;

  /// FR-W2-03: *Quiz these · 5 items*.
  static const int quizLength = 5;

  @override
  ConsumerState<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends ConsumerState<CompareScreen> {
  final ScrollController _sideways = ScrollController();

  /// One *Add all* at a time: a double tap must not add twice.
  bool _busy = false;

  @override
  void dispose() {
    _sideways.dispose();
    super.dispose();
  }

  Future<void> _addAll(List<WordWithState> words) async {
    if (_busy) return;
    setState(() => _busy = true);
    final actions = ref.read(wordActionsProvider);
    final today = ref.read(todayProvider);
    // The container, not ref: the screen may be gone before the adds are.
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      for (final word in words) {
        await actions.addToToday(
          word.uid,
          today: today,
          step: word.word.sublevelCode,
        );
      }
      // Today's plan is read once, when the day opens (as W1 replans).
      container.invalidate(todayPlanProvider);
      if (mounted) {
        DpToast.show(
          context,
          AppLocalizations.of(context).compareAdded(words.length),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(compareViewProvider(widget.uid));
    // Already in today's plan is not waiting to be added.
    final open =
        ref.watch(todayOpenProvider).value ?? const <(String, String)>{};

    final Widget body;
    if (view.hasError) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: DpErrorPanel(
          message: l10n.compareLoadFailed,
          retryLabel: l10n.retry,
          onRetry: () => ref.invalidate(compareViewProvider(widget.uid)),
        ),
      );
    } else if (view.value case final value?) {
      final todo = <WordWithState>[
        for (final word in value.todo)
          if (!open.contains((PlanKind.newWord.wire, word.uid))) word,
      ];
      body = _Body(
        view: value,
        sideways: _sideways,
        quiz: value.quizItems == 0
            ? null
            : () => QuizRoute.open(context, compareQuiz(widget.uid)),
        addLabel: todo.isEmpty ? null : l10n.compareAddAll(todo.length),
        onAdd: _busy ? null : () => unawaited(_addAll(todo)),
      );
    } else if (view.hasValue) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: DpText(
          l10n.compareNotFound,
          role: DpTextRole.body,
          textAlign: TextAlign.center,
        ),
      );
    } else {
      body = const SizedBox.shrink();
    }

    final scaffold = AdaptiveScaffold(
      title: l10n.compareTitle,
      leading: AdaptiveBackButton(
        label: l10n.compareBack,
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
      body: body,
    );
    return tokens.isGlass
        ? AuroraBackdrop(leading: tokens.color.die, child: scaffold)
        : scaffold;
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.view,
    required this.sideways,
    required this.quiz,
    required this.addLabel,
    required this.onAdd,
  });

  final CompareView view;
  final ScrollController sideways;

  /// Null closes *Quiz these*: no sentence names a member.
  final VoidCallback? quiz;

  /// Null hides *Add all*: nothing left To do.
  final String? addLabel;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final members = view.members;
    final addLabel = this.addLabel;

    Widget caption(String text) => DpText(
      text,
      role: DpTextRole.caption,
      color: tokens.color.textSecondary,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // FR-W2-04: a tablet shows every column; a phone scrolls them.
        final fits =
            CompareTable.labelWidth +
                members.length * CompareTable.columnWidth <=
            constraints.maxWidth - 32;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: <Widget>[
                  caption(
                    fits
                        ? l10n.compareSubtitleWide(view.set.step)
                        : l10n.compareSubtitle(view.set.step),
                  ),
                  const SizedBox(height: 12),
                  CompareTable(
                    members: members,
                    sideways: fits ? null : sideways,
                  ),
                  if (!fits) ...<Widget>[
                    const SizedBox(height: 12),
                    caption(l10n.compareDrag(members.last.headword)),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  DpButton(
                    label: l10n.compareQuiz(view.quizItems),
                    onPressed: quiz,
                  ),
                  if (addLabel != null) ...<Widget>[
                    const SizedBox(height: 8),
                    DpButton(
                      label: addLabel,
                      kind: DpButtonKind.secondary,
                      onPressed: onAdd,
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// W2's table: a row per aspect, a column per member, and the labels'
/// column pinned (FR-W2-04).
///
/// One [Table], so a row is as tall as its tallest cell, labels included.
/// It is laid out right to left with the labels last, so they paint over
/// the members; with [sideways], they are moved along by its offset and
/// stay put while the members scroll under them.
class CompareTable extends ConsumerWidget {
  const CompareTable({required this.members, super.key, this.sideways});

  final List<CompareMember> members;

  /// The phone's sideways scroll; null when every column fits.
  final ScrollController? sideways;

  /// The artboard's: a 96 dp label column, members 170 dp at least.
  static const double labelWidth = 96;
  static const double columnWidth = 170;

  /// A cell the course leaves empty (FR-W2-02).
  static const String missing = '—';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final line = BorderSide(color: tokens.surface.outline);
    final head = BorderSide(
      color: tokens.isGlass ? tokens.surface.outline : tokens.color.ink,
      width: 2,
    );
    // Opaque, so the members pass under it: under glass the panel's frost
    // over the backdrop's base.
    final pinned = tokens.isGlass
        ? Color.alphaBlend(tokens.surface.cardStrong, tokens.surface.paper)
        : tokens.surface.paper;
    const padding = EdgeInsets.symmetric(horizontal: 12, vertical: 10);

    Widget label(String? text, BorderSide bottom) {
      final cell = DecoratedBox(
        decoration: BoxDecoration(
          color: pinned,
          border: Border(right: line, bottom: bottom),
        ),
        child: Padding(
          padding: padding,
          child: text == null
              ? const SizedBox.shrink()
              : DpText(
                  text.toUpperCase(),
                  role: DpTextRole.caption,
                  weight: 700,
                  letterSpacing: 0.5,
                  color: tokens.color.textSecondary,
                ),
        ),
      );
      final scroll = sideways;
      if (scroll == null) return cell;
      return ListenableBuilder(
        listenable: scroll,
        builder: (context, child) => Transform.translate(
          offset: Offset(scroll.hasClients ? scroll.offset : 0, 0),
          child: child,
        ),
        child: cell,
      );
    }

    Widget cell(Widget child, BorderSide bottom) => DecoratedBox(
      decoration: BoxDecoration(border: Border(bottom: bottom)),
      child: Padding(
        padding: padding,
        child: Align(alignment: AlignmentDirectional.topStart, child: child),
      ),
    );

    Widget text(String? value) =>
        DpText(value ?? missing, role: DpTextRole.body);

    // Right to left, the labels last: see the class comment.
    TableRow row(
      String? name,
      Widget Function(CompareMember) of, {
      BorderSide? bottom,
    }) => TableRow(
      children: <Widget>[
        for (final member in members.reversed) cell(of(member), bottom ?? line),
        label(name, bottom ?? line),
      ],
    );

    final table = Table(
      textDirection: Directionality.of(context) == TextDirection.ltr
          ? TextDirection.rtl
          : TextDirection.ltr,
      defaultVerticalAlignment: TableCellVerticalAlignment.intrinsicHeight,
      defaultColumnWidth: sideways == null
          ? const FlexColumnWidth()
          : const FixedColumnWidth(columnWidth),
      columnWidths: <int, TableColumnWidth>{
        members.length: const FixedColumnWidth(labelWidth),
      },
      children: <TableRow>[
        row(null, (member) => _Header(member), bottom: head),
        row(l10n.compareMeaning, (member) => text(member.meaning)),
        row(
          l10n.compareRegister,
          (member) => switch (member.register) {
            null => text(null),
            final labels => Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                // A status chip's look, but its label wraps: DpChip's one
                // line would run out of a 170 dp column at 200 % text.
                for (final register in labels)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.surface.muted,
                      borderRadius: BorderRadius.circular(tokens.shape.chip),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: DpText(
                        register,
                        role: DpTextRole.caption,
                        weight: 600,
                      ),
                    ),
                  ),
              ],
            ),
          },
        ),
        row(l10n.compareWith, (member) => text(member.withText)),
        row(
          l10n.compareExample,
          (member) => switch (member.example) {
            null => text(null),
            final example => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                StudyPlayButton(
                  label: l10n.studyPlaySentence,
                  onPressed: () => unawaited(say(ref, context, example.german)),
                ),
                Expanded(
                  child: DpText(
                    example.german,
                    role: DpTextRole.body,
                    italic: true,
                  ),
                ),
              ],
            ),
          },
        ),
        row(
          l10n.compareUseWhen,
          (member) => text(member.useWhen),
          bottom: BorderSide.none,
        ),
      ],
    );

    final radius = tokens.shape.card;
    final inset = tokens.surface.outlineWidth;
    final scroll = sideways;
    return DpSurface(
      kind: DpSurfaceKind.bar,
      radius: radius,
      // Inside the outline, so the pinned column does not paint over it.
      padding: EdgeInsets.all(inset),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - inset),
        child: scroll == null
            ? table
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: scroll,
                child: table,
              ),
      ),
    );
  }
}

/// A member's column head: article and headword, a play button and its
/// step. Tapped, W1 for a member the course has a word for.
class _Header extends ConsumerWidget {
  const _Header(this.member);

  final CompareMember member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        DpHeadword(
          member.headword,
          article: member.article,
          role: DpTextRole.title,
        ),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            StudyPlayButton(
              label: l10n.wordPronounce(member.spoken),
              onPressed: () => unawaited(say(ref, context, member.spoken)),
            ),
            DpChip(label: member.step),
          ],
        ),
      ],
    );
    final uid = member.uid;
    if (uid == null) return content;
    void open() => WordRoute.open(context, uid);
    return Semantics(
      button: true,
      onTap: open,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: open,
        child: content,
      ),
    );
  }
}
