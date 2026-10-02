import 'dart:async';

import 'package:flutter/services.dart'
    show LengthLimitingTextInputFormatter, TextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/components/sg_button.dart';
import 'package:sogda/core/components/sg_chip.dart';
import 'package:sogda/core/components/sg_feedback.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/aurora_backdrop.dart';
import 'package:sogda/core/theme/sg_focusable.dart';
import 'package:sogda/core/theme/sg_surface.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/theme/system_bars.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/data/repositories/search_repository.dart';
import 'package:sogda/data/repositories/word_repository.dart';
import 'package:sogda/features/search/search_screen.dart'
    show myWordsProvider, sameWord, savedAs;
import 'package:sogda/features/study/write_guard.dart';
import 'package:sogda/features/today/today_providers.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/router/routes.dart';

part 'add_word_screen.g.dart';

/// FR-R2-01's live check: the course word [german] already is, if any, from
/// the search's exact tier.
@riverpod
Future<WordHit?> courseMatch(Ref ref, String german) async {
  final search = ref.watch(searchRepositoryProvider);
  final term = german.trim();
  if (term.isEmpty) return null;
  final results = await search.search(term);
  return results.inTier(SearchTier.exact).firstOrNull;
}

/// R2's edit mode: the word as it was saved, or null once it has gone.
@riverpod
Future<MyWordDraft?> myWord(Ref ref, int id) =>
    ref.watch(wordRepositoryProvider).myWord(id);

/// R2's edit mode: whether the word is already in revision (#363).
@riverpod
Future<bool> myWordInRevision(Ref ref, int id) =>
    ref.watch(wordRepositoryProvider).isMyWordInRevision(id);

/// R2's fields as compared for #1263: trimmed, as *Save* stores them.
typedef _Fields = ({
  String? article,
  String german,
  String meaning,
  String where,
  String example,
});

/// R2 · Add / edit my word (`add-word.md`, the AddWord artboards). [german]
/// comes filled in from R1's no-results page; [id] is edit mode, from R1's
/// *My words*.
class AddWordScreen extends ConsumerStatefulWidget {
  const AddWordScreen({super.key, this.german, this.id});

  final String? german;
  final int? id;

  /// FR-R2-01's debounce.
  static const Duration debounce = Duration(milliseconds: 300);

  /// The articles in the order the artboard draws them; null is *none*.
  static const List<String?> articles = <String?>['der', 'die', 'das', null];

  @override
  ConsumerState<AddWordScreen> createState() => _AddWordState();
}

class _AddWordState extends ConsumerState<AddWordScreen> {
  final TextEditingController _german = TextEditingController();
  final TextEditingController _meaning = TextEditingController();
  final TextEditingController _where = TextEditingController();
  final TextEditingController _example = TextEditingController();
  final FocusNode _germanFocus = FocusNode();
  Timer? _debounce;

  String? _article;

  /// The German the live check is for: the field, a moment after it moved.
  String _checked = '';

  /// One write at a time: a double tap on *Save* saves once.
  bool _busy = false;

  /// What the fields held when R2 opened: the search's German, or the word
  /// being edited once it has loaded. Leaving with anything else asks first
  /// (#1263).
  _Fields? _baseline;

  @override
  void initState() {
    super.initState();
    _german.text = widget.german?.trim() ?? '';
    _checked = _german.text.trim();
    _baseline = _fields;
    _german.addListener(_changed);
    _meaning.addListener(_refresh);
    // Every field, so Back knows at once whether it would lose text (#1263).
    _where.addListener(_refresh);
    _example.addListener(_refresh);
    // The umlaut row shows while the German field is the one typed in.
    _germanFocus.addListener(_refresh);
    if (widget.id case final id?) unawaited(_load(id));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _german.dispose();
    _meaning.dispose();
    _where.dispose();
    _example.dispose();
    _germanFocus.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(AddWordScreen.debounce, () {
      if (mounted) setState(() => _checked = _german.text.trim());
    });
    setState(() {});
  }

  /// Edit mode: the word as it was saved.
  Future<void> _load(int id) async {
    final word = await ref.read(myWordProvider(id).future);
    if (!mounted || word == null) return;
    _german.text = word.german;
    _meaning.text = word.meaning;
    _where.text = word.whereSeen ?? '';
    _example.text = word.example ?? '';
    _debounce?.cancel();
    setState(() {
      _article = word.article;
      _checked = word.german;
      _baseline = _fields;
    });
  }

  _Fields get _fields => (
    article: _article,
    german: _german.text.trim(),
    meaning: _meaning.text.trim(),
    where: _where.text.trim(),
    example: _example.text.trim(),
  );

  /// Typed or changed since R2 opened (#1263).
  bool get _dirty => _fields != _baseline;

  /// #1263: Back with text that isn't saved asks first; *Leave* drops it.
  Future<void> _confirmLeave() async {
    final l10n = AppLocalizations.of(context);
    final leave = await Adaptive.showConfirm(
      context: context,
      title: l10n.addWordDiscardTitle,
      message: l10n.addWordDiscardBody,
      confirmLabel: l10n.addWordDiscard,
      cancelLabel: l10n.addWordDiscardKeep,
      destructive: true,
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  String get _name {
    final german = _german.text.trim();
    return _article == null ? german : '$_article $german';
  }

  bool get _complete =>
      _german.text.trim().isNotEmpty && _meaning.text.trim().isNotEmpty;

  /// FR-R2-03 *Save*: into `custom_words`, and back to R1, where *My words*
  /// shows it first. With [revise], *Save and add to revision*: scheduled
  /// too, due today (#363).
  Future<void> _save(WordHit? match, {bool revise = false}) async {
    if (_busy || !_complete) return;
    final l10n = AppLocalizations.of(context);
    final words = ref.read(wordRepositoryProvider);
    final now = ref.read(clockProvider)();
    final today = ref.read(todayProvider);
    final name = _name;
    // Held now: Back isn't blocked while the save runs, and this page's
    // `ref` is gone once it has been left (#811, `state-management.md`).
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _busy = true);
    try {
      await words.saveMyWord(
        (
          article: _article,
          german: _german.text,
          meaning: _meaning.text,
          whereSeen: _where.text,
          example: _example.text,
        ),
        now: now,
        id: widget.id,
        // The check trails the field by its debounce: a match found for an
        // earlier spelling isn't this word's.
        matchedUid: _checked == _german.text.trim() ? match?.uid : null,
        reviseFrom: revise ? today : null,
      );
      // Today's plan is read once, when the day opens: the row is on Today's
      // Revise block once it is read again.
      if (revise) container.invalidate(todayPlanProvider);
      if (!mounted) return;
      SgToast.show(
        context,
        revise ? l10n.addWordSavedRevise(name) : l10n.addWordSaved(name),
      );
      // Still busy: the page is going, and a tap on its way out must not save
      // the word again.
      Navigator.of(context).pop();
    } on Object catch (error) {
      debugPrint('add word: $error');
      if (!mounted) return;
      SgToast.show(context, l10n.addWordSaveFailed);
      setState(() => _busy = false);
    }
  }

  /// FR-R2-02 *Log it*: one more sighting of the course word, and no word of
  /// the learner's own.
  Future<void> _log(WordHit match) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final words = ref.read(wordRepositoryProvider);
    setState(() => _busy = true);
    try {
      // A write that fails says so, with Retry and Export (#694 CC-3).
      final written = await guardWrite(context, () async {
        await words.logSighting(match.uid);
        return true;
      });
      if (written && mounted) {
        SgToast.show(context, l10n.addWordLogged(_headword(match)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The word of the learner's own the German already is, other than the one
  /// being edited (#669).
  MyWord? _mine(List<MyWord>? words) =>
      savedAs(words, _german.text, article: _article, except: widget.id);

  /// *Log it* on a word of the learner's own (#669): one more real-life
  /// sighting, "seen N×" in R1's *My words*, and no second word.
  Future<void> _logMine(MyWord word) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final words = ref.read(wordRepositoryProvider);
    final name = word.article == null || word.article!.isEmpty
        ? word.german
        : '${word.article} ${word.german}';
    setState(() => _busy = true);
    try {
      final written = await guardWrite(context, () async {
        await words.logMySighting(word.id);
        return true;
      });
      if (written && mounted) SgToast.show(context, l10n.addWordLogged(name));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Edit mode's *Delete*, after asking.
  Future<void> _delete(int id) async {
    final l10n = AppLocalizations.of(context);
    final words = ref.read(wordRepositoryProvider);
    final sure = await Adaptive.showConfirm(
      context: context,
      title: l10n.addWordDeleteTitle(_name),
      message: l10n.addWordDeleteBody,
      confirmLabel: l10n.addWordDelete,
      cancelLabel: l10n.addWordDeleteKeep,
      destructive: true,
    );
    if (sure != true || !mounted) return;
    final written = await guardWrite(context, () async {
      await words.deleteMyWord(id);
      return true;
    });
    if (written && mounted) Navigator.of(context).pop();
  }

  static String _headword(WordHit match) {
    final article = match.word.article;
    return article == null || article.isEmpty
        ? match.word.german
        : '$article ${match.word.german}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final match = _checked.isEmpty
        ? null
        : ref.watch(courseMatchProvider(_checked)).value;
    final id = widget.id;
    // #669: already one of my words (another, in edit mode). Read from the
    // field, not the debounced check: a quick Save must not make it twice.
    final mine = _mine(ref.watch(myWordsProvider).value);
    // #841: only the word itself, key and article, is refused. One only like
    // it (schon for schön, die See for der See) is shown, and Save stays.
    final twice = mine != null && sameWord(mine, _german.text, _article);
    // Until it is known, as if it were: the button appears rather than
    // flashing up and going.
    final inRevision =
        id != null && (ref.watch(myWordInRevisionProvider(id)).value ?? true);

    final scaffold = AdaptiveScaffold(
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
      // The band's Raspberry behind the status bar once the form scrolls it
      // away, as a tab's header keeps (#317, #390).
      statusBarColour: tokens.color.die,
      body: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          const _Header(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _Label(l10n.addWordArticle),
                _ArticlePicker(
                  value: _article,
                  onChanged: (article) => setState(() => _article = article),
                ),
                const SizedBox(height: 14),
                _Label(l10n.addWordGerman),
                _Field(
                  controller: _german,
                  focusNode: _germanFocus,
                  label: l10n.addWordGerman,
                  // German: the keyboard mustn't correct it into English.
                  german: true,
                  // Searched as it is typed (FR-R2-01), so R1's length.
                  maxLength: SearchRepository.maxQueryLength,
                  // On focus, its umlaut row and the next field show above
                  // the keyboard: 14 dp, a label and a 48 dp field (#515).
                  scrollPadding: SgUmlautBar.scrollPadding(
                    context,
                    below: 14 + 22 + 48,
                  ),
                ),
                if (_germanFocus.hasFocus) ...<Widget>[
                  const SizedBox(height: 8),
                  SgUmlautBar(controller: _german),
                ],
                if (mine != null) ...<Widget>[
                  const SizedBox(height: 14),
                  _Match(
                    title: l10n.searchNoneMine,
                    german: mine.german,
                    article: mine.article,
                    busy: _busy,
                    onOpen: () => EditCustomWordRoute.open(context, mine.id),
                    onLog: () => unawaited(_logMine(mine)),
                  ),
                ] else if (match != null) ...<Widget>[
                  const SizedBox(height: 14),
                  _Match(
                    title: l10n.addWordInCourse(match.word.sublevelCode),
                    german: match.word.german,
                    article: match.word.article,
                    plural: match.word.forms,
                    busy: _busy,
                    onOpen: () => WordRoute.open(context, match.uid),
                    onLog: () => unawaited(_log(match)),
                  ),
                ],
                const SizedBox(height: 14),
                _Label(l10n.addWordMeaning),
                _Field(controller: _meaning, label: l10n.addWordMeaning),
                const SizedBox(height: 14),
                _Label(l10n.addWordWhere),
                _Field(controller: _where, label: l10n.addWordWhere),
                const SizedBox(height: 14),
                _Label(l10n.addWordExample),
                _Field(
                  controller: _example,
                  label: l10n.addWordExample,
                  hint: l10n.addWordExampleHint,
                  german: true,
                ),
                const SizedBox(height: 24),
                SgButton(
                  label: l10n.addWordSave,
                  onPressed: _complete && !_busy && !twice
                      ? () => unawaited(_save(match))
                      : null,
                ),
                if (!inRevision) ...<Widget>[
                  const SizedBox(height: 8),
                  SgButton(
                    label: l10n.addWordSaveRevise,
                    kind: SgButtonKind.secondary,
                    onPressed: _complete && !_busy && !twice
                        ? () => unawaited(_save(match, revise: true))
                        : null,
                  ),
                ],
                if (id != null) ...<Widget>[
                  const SizedBox(height: 8),
                  SgButton(
                    label: l10n.addWordDelete,
                    kind: SgButtonKind.text,
                    onPressed: _busy ? null : () => unawaited(_delete(id)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    return PopScope(
      // A save under way leaves as it always did: its own pop follows.
      canPop: _busy || !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmLeave());
      },
      child: tokens.isGlass
          ? AuroraBackdrop(leading: tokens.color.die, child: scaffold)
          : scaffold,
    );
  }
}

/// The Raspberry band: the way back, "My word" and what it is for.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        4,
        MediaQuery.paddingOf(context).top + 4,
        16,
        16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AdaptiveBackButton(
            colour: tokens.color.ink,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 0, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Semantics(
                  header: true,
                  child: SgText(
                    l10n.addWordTitle,
                    role: SgTextRole.headline,
                    color: tokens.color.ink,
                  ),
                ),
                SgText(
                  l10n.addWordIntro,
                  role: SgTextRole.caption,
                  color: tokens.color.ink,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return tokens.isGlass
        ? SgSurface(
            kind: SgSurfaceKind.tint(tokens.color.die),
            radius: 0,
            child: content,
          )
        : SgHeaderFill(color: tokens.color.die, child: content);
  }
}

/// A field's heading: small capitals, as R1's groups are.
class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: ExcludeSemantics(
      // The field carries the same words as its label, so this isn't read
      // twice.
      child: SgText(
        text.toUpperCase(),
        role: SgTextRole.caption,
        weight: 700,
        letterSpacing: 0.6,
        color: context.tokens.color.textSecondary,
      ),
    ),
  );
}

/// One of R2's fields: 48 dp, the ink edge, on the card.
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.focusNode,
    this.hint,
    this.german = false,
    this.scrollPadding = const EdgeInsets.all(20),
    this.maxLength = 200,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;

  /// How far above the keyboard the page scrolls it on focus.
  final EdgeInsets scrollPadding;

  /// What a screen reader hears on it.
  final String label;
  final String? hint;

  /// German text: no autocorrect into the phone's language.
  final bool german;

  /// The most it takes, in characters (#691 EX-13). 200 by default: a
  /// meaning, a place or a sentence, where the course's longest sentence
  /// is 141.
  final int maxLength;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final edge = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: tokens.color.ink, width: 1.5),
    );
    return Semantics(
      label: label,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autocorrect: !german,
        enableSuggestions: !german,
        textInputAction: TextInputAction.next,
        inputFormatters: <TextInputFormatter>[
          LengthLimitingTextInputFormatter(maxLength),
        ],
        // R2's list runs under the status bar (its header bleeds to the
        // top, #421), so a field revealed 20 dp from the list's top sat
        // under it: in Bangla at 200 % with the keyboard up, 3 dp (#590).
        scrollPadding: scrollPadding.copyWith(
          top: scrollPadding.top + MediaQuery.paddingOf(context).top,
        ),
        style: SgText.styleFor(
          tokens,
          SgTextRole.body,
        ).copyWith(fontSize: 16, color: tokens.color.ink),
        decoration: InputDecoration(
          filled: true,
          fillColor: tokens.surface.cardStrong,
          isDense: true,
          constraints: const BoxConstraints(minHeight: 48),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          border: edge,
          enabledBorder: edge,
          focusedBorder: edge.copyWith(
            borderSide: BorderSide(color: tokens.color.ink, width: 2),
          ),
          hintText: hint,
          // Whole, not cut to one line, as R1's is (#565).
          hintMaxLines: 3,
          maintainHintSize: false,
          hintStyle: SgText.styleFor(
            tokens,
            SgTextRole.body,
          ).copyWith(fontSize: 16, color: tokens.color.textSecondary),
        ),
      ),
    );
  }
}

/// der · die · das · none: four equal buttons, the chosen one in its
/// gender's colour with the ink edge.
class _ArticlePicker extends StatelessWidget {
  const _ArticlePicker({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    return Row(
      children: <Widget>[
        for (final (index, article)
            in AddWordScreen.articles.indexed) ...<Widget>[
          if (index > 0) const SizedBox(width: 6),
          Expanded(
            child: _ArticleOption(
              label: article ?? l10n.addWordNoArticle,
              selected: article == value,
              fill: switch (article) {
                'der' => tokens.color.der,
                'die' => tokens.color.die,
                'das' => tokens.color.das,
                _ => tokens.surface.muted,
              },
              ink: article == 'der' ? tokens.color.onDer : tokens.color.ink,
              onTap: () => onChanged(article),
            ),
          ),
        ],
      ],
    );
  }
}

class _ArticleOption extends StatelessWidget {
  const _ArticleOption({
    required this.label,
    required this.selected,
    required this.fill,
    required this.ink,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color fill;
  final Color ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: SgTappable(
        radius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? fill : null,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? tokens.color.ink : tokens.surface.outline,
                width: selected ? 2 : 1.5,
              ),
            ),
            child: SgText(
              label,
              role: SgTextRole.label,
              weight: 700,
              color: selected ? ink : tokens.color.ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// FR-R2-01: the German is a course word already. *Open* it, or *Log it*
/// as one more real-life sighting (FR-R2-02).
class _Match extends StatelessWidget {
  const _Match({
    required this.title,
    required this.german,
    required this.article,
    required this.busy,
    required this.onOpen,
    required this.onLog,
    this.plural,
  });

  /// What it already is: "Already in the course · A1.2 ·", or one of my
  /// words (#669).
  final String title;
  final String german;
  final String? article;
  final String? plural;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onLog;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final name = article == null || article!.isEmpty
        ? german
        : '$article $german';
    final words = <Widget>[
      Icon(Icons.check, size: 20, color: tokens.color.correctText),
      const SizedBox(width: 10),
      Expanded(
        child: Semantics(
          container: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  SgText(
                    // ponytail: allow-literal — ARB text and a space, no number.
                    '$title ',
                    role: SgTextRole.label,
                  ),
                  SgHeadword(
                    german,
                    article: article,
                    plural: plural,
                    role: SgTextRole.label,
                    weight: 600,
                  ),
                ],
              ),
              SgText(
                l10n.addWordLogHint,
                role: SgTextRole.caption,
                color: tokens.color.textSecondary,
              ),
            ],
          ),
        ),
      ),
    ];
    final actions = <Widget>[
      // The link is drawn as a line of text; the target makes it 48 dp to
      // press (#478).
      AdaptiveTapTarget(
        child: Semantics(
          label: l10n.addWordOpenLabel(name),
          button: true,
          onTap: onOpen,
          excludeSemantics: true,
          child: SgButton(
            label: l10n.addWordOpen,
            kind: SgButtonKind.text,
            expand: false,
            onPressed: onOpen,
          ),
        ),
      ),
      const SizedBox(width: 4),
      SgChip(
        label: l10n.addWordLogIt,
        kind: SgChipKind.filter,
        onTap: busy ? null : onLog,
      ),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: tokens.color.easy.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.color.ink, width: 1.5),
      ),
      // #1078: at large text the actions go under the words, as #165's rows
      // do: beside them, Polish's at 200 % left the words a sliver.
      child: SgScript.large(context)
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(children: words),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: actions,
                ),
              ],
            )
          : Row(children: <Widget>[...words, ...actions]),
    );
  }
}
