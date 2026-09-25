import 'dart:async';

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
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

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

  @override
  void initState() {
    super.initState();
    _german.text = widget.german?.trim() ?? '';
    _checked = _german.text.trim();
    _german.addListener(_changed);
    _meaning.addListener(_refresh);
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
    });
  }

  String get _name {
    final german = _german.text.trim();
    return _article == null ? german : '$_article $german';
  }

  bool get _complete =>
      _german.text.trim().isNotEmpty && _meaning.text.trim().isNotEmpty;

  /// FR-R2-03 *Save*: into `custom_words`, and back to R1, where *My words*
  /// shows it first.
  Future<void> _save(WordHit? match) async {
    if (_busy || !_complete) return;
    final l10n = AppLocalizations.of(context);
    final words = ref.read(wordRepositoryProvider);
    final now = ref.read(clockProvider)();
    final name = _name;
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
      );
      if (!mounted) return;
      DpToast.show(context, l10n.addWordSaved(name));
      Navigator.of(context).pop();
    } on Object catch (error) {
      debugPrint('add word: $error');
      if (mounted) DpToast.show(context, l10n.addWordSaveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
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
      await words.logSighting(match.uid);
      if (mounted) {
        DpToast.show(context, l10n.addWordLogged(_headword(match)));
      }
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
    await words.deleteMyWord(id);
    if (mounted) Navigator.of(context).pop();
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

    final scaffold = AdaptiveScaffold(
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
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
                ),
                if (_germanFocus.hasFocus) ...<Widget>[
                  const SizedBox(height: 8),
                  DpUmlautBar(controller: _german),
                ],
                if (match != null) ...<Widget>[
                  const SizedBox(height: 14),
                  _Match(
                    match: match,
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
                DpButton(
                  label: l10n.addWordSave,
                  onPressed: _complete && !_busy
                      ? () => unawaited(_save(match))
                      : null,
                ),
                // ponytail: *Save and add to revision* (FR-R2-03's second
                // half) waits for custom words to be revisable: the plan, T2
                // and the quizzes serve course words only (#363).
                if (id != null) ...<Widget>[
                  const SizedBox(height: 8),
                  DpButton(
                    label: l10n.addWordDelete,
                    kind: DpButtonKind.text,
                    onPressed: _busy ? null : () => unawaited(_delete(id)),
                  ),
                ],
              ],
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
                  child: DpText(
                    l10n.addWordTitle,
                    role: DpTextRole.headline,
                    color: tokens.color.ink,
                  ),
                ),
                DpText(
                  l10n.addWordIntro,
                  role: DpTextRole.caption,
                  color: tokens.color.ink,
                ),
              ],
            ),
          ),
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
      child: DpText(
        text.toUpperCase(),
        role: DpTextRole.caption,
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
  });

  final TextEditingController controller;
  final FocusNode? focusNode;

  /// What a screen reader hears on it.
  final String label;
  final String? hint;

  /// German text: no autocorrect into the phone's language.
  final bool german;

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
        style: DpText.styleFor(
          tokens,
          DpTextRole.body,
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
          hintStyle: DpText.styleFor(
            tokens,
            DpTextRole.body,
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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
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
            child: DpText(
              label,
              role: DpTextRole.label,
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
    required this.match,
    required this.busy,
    required this.onOpen,
    required this.onLog,
  });

  final WordHit match;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onLog;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final word = match.word;
    final name = word.article == null || word.article!.isEmpty
        ? word.german
        : '${word.article} ${word.german}';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: tokens.color.easy.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.color.ink, width: 1.5),
      ),
      child: Row(
        children: <Widget>[
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
                      DpText(
                        '${l10n.addWordInCourse(word.sublevelCode)} ',
                        role: DpTextRole.label,
                      ),
                      DpHeadword(
                        word.german,
                        article: word.article,
                        role: DpTextRole.label,
                        weight: 600,
                      ),
                    ],
                  ),
                  DpText(
                    l10n.addWordLogHint,
                    role: DpTextRole.caption,
                    color: tokens.color.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          Semantics(
            container: true,
            label: l10n.addWordOpenLabel(name),
            button: true,
            onTap: onOpen,
            excludeSemantics: true,
            child: DpButton(
              label: l10n.addWordOpen,
              kind: DpButtonKind.text,
              expand: false,
              onPressed: onOpen,
            ),
          ),
          const SizedBox(width: 4),
          DpChip(
            label: l10n.addWordLogIt,
            kind: DpChipKind.filter,
            onTap: busy ? null : onLog,
          ),
        ],
      ),
    );
  }
}
