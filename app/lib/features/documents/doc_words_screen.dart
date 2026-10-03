import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show GestureRecognizer, TapGestureRecognizer;
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/components/sg_button.dart';
import 'package:sogda/core/components/sg_feedback.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/aurora_backdrop.dart';
import 'package:sogda/core/theme/sg_surface.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/app_fonts.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/domain/documents/matcher.dart';
import 'package:sogda/features/search/search_header.dart';
import 'package:sogda/features/study/study_back.dart' show MeaningLines;
import 'package:sogda/features/today/today_providers.dart';
import 'package:sogda/features/words/word_detail_screen.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/router/routes.dart';

part 'doc_words_screen.g.dart';

/// D2's data: the document, the matcher's run over it (#1230 part 1), what
/// the learner has added from it, and today's room for document words.
class DocWordsView {
  const DocWordsView({
    required this.document,
    required this.match,
    required this.added,
    required this.slotsLeft,
  });

  final Document document;
  final DocumentMatch match;
  final Set<String> added;

  /// BR-PLAN-11: how many more words today takes (`docSlotsLeft`).
  final int slotsLeft;
}

/// FR-D2-07: every opening runs the matcher again on the saved text, so the
/// marks follow what has been learnt since. Null for a document that's gone.
@riverpod
Future<DocWordsView?> docWords(Ref ref, int id) async {
  final documents = ref.watch(documentRepositoryProvider);
  final engine = ref.watch(planEngineProvider);
  final today = ref.watch(todayProvider);
  final match = await documents.match(id);
  final document = await documents.document(id);
  if (match == null || document == null) return null;
  return DocWordsView(
    document: document,
    match: match,
    added: await documents.added(id),
    slotsLeft: await engine.docSlotsLeft(today),
  );
}

/// *Show words I probably know* (`doc_show_probably_known`), redrawn when it
/// changes, here or in M3.
@riverpod
class ShowProbablyKnown extends _$ShowProbablyKnown {
  @override
  bool build() {
    final settings = ref.watch(settingsSourceProvider);
    bool read() => settings.read(SettingKeys.docShowProbablyKnown);
    final changes = settings.changes
        .where((key) => key == SettingKeys.docShowProbablyKnown)
        .listen((_) => state = read());
    ref.onDispose(changes.cancel);
    return read();
  }

  Future<void> set(bool on) => ref
      .read(settingsSourceProvider)
      .write(SettingKeys.docShowProbablyKnown, on);
}

const List<String> _levels = <String>['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

/// The CEFR colours of L1's steps (`docs/design/cefr-marks.json`).
Color levelColour(SgTokens tokens, String? level) => switch (level) {
  'A1' => tokens.color.primary,
  'A2' => tokens.color.accent,
  'B1' => tokens.color.die,
  'B2' => tokens.color.der,
  'C1' => tokens.color.easy,
  _ => tokens.color.hard,
};

/// D2 · The words in your text (`docs/04-screens/planned/doc-words.md`).
class DocWordsScreen extends ConsumerStatefulWidget {
  const DocWordsScreen({required this.id, super.key});

  final int id;

  @override
  ConsumerState<DocWordsScreen> createState() => _DocWordsScreenState();
}

class _DocWordsScreenState extends ConsumerState<DocWordsScreen> {
  /// Added or ignored in this visit, on top of what was added before.
  final Set<String> _added = <String>{};
  final Set<String> _ignored = <String>{};

  /// One recognizer per word, kept across builds and let go of at the end.
  final Map<String, TapGestureRecognizer> _taps =
      <String, TapGestureRecognizer>{};

  bool _busy = false;

  /// This visit's adds that start today: they took today's slots, which
  /// This visit's adds that start today, and the view they were counted
  /// against: they took today's slots, which that view's slotsLeft read
  /// before them. A view read again (back from R2, a Retry, a new day)
  /// counts them itself (agent-3, #1294).
  int _startedToday = 0;
  DocWordsView? _countedOn;

  @override
  void dispose() {
    for (final tap in _taps.values) {
      tap.dispose();
    }
    super.dispose();
  }

  bool _isAdded(DocWordsView view, DocWord word) =>
      _added.contains(word.key) || view.added.contains(word.key);

  /// The new course words still to add: one reading each (an ambiguous one
  /// asks first, on its card).
  List<DocWord> _fresh(DocWordsView view) => <DocWord>[
    for (final word in view.match.words)
      if (word.docClass == DocClass.newInCourse &&
          !word.ambiguous &&
          !_isAdded(view, word) &&
          !_ignored.contains(word.key))
        word,
  ];

  /// The word's first sentence, trimmed, and where the word starts in it.
  (String, int) _sentenceOf(DocWordsView view, DocWord word) {
    final sentence = view.match.sentences[word.sentences.first];
    final raw = view.document.body.substring(sentence.start, sentence.end);
    final lead = raw.length - raw.trimLeft().length;
    return (raw.trim(), word.spans.first.$1 - sentence.start - lead);
  }

  /// FR-D2-02/03: the words join the document queue (BR-PLAN-11) with their
  /// sentences (BR-DOC-04), and the toast says when they start.
  Future<void> _add(DocWordsView view, List<DocWord> words) async {
    if (_busy || words.isEmpty) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final today = ref.read(todayProvider);
    final documents = ref.read(documentRepositoryProvider);
    try {
      final starts = await ref
          .read(planEngineProvider)
          .addDocWords(
            <String>[for (final word in words) word.entries.single.uid],
            today,
            at: ref.read(clockProvider)().toUtc().toIso8601String(),
          );
      for (final word in words) {
        await documents.recordAdd(
          documentId: widget.id,
          lemmaKey: word.key,
          wordKey: word.entries.single.uid,
          sentence: _sentenceOf(view, word).$1,
        );
      }
      // Today shows the words it took at once (agent-3, #1280).
      ref.invalidate(todayPlanProvider);
      if (!mounted) return;
      final days = <String?>[
        for (final word in words) starts[word.entries.single.uid],
      ];
      setState(() {
        _added.addAll(words.map((w) => w.key));
        if (!identical(_countedOn, view)) {
          _countedOn = view;
          _startedToday = 0;
        }
        _startedToday += days.where((d) => d == today).length;
      });
      final message = words.length == 1
          ? switch (days.single) {
              final day? when day == today => l10n.docWordsAddedToday(
                words.single.surface,
              ),
              final day? => l10n.docWordsAddedFrom(
                words.single.surface,
                DateFormat.EEEE(locale).format(DateTime.parse(day)),
              ),
              null => l10n.docWordsAddedWaiting(words.single.surface),
            }
          // #1311: what happened, all today, some, none, or no day at all.
          : switch (days.where((d) => d == today).length) {
              final n when n == words.length => l10n.docWordsAddedManyToday(n),
              0 when days.every((d) => d == null) =>
                l10n.docWordsAddedManyWaiting(words.length),
              0 => l10n.docWordsAddedManyLater(words.length),
              final n => l10n.docWordsAddedMany(words.length, n),
            };
      SgToast.show(context, message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// FR-D2-04: W1's *Mark known*, with its Undo.
  Future<void> _markKnown(DocWord word, String uid) async {
    final l10n = AppLocalizations.of(context);
    final undo = await ref
        .read(wordActionsProvider)
        .markKnown(uid, today: ref.read(todayProvider));
    if (!mounted) return;
    setState(() => _ignored.add(word.key));
    unawaited(
      SgUndo.show(
        context,
        message: l10n.wordMarkedKnown(word.surface),
        onUndo: () {
          unawaited(undo());
          if (mounted) setState(() => _ignored.remove(word.key));
        },
      ),
    );
  }

  Future<void> _openCard(DocWordsView view, DocWord word) =>
      Adaptive.showSheet<void>(
        context: context,
        builder: (sheet) => _WordCard(
          word: word,
          sentence: _sentenceOf(view, word),
          added: _isAdded(view, word),
          onAdd: (chosen) {
            Navigator.of(sheet).pop();
            unawaited(_add(view, <DocWord>[chosen]));
          },
          onKnow: (uid) {
            Navigator.of(sheet).pop();
            unawaited(_markKnown(word, uid));
          },
          onIgnore: () {
            Navigator.of(sheet).pop();
            setState(() => _ignored.add(word.key));
          },
          onOpen: (uid) {
            Navigator.of(sheet).pop();
            WordRoute.open(context, uid);
          },
          onAddMine: () async {
            Navigator.of(sheet).pop();
            await AddWordRoute.openAndWait(context, german: word.surface);
            // Saved there, it is mine here: its chip and Keep this sentence.
            if (mounted) ref.invalidate(docWordsProvider(widget.id));
          },
          onKeepSentence: () {
            Navigator.of(sheet).pop();
            unawaited(_keepSentence(view, word));
          },
        ),
      );

  /// FR-D2-06: a word already mine gets this sentence, and no second word.
  Future<void> _keepSentence(DocWordsView view, DocWord word) async {
    final l10n = AppLocalizations.of(context);
    await ref
        .read(documentRepositoryProvider)
        .recordAdd(
          documentId: widget.id,
          lemmaKey: word.key,
          wordKey: 'custom:${word.customId}',
          sentence: _sentenceOf(view, word).$1,
        );
    if (!mounted) return;
    setState(() => _added.add(word.key));
    SgToast.show(context, l10n.docWordsSentenceKept(word.surface));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(docWordsProvider(widget.id));
    final showProbable = ref.watch(showProbablyKnownProvider);
    final Widget body;
    Widget? bar;
    switch (view) {
      case AsyncData(value: final view?):
        final words = view.match.words;
        int count(DocClass c) => words.where((w) => w.docClass == c).length;
        final fresh = _fresh(view);
        body = _Text(
          view: view,
          showProbable: showProbable,
          isAdded: (w) => _isAdded(view, w),
          ignored: _ignored,
          tapOf: (word) =>
              _taps.putIfAbsent(word.key, () => TapGestureRecognizer())
                ..onTap = () => unawaited(_openCard(view, word)),
          onLongPress: (word) {
            if (word.docClass != DocClass.newInCourse ||
                word.ambiguous ||
                _isAdded(view, word)) {
              return;
            }
            unawaited(HapticFeedback.mediumImpact());
            unawaited(_add(view, <DocWord>[word]));
          },
          header: SearchHeader(
            title: view.document.title,
            intro: l10n.docWordsSummary(
              count(DocClass.newInCourse),
              count(DocClass.probablyKnown),
              count(DocClass.outside),
            ),
          ),
          controls: _Controls(
            showProbable: showProbable,
            levels: <String>{
              for (final w in words)
                if (w.docClass == DocClass.newInCourse) ?w.level,
            },
            empty:
                fresh.isEmpty &&
                !words.any((w) => w.docClass == DocClass.outside),
          ),
        );
        if (fresh.isNotEmpty) {
          bar = _BulkBar(
            level: view.match.level,
            fresh: fresh,
            slotsLeft: math.max(
              0,
              view.slotsLeft -
                  (identical(view, _countedOn) ? _startedToday : 0),
            ),
            cap: ref
                .watch(settingsSourceProvider)
                .read(SettingKeys.docDailyCap),
            busy: _busy,
            onAdd: (words) => unawaited(_add(view, words)),
          );
        }
      case AsyncData():
        body = Center(child: SgText(l10n.docWordsGone, role: SgTextRole.body));
      case AsyncError():
        body = SgErrorPanel(
          message: l10n.docWordsFailed,
          retryLabel: l10n.retry,
          onRetry: () => ref.invalidate(docWordsProvider(widget.id)),
        );
      default:
        body = Center(
          child: SgText(l10n.docImportFinding, role: SgTextRole.body),
        );
    }
    final scaffold = AdaptiveScaffold(
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
      statusBarColour: tokens.color.die,
      bottomBar: bar,
      body: body,
    );
    return tokens.isGlass
        ? AuroraBackdrop(leading: tokens.color.die, child: scaffold)
        : scaffold;
  }
}

/// The switch, the legend, and the empty state's line.
class _Controls extends ConsumerWidget {
  const _Controls({
    required this.showProbable,
    required this.levels,
    required this.empty,
  });

  final bool showProbable;
  final Set<String> levels;
  final bool empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final caption = SgText.styleFor(
      tokens,
      SgTextRole.caption,
    ).copyWith(color: tokens.color.ink, fontWeight: FontWeight.w700);
    // The legend draws each mark as the text does.
    Widget chip(String label, {Color? fill, bool dotted = false}) => Container(
      // The dotted one has no border, so no inset: it lines up with the text.
      padding: dotted
          ? const EdgeInsets.symmetric(vertical: 4)
          : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(8),
        border: dotted ? null : Border.all(color: tokens.color.ink),
      ),
      child: SgRuns(<TextSpan>[
        TextSpan(
          text: label,
          style: dotted
              ? caption.copyWith(
                  decoration: TextDecoration.underline,
                  decorationStyle: TextDecorationStyle.dotted,
                  decorationColor: tokens.color.ink,
                )
              : caption,
        ),
      ]),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (empty) ...<Widget>[
            SgText(l10n.docWordsEmpty, role: SgTextRole.title),
            const SizedBox(height: 8),
          ],
          // #1309: one node, «Show words I probably know, switch»: the
          // switch says the title, as M3's rows do, and the legend below
          // reads as the list item's text, apart from it.
          MergeSemantics(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: ExcludeSemantics(
                    child: SgText(
                      l10n.docWordsShowProbablyKnown,
                      role: SgTextRole.body,
                    ),
                  ),
                ),
                AdaptiveSwitch(
                  value: showProbable,
                  semanticLabel: l10n.docWordsShowProbablyKnown,
                  onChanged: (on) => unawaited(
                    ref.read(showProbablyKnownProvider.notifier).set(on),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final level in _levels)
                if (levels.contains(level))
                  chip(
                    l10n.docWordsLegendNew(level),
                    fill: levelColour(tokens, level).withValues(alpha: 0.3),
                  ),
              chip(l10n.docWordsLegendMine),
              chip(l10n.docWordsLegendOutside, dotted: true),
            ],
          ),
        ],
      ),
    );
  }
}

/// The text, a paragraph per item so a 20,000-character one never builds at
/// once (doc-words.md, *Developer notes*), each marked word its own
/// semantics node.
class _Text extends StatelessWidget {
  const _Text({
    required this.view,
    required this.showProbable,
    required this.isAdded,
    required this.ignored,
    required this.tapOf,
    required this.onLongPress,
    required this.header,
    required this.controls,
  });

  final DocWordsView view;
  final bool showProbable;
  final bool Function(DocWord) isAdded;
  final Set<String> ignored;
  final TapGestureRecognizer Function(DocWord) tapOf;
  final ValueChanged<DocWord> onLongPress;
  final Widget header;
  final Widget controls;

  @override
  Widget build(BuildContext context) {
    final body = view.document.body;
    final paragraphs = <(int, int)>[];
    var start = 0;
    for (final gap in RegExp(r'\n[ \t]*\n').allMatches(body)) {
      paragraphs.add((start, gap.start));
      start = gap.end;
    }
    paragraphs.add((start, body.length));
    // Every place a word stands, by its start.
    final marks = <(int, int, DocWord)>[
      for (final word in view.match.words)
        for (final (s, e) in word.spans) (s, e, word),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: paragraphs.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) return header;
        if (i == 1) return controls;
        final (from, to) = paragraphs[i - 2];
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: _Paragraph(
            text: body,
            from: from,
            to: to,
            marks: <(int, int, DocWord)>[
              for (final mark in marks)
                if (mark.$1 >= from && mark.$2 <= to) mark,
            ],
            showProbable: showProbable,
            isAdded: isAdded,
            ignored: ignored,
            tapOf: tapOf,
            onLongPress: onLongPress,
          ),
        );
      },
    );
  }
}

class _Paragraph extends StatelessWidget {
  const _Paragraph({
    required this.text,
    required this.from,
    required this.to,
    required this.marks,
    required this.showProbable,
    required this.isAdded,
    required this.ignored,
    required this.tapOf,
    required this.onLongPress,
  });

  final String text;
  final int from;
  final int to;
  final List<(int, int, DocWord)> marks;
  final bool showProbable;
  final bool Function(DocWord) isAdded;
  final Set<String> ignored;
  final TapGestureRecognizer Function(DocWord) tapOf;
  final ValueChanged<DocWord> onLongPress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => _rich(context, constraints.maxWidth),
    );
  }

  Widget _rich(BuildContext context, double width) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final base = SgText.styleFor(tokens, SgTextRole.bodyLarge);
    final scaler = MediaQuery.textScalerOf(context);
    // A word wider than the line breaks at its syllables, not at any letter
    // (#165): only such a word, so 100 % stays as drawn.
    String fit(String s) => SgScript.scaled(context)
        ? SgScript.breakTooWide(s, style: base, width: width, scaler: scaler)
        : s;
    TextSpan plain(String s) {
      final shown = fit(s);
      return TextSpan(text: shown, semanticsLabel: shown == s ? null : s);
    }

    // Each word's tap, for the long press to find the word under it.
    final byTap = <GestureRecognizer, DocWord>{};
    final spans = <InlineSpan>[];
    var at = from;
    for (final (start, end, word) in marks) {
      if (start < at) continue;
      spans.add(plain(text.substring(at, start)));
      final surface = text.substring(start, end);
      final shown = switch (word.docClass) {
        _ when ignored.contains(word.key) => false,
        DocClass.newInCourse || DocClass.outside || DocClass.mine => true,
        DocClass.probablyKnown => showProbable,
        DocClass.known => word.mine,
      };
      if (!shown) {
        spans.add(plain(surface));
        at = end;
        continue;
      }
      final added = isAdded(word);
      final style = switch (word.docClass) {
        DocClass.newInCourse => TextStyle(
          backgroundColor: levelColour(
            tokens,
            word.level,
          ).withValues(alpha: 0.3),
          decoration: TextDecoration.underline,
          decorationColor: tokens.color.ink,
          decorationThickness: 2,
        ),
        DocClass.probablyKnown => TextStyle(
          color: tokens.color.textSecondary,
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.dashed,
          decorationColor: tokens.color.textSecondary,
        ),
        DocClass.outside => TextStyle(
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.dotted,
          decorationColor: tokens.color.ink,
        ),
        // A word of my own: plain, its chip says what it is (the artboard).
        DocClass.mine || DocClass.known => const TextStyle(),
      };
      if (word.mine) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ExcludeSemantics(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: tokens.color.ink),
                  ),
                  child: SgText(
                    l10n.docWordsLegendMine,
                    role: SgTextRole.caption,
                    weight: 700,
                  ),
                ),
              ),
            ),
          ),
        );
      }
      final tap = tapOf(word);
      byTap[tap] = word;
      spans.add(
        TextSpan(
          // A word joiner each side: the chip before and the check after
          // stay on the word's line (agent-3, #1294).
          text:
              '${word.mine ? '\u2060' : ''}${fit(surface)}'
              '${added ? '\u2060' : ''}',
          style: style,
          recognizer: tap,
          semanticsLabel: _label(l10n, word, surface, added),
        ),
      );
      if (added) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: ExcludeSemantics(
              child: Icon(Icons.check, size: 16, color: tokens.color.ink),
            ),
          ),
        );
      }
      at = end;
    }
    spans.add(plain(text.substring(at, to)));
    return GestureDetector(
      // A long press on a new word adds it at once (doc-words.md): a sighted
      // shortcut, so a screen reader hears the words' own taps only.
      excludeFromSemantics: true,
      onLongPressStart: (details) {
        final word = _wordAt(context, details.localPosition, byTap);
        if (word != null) onLongPress(word);
      },
      // The words' taps and labels sit beside WidgetSpans (the My-word
      // chip, the check), which SgRuns' TextSpans can't carry; too-wide
      // words break by breakTooWide above. ponytail: allow-raw-text
      child: RichText(
        textScaler: scaler,
        text: TextSpan(
          style: base.copyWith(color: tokens.color.ink),
          children: spans,
        ),
      ),
    );
  }

  /// The marked word under [position], if any: by the span there, since
  /// the text as laid out may hold soft hyphens the document doesn't.
  DocWord? _wordAt(
    BuildContext context,
    Offset position,
    Map<GestureRecognizer, DocWord> byTap,
  ) {
    final render = context.findRenderObject();
    if (render is! RenderBox) return null;
    final paragraph = _paragraphOf(render);
    if (paragraph == null) return null;
    final span = paragraph.text.getSpanForPosition(
      paragraph.getPositionForOffset(position),
    );
    return span is TextSpan ? byTap[span.recognizer] : null;
  }

  static RenderParagraph? _paragraphOf(RenderObject render) {
    if (render is RenderParagraph) return render;
    RenderParagraph? found;
    render.visitChildren((child) => found ??= _paragraphOf(child));
    return found;
  }

  static String _label(
    AppLocalizations l10n,
    DocWord word,
    String surface,
    bool added,
  ) => switch (word.docClass) {
    _ when added => l10n.docWordsSemAdded(surface),
    DocClass.newInCourse => l10n.docWordsSemNew(surface, word.level ?? ''),
    DocClass.probablyKnown => l10n.docWordsSemProbable(surface),
    DocClass.outside => l10n.docWordsSemOutside(surface),
    DocClass.mine || DocClass.known => l10n.docWordsSemMine(surface),
  };
}

/// The bulk bar (FR-D2-03), pinned at the foot.
class _BulkBar extends StatelessWidget {
  const _BulkBar({
    required this.level,
    required this.fresh,
    required this.slotsLeft,
    required this.cap,
    required this.busy,
    required this.onAdd,
  });

  final String? level;
  final List<DocWord> fresh;
  final int slotsLeft;
  final int cap;
  final bool busy;
  final ValueChanged<List<DocWord>> onAdd;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final at = _levels.indexOf(level ?? '');
    final next = at >= 0 && at + 1 < _levels.length ? _levels[at + 1] : null;
    final mine = <DocWord>[
      for (final w in fresh)
        if (at >= 0 && w.level == level) w,
    ];
    final mineAndNext = <DocWord>[
      for (final w in fresh)
        if (at >= 0 && (w.level == level || w.level == next)) w,
    ];
    final later = fresh.length - slotsLeft;
    final pair = <(String, List<DocWord>)>[
      if (mine.isNotEmpty && level != null)
        (l10n.docWordsAddLevel(level!, mine.length), mine),
      if (mine.isNotEmpty &&
          level != null &&
          next != null &&
          mineAndNext.length > mine.length)
        (l10n.docWordsAddLevels(level!, next, mineAndNext.length), mineAndNext),
    ]..removeWhere((p) => p.$2.length == fresh.length);
    return SgSurface(
      kind: SgSurfaceKind.bar,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (pair.isNotEmpty) ...<Widget>[
              LayoutBuilder(
                builder: (context, constraints) {
                  // Side by side as drawn while both labels fit half a row
                  // on one line; stacked when one doesn't (a long label,
                  // Polish or Russian, large text), rather than two buttons
                  // of two heights.
                  final half = (constraints.maxWidth - 8) / 2 - 2 * 18 - 4;
                  final stacked =
                      pair.length == 2 &&
                      pair.any((p) => _labelWidth(context, p.$1) > half);
                  final buttons = <Widget>[
                    for (final (label, words) in pair)
                      SgButton(
                        label: label,
                        kind: SgButtonKind.secondary,
                        compact: true,
                        onPressed: busy ? null : () => onAdd(words),
                      ),
                  ];
                  if (stacked || buttons.length == 1) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        for (final (i, button) in buttons.indexed) ...<Widget>[
                          if (i > 0) const SizedBox(height: 8),
                          button,
                        ],
                      ],
                    );
                  }
                  return Row(
                    children: <Widget>[
                      Expanded(child: buttons[0]),
                      const SizedBox(width: 8),
                      Expanded(child: buttons[1]),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
            SgButton(
              label: l10n.docWordsAddAll(fresh.length),
              onPressed: busy ? null : () => onAdd(fresh),
            ),
            if (later > 0) ...<Widget>[
              const SizedBox(height: 6),
              SgText(
                l10n.docWordsCapNote(cap, later),
                role: SgTextRole.caption,
                color: tokens.color.textSecondary,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// [label]'s width on one line, as a compact [SgButton] draws it: body at
/// 600, Bangla a role up (as `SgRatingBar` measures its labels).
double _labelWidth(BuildContext context, String label) {
  final tokens = context.tokens;
  TextStyle semi(TextStyle style) =>
      DefaultTextStyle.of(context).style
          .merge(style.copyWith(fontVariations: AppFonts.weight(600)));
  final painter = TextPainter(
    text: TextSpan(
      children: SgScript.spans(
        label,
        latin: semi(SgText.styleFor(tokens, SgTextRole.body)),
        bengali: semi(SgText.banglaStyleFor(tokens, SgTextRole.body)),
      ),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// The mini card (doc-words.md): a course word's headword, forms, level,
/// meanings and sentence, or a word outside the course with its compound
/// hint. An ambiguous word asks which first.
class _WordCard extends ConsumerStatefulWidget {
  const _WordCard({
    required this.word,
    required this.sentence,
    required this.added,
    required this.onAdd,
    required this.onKnow,
    required this.onIgnore,
    required this.onOpen,
    required this.onAddMine,
    required this.onKeepSentence,
  });

  final DocWord word;
  final (String, int) sentence;
  final bool added;
  final ValueChanged<DocWord> onAdd;
  final ValueChanged<String> onKnow;
  final VoidCallback onIgnore;
  final ValueChanged<String> onOpen;
  final VoidCallback onAddMine;

  /// FR-D2-06: the sentence kept with a word of my own.
  final VoidCallback onKeepSentence;

  @override
  ConsumerState<_WordCard> createState() => _WordCardState();
}

class _WordCardState extends ConsumerState<_WordCard> {
  /// The reading chosen, for an ambiguous word.
  String? _uid;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final word = widget.word;
    final uid = word.ambiguous ? _uid : word.entries.firstOrNull?.uid;
    final children = <Widget>[];
    if (word.entries.isEmpty) {
      children.addAll(<Widget>[
        SgText(word.surface, role: SgTextRole.headline),
        const SizedBox(height: 4),
        SgText(
          word.docClass == DocClass.mine
              ? l10n.docWordsCardMine
              : l10n.docWordsCardOutside,
          role: SgTextRole.body,
          color: tokens.color.textSecondary,
        ),
        if (word.compound case final parts?) ...<Widget>[
          const SizedBox(height: 4),
          SgText(
            l10n.docWordsCardCompound(parts.join(' + ')),
            role: SgTextRole.body,
          ),
        ],
      ]);
    } else if (uid == null) {
      children.addAll(<Widget>[
        SgText(l10n.docWordsCardWhich, role: SgTextRole.title),
        const SizedBox(height: 8),
        for (final entry in word.entries) ...<Widget>[
          SgButton(
            // «ausfallen · A2.2 · to be cancelled»: two readings can share
            // a spelling and an article (agent-3, #1294).
            label: <String>[
              <String>[?entry.article, entry.german].join(' '),
              if (ref.watch(wordDetailProvider(entry.uid)).value
                  case final detail?) ...<String>[
                detail.word.word.sublevelCode,
                ?detail.meanings.lines(detail.word.word).firstOrNull?.text,
              ],
            ].join(' · '),
            kind: SgButtonKind.secondary,
            compact: true,
            onPressed: () => setState(() => _uid = entry.uid),
          ),
          const SizedBox(height: 6),
        ],
      ]);
    } else {
      final detail = ref.watch(wordDetailProvider(uid)).value;
      final entry = word.entries.firstWhere((e) => e.uid == uid);
      children.addAll(<Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: SgRuns(
                <TextSpan>[
                  // The article in its gender's colour, as W1 draws it.
                  if (entry.article case final article?)
                    TextSpan(
                      text: '$article ',
                      style: TextStyle(
                        color: switch (article) {
                          'der' => tokens.color.der,
                          'die' => tokens.color.die,
                          _ => tokens.color.das,
                        },
                      ),
                    ),
                  TextSpan(text: entry.german),
                ],
                style: SgText.styleFor(
                  tokens,
                  SgTextRole.headline,
                ).copyWith(color: tokens.color.ink),
              ),
            ),
            if (detail != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: levelColour(tokens, detail.word.word.levelCode),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SgText(
                  detail.word.word.sublevelCode,
                  role: SgTextRole.label,
                  weight: 700,
                  color: tokens.color.ink,
                ),
              ),
          ],
        ),
        if (entry.forms case final forms? when forms.isNotEmpty)
          SgText(
            forms,
            role: SgTextRole.body,
            color: tokens.color.textSecondary,
          ),
        if (detail != null) ...<Widget>[
          const SizedBox(height: 4),
          MeaningLines(detail.meanings.lines(detail.word.word)),
        ],
      ]);
    }
    if (word.entries.isEmpty || uid != null) {
      children.addAll(<Widget>[
        const SizedBox(height: 12),
        SgText(
          l10n.docWordsCardInText,
          role: SgTextRole.caption,
          weight: 700,
          color: tokens.color.textSecondary,
        ),
        const SizedBox(height: 2),
        _Sentence(
          sentence: widget.sentence.$1,
          at: widget.sentence.$2,
          word: word.surface,
        ),
        const SizedBox(height: 16),
        ..._actions(l10n, word, uid),
      ]);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  List<Widget> _actions(AppLocalizations l10n, DocWord word, String? uid) {
    if (uid == null) {
      return <Widget>[
        if (word.docClass == DocClass.outside)
          SgButton(
            label: l10n.docWordsCardAddMine,
            onPressed: widget.onAddMine,
          ),
        if (word.customId != null)
          SgButton(
            label: l10n.docWordsCardKeepSentence,
            onPressed: widget.onKeepSentence,
          ),
      ];
    }
    final offered =
        word.docClass == DocClass.newInCourse ||
        word.docClass == DocClass.probablyKnown;
    return <Widget>[
      if (offered)
        SgButton(
          label: widget.added ? l10n.docWordsCardAdded : l10n.docWordsCardAdd,
          onPressed: widget.added
              ? null
              : () => widget.onAdd(word.ambiguous ? _chosen(word, uid) : word),
        ),
      const SizedBox(height: 8),
      Row(
        children: <Widget>[
          if (offered) ...<Widget>[
            Expanded(
              child: SgButton(
                label: l10n.docWordsCardKnow,
                kind: SgButtonKind.secondary,
                compact: true,
                onPressed: () => widget.onKnow(uid),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SgButton(
                label: l10n.docWordsCardIgnore,
                kind: SgButtonKind.secondary,
                compact: true,
                onPressed: widget.onIgnore,
              ),
            ),
          ],
        ],
      ),
      SgButton(
        label: l10n.docWordsCardOpen,
        kind: SgButtonKind.text,
        onPressed: () => widget.onOpen(uid),
      ),
    ];
  }

  /// The ambiguous word, as the reading the learner chose.
  DocWord _chosen(DocWord word, String uid) => word.only(uid);
}

/// The sentence from the document, the word bold.
class _Sentence extends StatelessWidget {
  const _Sentence({
    required this.sentence,
    required this.at,
    required this.word,
  });

  final String sentence;

  /// Where [word] stands in [sentence]: the first match could be inside
  /// another word (agent-3, #1294).
  final int at;
  final String word;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final style = SgText.styleFor(
      tokens,
      SgTextRole.body,
    ).copyWith(color: tokens.color.ink);
    final at = sentence.startsWith(word, this.at.clamp(0, sentence.length))
        ? this.at
        : sentence.indexOf(word);
    return SgRuns(
      at < 0
          ? <TextSpan>[TextSpan(text: sentence)]
          : <TextSpan>[
              TextSpan(text: sentence.substring(0, at)),
              TextSpan(
                text: word,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              TextSpan(text: sentence.substring(at + word.length)),
            ],
      style: style,
    );
  }
}
