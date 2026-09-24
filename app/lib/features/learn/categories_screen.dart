import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_progress_ring.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/router/cross_tab.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'categories_screen.g.dart';

/// L5's cards, from one grouped query (FR-L5-01).
@riverpod
Stream<List<CategoryProgress>> categories(Ref ref) =>
    ref.watch(wordRepositoryProvider).watchCategoryProgress();

/// A card's tile colour and the ink on it, cycling through the palette in
/// the grid's order: the same list always colours the same way.
(Color, Color) categoryColours(DpTokens tokens, int index) {
  final c = tokens.color;
  final palette = <(Color, Color)>[
    (c.primary, c.onPrimary),
    (c.accent, c.onAccent),
    (c.die, c.onAccent),
    (c.der, c.onDer),
    (c.das, c.onAccent),
    (c.again, c.onAccent),
    (c.hard, c.onAccent),
    (c.easy, c.onAccent),
  ];
  return palette[index % palette.length];
}

/// L5 · Categories (`categories.md`, `Categories-android.html`): every
/// category in a two-column grid, each with its words and a status bar.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final categories = ref.watch(categoriesProvider).value;

    final Widget body;
    if (categories == null) {
      body = const SizedBox.expand();
    } else {
      final rows = (categories.length + 1) ~/ 2;
      body = ListView.builder(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: rows + 1,
        itemBuilder: (context, row) {
          if (row == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: DpText(
                l10n.categoriesLine,
                role: DpTextRole.caption,
                color: tokens.color.textSecondary,
              ),
            );
          }
          final first = (row - 1) * 2;
          Widget card(int index) => index < categories.length
              ? CategoryCard(
                  category: categories[index],
                  colours: categoryColours(tokens, index),
                )
              : const SizedBox.shrink();
          // A row is as tall as its taller card: a name that wraps grows
          // both, and the other keeps its text at the bottom.
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(child: card(first)),
                  const SizedBox(width: 10),
                  Expanded(child: card(first + 1)),
                ],
              ),
            ),
          );
        },
      );
    }

    final scaffold = AdaptiveScaffold(
      title: l10n.learnCategories,
      leading: AdaptiveBackButton(
        label: l10n.tabLearn,
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
      body: body,
    );
    return tokens.isGlass
        ? AuroraBackdrop(leading: tokens.color.accent, child: scaffold)
        : scaffold;
  }
}

/// One category: its tile, name, words and Done / Learning / To do bar.
class CategoryCard extends StatelessWidget {
  const CategoryCard({
    required this.category,
    required this.colours,
    super.key,
  });

  final CategoryProgress category;
  final (Color, Color) colours;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final (fill, ink) = colours;
    return Semantics(
      button: true,
      child: DpSurface(
        kind: DpSurfaceKind.bar,
        padding: const EdgeInsets.all(14),
        onTap: () => context.jumpToTab(CategoryRoute(id: category.id)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 92),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: tokens.color.ink, width: 1.5),
                  ),
                  child: Icon(Icons.layers_outlined, size: 18, color: ink),
                ),
              ),
              const SizedBox(height: 10),
              const Spacer(),
              DpText(category.name, role: DpTextRole.body, weight: 600),
              const SizedBox(height: 2),
              DpText(
                l10n.categoriesWords(category.words),
                role: DpTextRole.caption,
                color: tokens.color.textSecondary,
              ),
              const SizedBox(height: 10),
              DpSegmentedBar(
                done: category.done,
                learning: category.learning,
                todo: category.todo,
                height: 6,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
