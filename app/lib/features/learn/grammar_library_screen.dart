import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/grammar_repository.dart';
import 'package:deutschplan/features/learn/learn_screen.dart';
import 'package:deutschplan/features/learn/step_grammar.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'grammar_library_screen.g.dart';

/// Every topic of the course with its state, level by level (FR-L3-01).
@riverpod
Stream<List<TopicWithState>> libraryTopics(Ref ref) =>
    ref.watch(grammarRepositoryProvider).watchAll();

/// L3's filter chips.
enum LibraryFilter { all, notLearned, due }

/// FR-L3-02: *Not learned yet* and *Due* read `grammar_state` as L2 does.
bool inFilter(LibraryFilter filter, TopicWithState topic, String today) =>
    switch (filter) {
      LibraryFilter.all => true,
      LibraryFilter.notLearned => topicDue(topic, today) == TopicDue.notLearned,
      LibraryFilter.due => topicDue(topic, today) == TopicDue.due,
    };

/// L3 · Grammar library (`grammar-library.md`, `GrammarLibrary-android.html`):
/// all the course's topics under All · Not learned yet · Due, with live
/// counts, in sticky level bands.
class GrammarLibraryScreen extends ConsumerStatefulWidget {
  const GrammarLibraryScreen({super.key});

  @override
  ConsumerState<GrammarLibraryScreen> createState() =>
      _GrammarLibraryScreenState();
}

class _GrammarLibraryScreenState extends ConsumerState<GrammarLibraryScreen> {
  LibraryFilter _filter = LibraryFilter.all;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final topics = ref.watch(libraryTopicsProvider).value;
    final today = ref.watch(todayProvider);

    final Widget body;
    if (topics == null) {
      body = const SizedBox.expand();
    } else {
      int count(LibraryFilter filter) =>
          topics.where((topic) => inFilter(filter, topic, today)).length;
      final shown = <String, List<TopicWithState>>{};
      for (final topic in topics) {
        if (inFilter(_filter, topic, today)) {
          (shown[topic.topic.levelCode] ??= <TopicWithState>[]).add(topic);
        }
      }
      // The band's height at the learner's text size: a caption line and
      // 6 dp above and below.
      final band = MediaQuery.textScalerOf(context).scale(16) + 12;

      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Sized by its chips, not a fixed height: at 200 % text they grow,
          // and a fixed box would cut them (#314).
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: Row(
              children: <Widget>[
                for (final (filter, label) in <(LibraryFilter, String)>[
                  (
                    LibraryFilter.all,
                    l10n.libraryAll(count(LibraryFilter.all)),
                  ),
                  (
                    LibraryFilter.notLearned,
                    l10n.libraryNotLearned(count(LibraryFilter.notLearned)),
                  ),
                  (
                    LibraryFilter.due,
                    l10n.libraryDue(count(LibraryFilter.due)),
                  ),
                ]) ...<Widget>[
                  DpChip(
                    label: label,
                    kind: DpChipKind.filter,
                    selected: _filter == filter,
                    onTap: () => setState(() => _filter = filter),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: DpText(
                      l10n.libraryNone,
                      role: DpTextRole.body,
                      color: tokens.color.textSecondary,
                    ),
                  )
                : DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: tokens.surface.outline),
                      ),
                    ),
                    child: CustomScrollView(
                      slivers: <Widget>[
                        for (final MapEntry(key: level, value: rows)
                            in shown.entries)
                          // A band stays at the top while its level scrolls
                          // under it, and the next level's band pushes it out.
                          SliverMainAxisGroup(
                            slivers: <Widget>[
                              SliverPersistentHeader(
                                pinned: true,
                                delegate: _Band(level: level, height: band),
                              ),
                              SliverList.builder(
                                itemCount: rows.length,
                                itemBuilder: (context, index) => LibraryRow(
                                  topic: rows[index],
                                  due: topicDue(rows[index], today),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      );
    }

    final scaffold = AdaptiveScaffold(
      title: l10n.libraryTitle,
      leading: AdaptiveBackButton(
        label: l10n.tabLearn,
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
      body: body,
    );
    // Under glass the aurora is behind the bar too, not only the list: the
    // scaffold is see-through, and a bar over nothing drew black.
    return tokens.isGlass
        ? AuroraBackdrop(leading: tokens.color.accent, child: scaffold)
        : scaffold;
  }
}

class _Band extends SliverPersistentHeaderDelegate {
  const _Band({required this.level, required this.height});

  final String level;
  final double height;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrink, bool overlaps) =>
      LevelBand(code: level, path: false);

  @override
  bool shouldRebuild(_Band old) => old.level != level || old.height != height;
}

/// One topic: its title on one line, its step and its status dot.
class LibraryRow extends StatelessWidget {
  const LibraryRow({required this.topic, required this.due, super.key});

  final TopicWithState topic;
  final TopicDue due;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Pushed over the library, so back returns here.
        onTap: () => GrammarTopicRoute.open(context, topic.uid),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          decoration: BoxDecoration(
            color: tokens.surface.card,
            border: Border(bottom: BorderSide(color: tokens.surface.outline)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: DpOneLine(
                  topic.topic.topic,
                  role: DpTextRole.body,
                  weight: 500,
                ),
              ),
              const SizedBox(width: 10),
              DpChip(label: topic.topic.sublevelCode),
              const SizedBox(width: 16),
              TopicDot(due: due),
              const SizedBox(width: 16),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: tokens.color.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
