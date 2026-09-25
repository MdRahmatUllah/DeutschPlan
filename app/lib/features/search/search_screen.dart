import 'dart:async';
import 'dart:convert';

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/search_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/features/learn/step_words.dart';
import 'package:deutschplan/features/words/word_row.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/router/cross_tab.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'search_screen.g.dart';

/// One word R1 found: the word with its state and meaning, and its tier.
typedef SearchRow = ({StepWord word, SearchTier tier});

/// What a query shows: its words in the search's order, and its sentences.
@immutable
class SearchView {
  const SearchView({required this.words, required this.sentences});

  final List<SearchRow> words;
  final List<SentenceHit> sentences;

  bool get isEmpty => words.isEmpty && sentences.isEmpty;
}

/// FR-R1-01: [query] through `search.md`'s four tiers, the words joined to
/// the learner's state and meaning language — and again as those change, so
/// a word rated in W1 shows its new chip here. [step] is L2's.
@riverpod
Stream<SearchView> searchResults(Ref ref, String query, {String? step}) async* {
  // Read before the first await: a query typed past disposes this one, and
  // a ref used after that throws.
  final words = ref.watch(wordRepositoryProvider);
  final results = await ref
      .watch(searchRepositoryProvider)
      .search(query, step: step);
  final tiers = <String, SearchTier>{
    for (final hit in results.words) hit.uid: hit.tier,
  };
  if (tiers.isEmpty) {
    yield SearchView(words: const <SearchRow>[], sentences: results.sentences);
    return;
  }
  yield* words
      .watchWords(<String>[...tiers.keys])
      .map(
        (words) => SearchView(
          words: <SearchRow>[
            for (final word in withMeanings(ref, words))
              (word: word, tier: tiers[word.word.uid]!),
          ],
          sentences: results.sentences,
        ),
      );
}

/// FR-R1-04: the last ten searches, newest first, kept in `recent_searches`.
/// A search counts once the learner commits to it: the search key, a result
/// opened, a web chip or a recent chip, not every pause in typing.
@riverpod
class RecentSearches extends _$RecentSearches {
  static const int limit = 10;

  @override
  List<String> build() {
    final settings = ref.watch(settingsProvider);
    // Followed: import and reset write the setting too.
    final changes = settings.changes
        .where((key) => key == SettingKeys.recentSearches)
        .listen((_) => state = _read(settings));
    ref.onDispose(changes.cancel);
    return _read(settings);
  }

  /// [query] first; the same search again moves up rather than repeating.
  Future<void> remember(String query) async {
    final settings = ref.read(settingsProvider);
    final term = query.trim();
    if (term.isEmpty) return;
    final key = term.toLowerCase();
    state = <String>[
      term,
      for (final old in state)
        if (old.toLowerCase() != key) old,
    ].take(limit).toList();
    await settings.write(SettingKeys.recentSearches, jsonEncode(state));
  }

  /// FR-R1-04's *Clear*.
  Future<void> clear() async {
    final settings = ref.read(settingsProvider);
    state = const <String>[];
    await settings.write(SettingKeys.recentSearches, null);
  }

  static List<String> _read(SettingsRepository settings) {
    final raw = settings.read(SettingKeys.recentSearches);
    if (raw == null) return const <String>[];
    try {
      return <String>[
        for (final term in jsonDecode(raw) as List<Object?>)
          if (term is String) term,
      ];
    } on FormatException {
      return const <String>[];
    }
  }
}

/// How many words the course has, for R1's no-results page (#139).
@riverpod
Future<int?> courseWords(Ref ref) =>
    ref.watch(searchRepositoryProvider).courseWords();

/// R1's idle *My words* (#138): the learner's own words, newest first.
@riverpod
Stream<List<MyWord>> myWords(Ref ref) =>
    ref.watch(wordRepositoryProvider).watchMyWords();

/// R1 · Search (`search.md`, Search artboards): the Raspberry header with
/// its field, the web row, and the results grouped as BR-SEARCH-01 orders
/// them. [step] is L2's search icon: the results kept to that step, with a
/// chip that lets it go.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.step});

  final String? step;

  /// FR-R1-01's debounce.
  static const Duration debounce = Duration(milliseconds: 120);

  /// FR-R1-07: past this many words, the step and status chips appear.
  static const int filterFrom = 10;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _field = TextEditingController();
  Timer? _debounce;

  /// The query the results are for: the field, 120 ms after it last moved.
  String _query = '';

  /// L2's step, until its chip is removed.
  String? _step;

  /// FR-R1-07's chips.
  WordStatus? _status;
  String? _chipStep;

  /// The last answer, shown while the next query loads, so the list does
  /// not drop to the web row and lose its scroll between keystrokes.
  SearchView? _last;

  @override
  void initState() {
    super.initState();
    _step = widget.step;
  }

  @override
  void didUpdateWidget(SearchScreen old) {
    super.didUpdateWidget(old);
    // The tab is kept alive, so a second trip from L2 arrives as an update.
    if (widget.step != old.step) setState(() => _step = widget.step);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _changed(String text) {
    _debounce?.cancel();
    _debounce = Timer(SearchScreen.debounce, () {
      if (!mounted) return;
      setState(() {
        _query = text.trim();
        _status = null;
        _chipStep = null;
      });
    });
  }

  void _clear() {
    _debounce?.cancel();
    _field.clear();
    _last = null;
    setState(() {
      _query = '';
      _status = null;
      _chipStep = null;
    });
  }

  /// FR-R1-04: the search the learner committed to, remembered.
  void _use([String? term]) => unawaited(
    ref.read(recentSearchesProvider.notifier).remember(term ?? _query),
  );

  /// A recent chip: its search, at once.
  void _searchFor(String term) {
    _debounce?.cancel();
    _field.value = TextEditingValue(
      text: term,
      selection: TextSelection.collapsed(offset: term.length),
    );
    _last = null;
    setState(() {
      _query = term;
      _status = null;
      _chipStep = null;
    });
    _use(term);
  }

  /// FR-R1-02: the search key opens the first exact match.
  Future<void> _submitted(String text) async {
    final query = text.trim();
    if (query.isEmpty) return;
    _debounce?.cancel();
    _use(query);
    if (query != _query) {
      setState(() {
        _query = query;
        _status = null;
        _chipStep = null;
      });
    }
    final provider = searchResultsProvider(query, step: _step);
    // Held while it answers: the screen may not have rebuilt to watch it yet.
    final held = ref.listenManual(provider, (_, _) {});
    final SearchView view;
    try {
      view = await ref.read(provider.future);
    } finally {
      held.close();
    }
    if (!mounted) return;
    final exact = _shown(view).words
        .where((row) => row.tier == SearchTier.exact);
    if (exact.isNotEmpty) WordRoute.open(context, exact.first.word.word.uid);
  }

  /// [view] with FR-R1-07's chips applied. L2's step is the query's own.
  SearchView _shown(SearchView view) {
    bool keep(String step, WordStatus? status) =>
        (_chipStep == null || step == _chipStep) &&
        (_status == null || status == null || status == _status);
    return SearchView(
      words: <SearchRow>[
        for (final row in view.words)
          if (keep(row.word.word.word.sublevelCode, row.word.word.status)) row,
      ],
      sentences: <SentenceHit>[
        for (final sentence in view.sentences)
          // A sentence has no status of its own; only the step keeps it out.
          if (_status == null && keep(sentence.step, null)) sentence,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final query = _query;
    final results = query.isEmpty
        ? null
        : ref.watch(searchResultsProvider(query, step: _step));
    final view =
        results?.value ?? ((results?.isLoading ?? false) ? _last : null);
    _last = view;

    final scaffold = AdaptiveScaffold(
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Header(
            field: _field,
            step: _step,
            onChanged: _changed,
            onSubmitted: (text) => unawaited(_submitted(text)),
            onClear: _clear,
            // Through the route, so the route and the screen agree: a second
            // trip from the same step then brings the chip back.
            onRemoveStep: () => context.jumpToTab(const SearchRoute()),
          ),
          Expanded(
            child: query.isEmpty
                ? _Idle(onRecent: _searchFor)
                // The course lacks it (#139). Kept to L2's step, an empty
                // result says nothing about the course, so it stays a list.
                : view != null && view.isEmpty && _step == null
                ? _NoResults(query: query, onUse: _use)
                : results != null && results.hasError && view == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: DpErrorPanel(
                        message: l10n.searchFailed,
                        retryLabel: l10n.retry,
                        onRetry: () => ref.invalidate(
                          searchResultsProvider(query, step: _step),
                        ),
                      ),
                    ),
                  )
                : _Results(
                    query: query,
                    view: view,
                    shown: view == null ? null : _shown(view),
                    status: _status,
                    step: _chipStep,
                    onStatus: (status) => setState(
                      () => _status = _status == status ? null : status,
                    ),
                    onStep: (step) => setState(
                      () => _chipStep = _chipStep == step ? null : step,
                    ),
                    onUse: _use,
                  ),
          ),
        ],
      ),
    );
    return tokens.isGlass
        ? AuroraBackdrop(leading: tokens.color.die, child: scaffold)
        : scaffold;
  }
}

/// The Raspberry band under the status bar: the field, and L2's step chip.
class _Header extends StatelessWidget {
  const _Header({
    required this.field,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    required this.onRemoveStep,
    this.step,
  });

  final TextEditingController field;
  final String? step;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final VoidCallback onRemoveStep;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final step = this.step;
    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.paddingOf(context).top + 10,
        16,
        20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // On paper the field is the artboard's: 2 px ink and the hard
          // shadow. Under glass it is frosted like every other panel.
          DpSurface(
            radius: tokens.shape.button,
            selected: !tokens.isGlass,
            child: SizedBox(
              height: 52,
              child: Row(
                children: <Widget>[
                  const SizedBox(width: 14),
                  Icon(Icons.search, size: 24, color: tokens.color.ink),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: field,
                      // FR-R1-05: the tab is kept alive, so this fires on a
                      // fresh open only; coming back keeps query and scroll.
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onChanged: onChanged,
                      onSubmitted: onSubmitted,
                      style: DpText.styleFor(
                        tokens,
                        DpTextRole.bodyLarge,
                        color: tokens.color.ink,
                      ),
                      decoration: InputDecoration.collapsed(
                        hintText: l10n.searchHint,
                        hintStyle: DpText.styleFor(
                          tokens,
                          DpTextRole.bodyLarge,
                          color: tokens.color.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  ListenableBuilder(
                    listenable: field,
                    builder: (context, _) => field.text.isEmpty
                        ? const SizedBox(width: 6)
                        : Semantics(
                            button: true,
                            label: l10n.searchClear,
                            onTap: onClear,
                            excludeSemantics: true,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: onClear,
                              child: SizedBox(
                                width: 48,
                                height: 48,
                                child: Icon(
                                  Icons.close,
                                  size: 22,
                                  color: tokens.color.textSecondary,
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
          if (step != null) ...<Widget>[
            const SizedBox(height: 10),
            DpChip(
              label: step,
              kind: DpChipKind.filter,
              selected: true,
              icon: Icon(Icons.close, size: 14, color: tokens.color.ink),
              semanticLabel: l10n.searchRemoveStep(step),
              onTap: onRemoveStep,
            ),
          ],
        ],
      ),
    );
    return tokens.isGlass
        ? DpSurface(
            kind: DpSurfaceKind.tint(tokens.color.die),
            radius: 0,
            child: content,
          )
        : ColoredBox(color: tokens.color.die, child: content);
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.query,
    required this.view,
    required this.shown,
    required this.status,
    required this.step,
    required this.onStatus,
    required this.onStep,
    required this.onUse,
  });

  final String query;
  final SearchView? view;

  /// [view] with the filters applied.
  final SearchView? shown;
  final WordStatus? status;
  final String? step;
  final ValueChanged<WordStatus> onStatus;
  final ValueChanged<String> onStep;

  /// Called as a result or a web chip is opened (FR-R1-04).
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final view = this.view;
    final shown = this.shown;
    // The steps the results span, in course order (the codes sort so).
    final steps = view == null
        ? const <String>[]
        : (<String>{
            for (final row in view.words) row.word.word.word.sublevelCode,
          }.toList()..sort());

    return ListView(
      key: const PageStorageKey<String>('search-results'),
      padding: EdgeInsets.zero,
      children: <Widget>[
        _WebRow(term: query, onUse: onUse),
        if (view != null &&
            view.words.length > SearchScreen.filterFrom) ...<Widget>[
          _Chips(
            children: <Widget>[
              for (final (value, label) in <(WordStatus, String)>[
                (WordStatus.todo, l10n.wordStatusToDo),
                (WordStatus.learning, l10n.wordStatusLearning),
                (WordStatus.done, l10n.wordStatusDone),
              ])
                DpChip(
                  label: label,
                  kind: DpChipKind.filter,
                  selected: status == value,
                  onTap: () => onStatus(value),
                ),
              // One step (L2's, or a query that only has one) is no filter.
              if (steps.length > 1)
                for (final code in steps)
                  DpChip(
                    label: code,
                    kind: DpChipKind.filter,
                    selected: step == code,
                    onTap: () => onStep(code),
                  ),
            ],
          ),
        ],
        if (shown != null) ...<Widget>[
          for (final (tier, heading) in <(SearchTier, String Function(int))>[
            (SearchTier.exact, l10n.searchExact),
            (SearchTier.startsWith, l10n.searchStartsWith),
            (SearchTier.similar, l10n.searchSimilar),
          ])
            ..._words(context, shown, tier, heading),
          ..._sentences(context, shown),
        ],
      ],
    );
  }

  List<Widget> _sentences(BuildContext context, SearchView view) {
    final sentences = view.sentences;
    if (sentences.isEmpty) return const <Widget>[];
    return <Widget>[
      _Heading(AppLocalizations.of(context).searchSentences(sentences.length)),
      _Framed(
        children: <Widget>[
          for (final (index, sentence) in sentences.indexed)
            _SentenceRow(
              sentence: sentence,
              onUse: onUse,
              last: index == sentences.length - 1,
            ),
        ],
      ),
    ];
  }

  List<Widget> _words(
    BuildContext context,
    SearchView view,
    SearchTier tier,
    String Function(int) heading,
  ) {
    final rows = view.words.where((row) => row.tier == tier).toList();
    if (rows.isEmpty) return const <Widget>[];
    return <Widget>[
      _Heading(heading(rows.length)),
      _Framed(
        children: <Widget>[
          for (final (index, row) in rows.indexed)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                onUse();
                WordRoute.open(context, row.word.word.uid);
              },
              child: WordRow(
                word: row.word.word,
                meaning: row.word.meaning,
                step: row.word.word.word.sublevelCode,
                last: index == rows.length - 1,
              ),
            ),
        ],
      ),
    ];
  }
}

/// A row of chips that scrolls sideways: 12 above, 4 below, 16 at the sides.
class _Chips extends StatelessWidget {
  const _Chips({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Row(
      children: <Widget>[
        for (final (index, chip) in children.indexed) ...<Widget>[
          if (index > 0) const SizedBox(width: 8),
          chip,
        ],
      ],
    ),
  );
}

/// Duden · DWDS · Wiktionary · Linguee · Google for the query (BR-SEARCH-04).
/// The app makes no request: the page opens in an in-app browser tab
/// (FR-R1-06, BR-PRIV-01).
class _WebRow extends ConsumerWidget {
  const _WebRow({required this.term, required this.onUse});

  final VoidCallback onUse;

  final String term;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final links = SearchRepository.webLinks(term);
    return _Chips(
      children: <Widget>[
        for (final source in WebSource.values)
          DpChip(
            label: source.label,
            kind: DpChipKind.webLink,
            semanticLabel: l10n.searchOpenWeb(source.label),
            onTap: () {
              onUse();
              unawaited(ref.read(openWebProvider)(links[source]!));
            },
          ),
      ],
    );
  }
}

/// "EXACT MATCH · 1": 12/16, 700, spaced, 14 above and 6 below.
class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.trailing});

  final String text;

  /// On the right: the idle view's *Clear* and "From receipts…".
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final heading = Semantics(
      // A heading to a screen reader too, so a learner can move group by
      // group.
      header: true,
      child: DpText(
        text.toUpperCase(),
        role: DpTextRole.caption,
        weight: 700,
        letterSpacing: 0.6,
        color: context.tokens.color.textSecondary,
      ),
    );
    final trailing = this.trailing;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 14, trailing == null ? 16 : 4, 6),
      child: trailing == null
          ? heading
          // Both give way: at 200 % text, or in Bangla, neither pushes the
          // other off the row.
          : Row(
              children: <Widget>[
                Expanded(child: heading),
                const SizedBox(width: 8),
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: trailing,
                  ),
                ),
              ],
            ),
    );
  }
}

/// A group's rows between two hairlines; each row draws the one under it
/// but the last.
class _Framed extends StatelessWidget {
  const _Framed({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final line = BorderSide(color: context.tokens.surface.outline);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: line, bottom: line),
      ),
      child: Column(children: children),
    );
  }
}

/// An "In sentences" row: the sentence with the query marked in Sun, its
/// translation, and the word it belongs to with its step. A tap opens that
/// word.
class _SentenceRow extends StatelessWidget {
  const _SentenceRow({
    required this.sentence,
    required this.last,
    required this.onUse,
  });

  final VoidCallback onUse;

  final SentenceHit sentence;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final style = DpText.styleFor(
      tokens,
      DpTextRole.body,
      color: tokens.color.ink,
    ).copyWith(fontStyle: FontStyle.italic);
    final english = sentence.english;
    final head = sentence.article == null
        ? sentence.head
        : '${sentence.article} ${sentence.head}';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        onUse();
        WordRoute.open(context, sentence.wordUid);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: tokens.surface.card,
          border: last
              ? null
              : Border(bottom: BorderSide(color: tokens.surface.outline)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  for (final (text, marked) in sentence.runs)
                    TextSpan(
                      text: text,
                      style: marked
                          ? style.copyWith(
                              backgroundColor: tokens.color.accent,
                              color: tokens.color.onAccent,
                            )
                          : style,
                    ),
                ],
              ),
              locale: const Locale('de', 'DE'),
            ),
            if (english != null) ...<Widget>[
              const SizedBox(height: 2),
              DpText(
                english,
                role: DpTextRole.label,
                weight: 400,
                color: tokens.color.textSecondary,
              ),
            ],
            const SizedBox(height: 2),
            DpText(
              '$head · ${sentence.step}',
              role: DpTextRole.caption,
              color: tokens.color.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// R1 with nothing typed (#138, the SearchIdle artboards): the last
/// searches, the learner's own words, and the way to add one.
class _Idle extends ConsumerWidget {
  const _Idle({required this.onRecent});

  /// A recent chip tapped: search it again.
  final ValueChanged<String> onRecent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final recent = ref.watch(recentSearchesProvider);
    final words = ref.watch(myWordsProvider).value ?? const <MyWord>[];

    return ListView(
      key: const PageStorageKey<String>('search-idle'),
      padding: const EdgeInsets.only(bottom: 16),
      children: <Widget>[
        if (recent.isNotEmpty) ...<Widget>[
          _Heading(
            l10n.searchRecent,
            // The artboard's Clear ends 28 dp from the edge: the text
            // button's own 12 inside the heading's 16.
            trailing: Semantics(
              // Its own node: merged, the heading and the button were read
              // as one, "Recent, Clear recent searches".
              container: true,
              label: l10n.searchClearRecentLabel,
              excludeSemantics: true,
              button: true,
              onTap: () =>
                  unawaited(ref.read(recentSearchesProvider.notifier).clear()),
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: DpButton(
                  label: l10n.searchClearRecent,
                  kind: DpButtonKind.text,
                  expand: false,
                  onPressed: () => unawaited(
                    ref.read(recentSearchesProvider.notifier).clear(),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final term in recent)
                  DpChip(
                    label: term,
                    kind: DpChipKind.filter,
                    onTap: () => onRecent(term),
                  ),
              ],
            ),
          ),
        ],
        if (words.isNotEmpty) ...<Widget>[
          _Heading(
            l10n.searchMyWords(words.length),
            trailing: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: DpText(
                l10n.searchMyWordsFrom,
                role: DpTextRole.caption,
                color: tokens.color.textSecondary,
              ),
            ),
          ),
          _Framed(
            children: <Widget>[
              for (final (index, word) in words.indexed)
                _MyWordRow(word: word, last: index == words.length - 1),
            ],
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: DpButton(
            label: l10n.searchAddWord,
            kind: DpButtonKind.secondary,
            onPressed: () => AddWordRoute.open(context),
          ),
        ),
      ],
    );
  }
}

/// One of the learner's own words: "das Pfandflasche", "deposit bottle ·
/// Rewe receipt · seen 3×", the *My word* chip, and the way to it in R2.
class _MyWordRow extends StatelessWidget {
  const _MyWordRow({required this.word, required this.last});

  final MyWord word;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final where = word.whereSeen?.trim();
    final line = <String>[
      word.meaning,
      if (where != null && where.isNotEmpty) where,
      // Once is every word; the count says something from the second time.
      if (word.timesSeen > 1) l10n.searchSeen(word.timesSeen),
    ].join(' · ');

    return Semantics(
      button: true,
      onTap: () => EditCustomWordRoute.open(context, word.id),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => EditCustomWordRoute.open(context, word.id),
        child: Container(
          constraints: const BoxConstraints(minHeight: WordRow.height),
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          decoration: BoxDecoration(
            color: tokens.surface.card,
            border: last
                ? null
                : Border(bottom: BorderSide(color: tokens.surface.outline)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    DpHeadword(
                      word.german,
                      article: word.article,
                      role: DpTextRole.bodyLarge,
                      weight: 600,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 2),
                    DpText(
                      line,
                      role: DpTextRole.label,
                      weight: 400,
                      maxLines: 1,
                      color: tokens.color.textSecondary,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              DpChip(label: l10n.searchMyWord, kind: DpChipKind.status),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 22,
                color: tokens.color.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// R1 when the course has nothing like the query (#139, the SearchNone
/// artboards): what that means, the web a tap away, and the word kept as the
/// learner's own.
class _NoResults extends ConsumerWidget {
  const _NoResults({required this.query, required this.onUse});

  final String query;

  /// A web chip or the button: the search committed to (FR-R1-04).
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final words = ref.watch(courseWordsProvider).value;
    final links = SearchRepository.webLinks(query);

    return ListView(
      key: const PageStorageKey<String>('search-none'),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      children: <Widget>[
        Center(
          child: ExcludeSemantics(
            child: CustomPaint(
              size: const Size(140, 110),
              painter: _NotFound(
                ink: tokens.color.ink,
                fill: tokens.surface.muted,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Semantics(
          header: true,
          child: DpText(
            l10n.searchNoneTitle,
            role: DpTextRole.title,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 14),
        DpText(
          words == null
              ? l10n.searchNoneBodyNoCount
              : l10n.searchNoneBody(words),
          role: DpTextRole.caption,
          textAlign: TextAlign.center,
          color: tokens.color.textSecondary,
        ),
        const SizedBox(height: 18),
        // FR-R1-06, bigger than the row above a list: here the web is the
        // answer.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final source in WebSource.values)
              DpChip(
                label: source.label,
                kind: DpChipKind.webLink,
                large: true,
                semanticLabel: l10n.searchOpenWeb(source.label),
                onTap: () {
                  onUse();
                  unawaited(ref.read(openWebProvider)(links[source]!));
                },
              ),
          ],
        ),
        const SizedBox(height: 28),
        DpButton(
          label: l10n.searchNoneAdd(query),
          onPressed: () {
            onUse();
            AddWordRoute.open(context, german: query);
          },
        ),
        const SizedBox(height: 14),
        DpText(
          l10n.searchNoneFootnote,
          role: DpTextRole.caption,
          textAlign: TextAlign.center,
          color: tokens.color.textSecondary,
        ),
      ],
    );
  }
}

/// SearchNone's magnifier: an Oat lens, its handle, and two dotted lines for
/// a face that found nothing.
class _NotFound extends CustomPainter {
  const _NotFound({required this.ink, required this.fill});

  final Color ink;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    // The artboard's 140 × 110 viewBox, scaled to [size].
    canvas.scale(size.width / 140, size.height / 110);
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawCircle(const Offset(60, 48), 30, Paint()..color = fill)
      ..drawCircle(const Offset(60, 48), 30, stroke)
      ..drawLine(const Offset(82, 70), const Offset(112, 100), stroke);
    // Dashes 2 long, 8 apart, as `stroke-dasharray="2 6"` with round caps.
    for (final (from, to, y) in <(double, double, double)>[
      (48, 72, 44),
      (52, 68, 56),
    ]) {
      for (var x = from; x < to; x += 8) {
        canvas.drawLine(
          Offset(x, y),
          Offset(x + 2 > to ? to : x + 2, y),
          stroke,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_NotFound old) => old.ink != ink || old.fill != fill;
}
