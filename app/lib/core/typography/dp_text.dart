import 'dart:ui' show LocaleStringAttribute, StringAttribute;

import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/app_fonts.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:flutter/rendering.dart' show RenderParagraph, RenderProxyBox;
import 'package:flutter/semantics.dart' show AttributedString;
import 'package:material_ui/material_ui.dart';

/// One role of the type scale, named so callers ask for a role rather than a
/// number. `docs/01-architecture/theming.md` defines all seven.
enum DpTextRole { display, headline, title, bodyLarge, body, label, caption }

extension DpTextRoleTokens on DpTextRole {
  DpTextToken token(DpTypeTokens type) => switch (this) {
    DpTextRole.display => type.display,
    DpTextRole.headline => type.headline,
    DpTextRole.title => type.title,
    DpTextRole.bodyLarge => type.bodyLarge,
    DpTextRole.body => type.body,
    DpTextRole.label => type.label,
    DpTextRole.caption => type.caption,
  };

  /// The next role up, used for Bangla. `display` is already the top.
  DpTextRole get oneStepLarger => switch (this) {
    DpTextRole.display => DpTextRole.display,
    DpTextRole.headline => DpTextRole.display,
    DpTextRole.title => DpTextRole.headline,
    DpTextRole.bodyLarge => DpTextRole.title,
    DpTextRole.body => DpTextRole.bodyLarge,
    DpTextRole.label => DpTextRole.body,
    DpTextRole.caption => DpTextRole.label,
  };
}

/// Script-aware text helpers.
///
/// `theming.md`: "Bangla is set one step larger at the same role." Bengali
/// glyphs have a smaller optical size than Latin at the same point size, so
/// matching the number makes the Bangla look shrunken next to the German.
///
/// Most strings in this app are mixed — `die Wohnung · ফ্ল্যাট`, the headword
/// caption, the widget's Wort des Tages — so the step applies per run, not per
/// string. A string that is half German gets German at its role and Bangla one
/// step up, in the same line.
abstract final class DpScript {
  /// The Bengali Unicode block.
  static const int _bengaliStart = 0x0980;
  static const int _bengaliEnd = 0x09FF;

  static bool isBengaliRune(int rune) =>
      rune >= _bengaliStart && rune <= _bengaliEnd;

  static bool hasBengali(String text) => text.runes.any(isBengaliRune);

  /// Splits [text] into runs of Bengali and not-Bengali, preserving order.
  ///
  /// Whitespace and punctuation join whichever run precedes them, so a separator
  /// does not produce a third run and a visible size jump around the `·`.
  static List<(String text, bool bengali)> runs(String text) {
    if (text.isEmpty) return const <(String, bool)>[];

    final out = <(String, bool)>[];
    final buffer = StringBuffer();
    bool? current;

    for (final rune in text.runes) {
      final isLetter = _isLetterOrMark(rune);
      final bengali = isBengaliRune(rune);

      // Non-letters join the run in progress. With no run yet — a string that
      // opens with a space or punctuation — they wait for the first letter, so
      // leading whitespace does not open a spurious run of the wrong script.
      if (!isLetter) {
        buffer.writeCharCode(rune);
        continue;
      }

      if (current == null || bengali == current) {
        current ??= bengali;
        buffer.writeCharCode(rune);
        continue;
      }

      out.add((buffer.toString(), current));
      buffer
        ..clear()
        ..writeCharCode(rune);
      current = bengali;
    }

    if (buffer.isNotEmpty) out.add((buffer.toString(), current ?? false));
    return out;
  }

  /// The course's German, for a screen reader's voice.
  static const Locale deDE = Locale('de', 'DE');

  /// Bangla, for a screen reader's voice.
  static const Locale bnBD = Locale('bn', 'BD');

  /// [text] as spans a screen reader reads each in its own voice (#162):
  /// Bangla tagged bn-BD, and the rest de-DE when it is the course's German
  /// ([german]). Otherwise the rest is the app's own copy, and untagged, so
  /// it is read in the app's language. A soft hyphen is not read.
  static List<TextSpan> spans(
    String text, {
    required TextStyle latin,
    required TextStyle bengali,
    bool german = false,
  }) => <TextSpan>[
    for (final (run, isBengali) in runs(text))
      TextSpan(
        text: run,
        style: isBengali ? bengali : latin,
        locale: isBengali ? bnBD : (german ? deDE : null),
        semanticsLabel: run.contains(softHyphen)
            ? run.replaceAll(softHyphen, '')
            : null,
      ),
  ];

  static bool _isLetterOrMark(int rune) {
    if (rune >= 0x41 && rune <= 0x5A) return true; // A-Z
    if (rune >= 0x61 && rune <= 0x7A) return true; // a-z
    if (rune >= 0xC0 && rune <= 0x24F) return true; // Latin-1 supplement + ext
    if (rune == 0x1E9E || rune == 0xDF) return true; // ẞ ß
    return isBengaliRune(rune);
  }

  /// The soft hyphen: a place a line may break.
  ///
  /// ponytail: Flutter breaks there but draws no hyphen at the break
  /// (flutter/flutter#18443 is open); a headword and single-script
  /// `DpText` draw it themselves (`_Hyphenated`, #419).
  static const String softHyphen = '­';

  /// Lets a long German compound break between syllables rather than
  /// overflow, or wrap at an arbitrary letter.
  ///
  /// Not a dictionary's hyphenation, but German's syllable rule: a break
  /// falls before the consonants that open the next syllable (#405). A word
  /// longer than [threshold] gets a break opportunity at every syllable
  /// (two letters from either end at least), and the layout takes the
  /// last that fits, so even 200 % text wraps between syllables. Soft
  /// hyphens already in the content are respected.
  static String allowBreaks(String text, {int threshold = 14}) {
    if (text.contains(softHyphen)) return text;

    return text
        .split(' ')
        .map(
          (word) => word.length <= threshold
              ? word
              : _syllableBreaks(word).reversed.fold(
                  word,
                  (broken, at) =>
                      '${broken.substring(0, at)}$softHyphen'
                      '${broken.substring(at)}',
                ),
        )
        .join(' ');
  }

  /// The word length [allowBreaks] starts at, for text in [context]. Above
  /// 100 % text any word of five letters or more may break at its syllables,
  /// not only a long compound: at 200 % a display-size "Wohnung" or
  /// "geschafft!" is wider than its line, and Flutter would cut it at any
  /// letter (#165). Not at 100 %, where it fits, and a soft hyphen would
  /// still split its kerning.
  static int breakThreshold(BuildContext context) => scaled(context) ? 4 : 14;

  /// Whether text in [context] is larger than 100 %: where a label that fits
  /// at 100 % may need a syllable to break at (#165).
  static bool scaled(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(1) > 1;

  /// [size], a box around text at [role], grown as that text grows: by the
  /// factor the text takes, not by `scale(size)`. Android 14+ scales text
  /// nonlinearly — at 200 % 14 sp is 28, but 96 is about 97 — so a box's
  /// own size scaled as if it were a font barely grows (#165).
  static double grow(
    BuildContext context,
    double size, {
    DpTextRole role = DpTextRole.body,
  }) {
    final text = role.token(context.tokens.typography).size;
    return size * MediaQuery.textScalerOf(context).scale(text) / text;
  }

  /// Whether text in [context] is past 130 %, where two things side by side
  /// no longer fit a phone's width and one goes under the other (#165), as
  /// the tab bar scrolls from there (#314).
  /// ponytail: a threshold, not a measurement; measure where one row's
  /// content needs it.
  static bool large(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(14) > 14 * 1.3;

  static const String _vowels = 'aeiouyäöüAEIOUYÄÖÜ';

  /// The consonants that can open a German syllable together, besides any
  /// one alone: a break goes before the longest of them that ends a run.
  static const Set<String> _onsets = <String>{
    'ch', 'ck', 'ph', 'pf', 'th', 'sch', 'schl', 'schm', 'schn', 'schr', //
    'schw', 'bl', 'br', 'dr', 'fl', 'fr', 'gl', 'gr', 'kl', 'kn', 'kr', //
    'pl', 'pr', 'tr', 'zw', 'sp', 'st', 'spr', 'str', 'pfl', 'pfr', 'chr',
  };

  /// Where [word]'s syllables begin, two letters from either end at least
  /// (German hyphenation's minimum): in a vowel, consonants, vowel run, before the consonants that
  /// open the next syllable ("Haft|pflicht|ver|si|che|rung").
  static List<int> _syllableBreaks(String word) {
    bool vowel(int i) => _vowels.contains(word[i]);
    final breaks = <int>[];
    var i = 1;
    while (i < word.length) {
      if (!vowel(i - 1) || vowel(i)) {
        i++;
        continue;
      }
      var end = i;
      while (end < word.length && !vowel(end)) {
        end++;
      }
      if (end == word.length) break;
      final run = word.substring(i, end).toLowerCase();
      var start = end - 1;
      for (var length = run.length; length > 1; length--) {
        if (_onsets.contains(run.substring(run.length - length))) {
          start = end - length;
          break;
        }
      }
      if (start >= 2 && word.length - start >= 2) breaks.add(start);
      i = end;
    }
    return breaks;
  }
}

/// Text at a role from the scale, with Bangla automatically one step larger.
///
/// Screens use this rather than `Text` so the Bangla rule cannot be forgotten
/// on the one screen where it matters most.
class DpText extends StatelessWidget {
  const DpText(
    this.data, {
    required this.role,
    super.key,
    this.color,
    this.weight,
    this.italic = false,
    this.textAlign,
    this.maxLines,
    this.allowBreaks = false,
    this.semanticsLabel,
    this.letterSpacing,
    this.german = false,
  });

  final String data;
  final DpTextRole role;
  final Color? color;

  /// Overrides the role's own weight on the variable font's `wght` axis.
  final double? weight;
  final bool italic;
  final TextAlign? textAlign;
  final int? maxLines;

  /// Give an over-long German compound somewhere to break. Off by default: it
  /// is only right for free text, not for a headword being learned.
  final bool allowBreaks;

  final String? semanticsLabel;

  /// Tracking in logical pixels, for the few uppercase labels that carry it.
  final double? letterSpacing;

  /// The course's German (an example, a sentence), not the app's copy: a
  /// screen reader reads it in a German voice (#162).
  final bool german;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = allowBreaks
        ? DpScript.allowBreaks(
            data,
            threshold: DpScript.breakThreshold(context),
          )
        : data;

    // Applied to every style, not just the Latin one: a weight silently
    // dropped on mixed strings would be dropped on most of this app's copy.
    TextStyle dressed(DpTextRole forRole) {
      final style = styleFor(tokens, forRole, color: color ?? tokens.color.ink)
          .copyWith(
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            letterSpacing: letterSpacing,
          );
      return weight == null
          ? style
          : style.copyWith(fontVariations: AppFonts.weight(weight!));
    }

    final base = dressed(role);
    // A line that ends at a syllable shows its "-" (#419): for German or
    // the app's copy, and not when a caller labels the whole.
    // ponytail: not with Bangla in the text (T2's caption with the
    // pronunciation on), whose runs the drawn lines would have to map back
    // onto; it breaks at a syllable with no "-" there (#502).
    Widget hyphenated(Widget child) =>
        maxLines != null ||
            semanticsLabel != null ||
            !text.contains(DpScript.softHyphen) ||
            DpScript.hasBengali(text)
        ? child
        : _Hyphenated(
            article: null,
            word: text,
            articleStyle: base,
            wordStyle: base,
            locale: german ? DpScript.deDE : null,
            child: child,
          );

    if (!german && !DpScript.hasBengali(text)) {
      return hyphenated(
        Text(
          text,
          style: base,
          textAlign: textAlign,
          maxLines: maxLines,
          semanticsLabel: semanticsLabel,
        ),
      );
    }

    // accessibility-performance.md: German is tagged de-DE and Bangla bn-BD,
    // so TalkBack and VoiceOver switch voices mid-string. The spans carry
    // the tags: a label on the whole would drop them (#162), so only a
    // caller's own replaces them.
    return hyphenated(
      Text.rich(
        TextSpan(
          children: DpScript.spans(
            text,
            latin: base,
            bengali: dressed(role.oneStepLarger),
            german: german,
          ),
        ),
        textAlign: textAlign,
        maxLines: maxLines,
        semanticsLabel: semanticsLabel,
      ),
    );
  }

  /// The [TextStyle] for one role, with the family, fallback and `wght` axis set.
  static TextStyle styleFor(DpTokens tokens, DpTextRole role, {Color? color}) {
    final token = role.token(tokens.typography);
    return TextStyle(
      fontFamily: AppFonts.latin,
      fontFamilyFallback: AppFonts.fallback,
      fontSize: token.size,
      height: token.heightFactor,
      fontVariations: AppFonts.weight(token.weight),
      color: color ?? tokens.color.ink,
    );
  }
}

/// One line of [text], cut at a word rather than inside one: "konnte,
/// musste, wollte — no …" and never "wol…". L2's rule previews.
class DpOneLine extends StatelessWidget {
  const DpOneLine(
    this.text, {
    required this.role,
    super.key,
    this.color,
    this.weight,
    this.size,
  });

  final String text;
  final DpTextRole role;
  final Color? color;
  final double? weight;

  /// The role's size, overridden: an app bar title the artboards draw
  /// between two roles (#280). Bangla still takes the next role up.
  final double? size;

  static const String ellipsis = '…';

  @override
  Widget build(BuildContext context) {
    // Measured as it will be drawn: `Text` merges the ambient text style —
    // a Material body's letter spacing — and a measure without it cut the
    // line a few pixels too late, clipping a letter in half.
    TextStyle styled(DpTextRole at, {double? size}) {
      final own = DpText.styleFor(context.tokens, at, color: color);
      return DefaultTextStyle.of(context).style.merge(
        own.copyWith(
          fontSize: size,
          fontVariations: weight == null ? null : AppFonts.weight(weight!),
        ),
      );
    }

    final style = styled(role, size: size);
    // Bangla one step larger, as DpText sets it (`theming.md`).
    final larger = styled(role.oneStepLarger);
    TextSpan span(String line) => !DpScript.hasBengali(line)
        ? TextSpan(text: line, style: style)
        : TextSpan(
            style: style,
            children: DpScript.spans(line, latin: style, bengali: larger),
          );
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        bool fits(String candidate) {
          final painter = TextPainter(
            text: span(candidate),
            textDirection: direction,
            textScaler: scaler,
            maxLines: 1,
          )..layout(maxWidth: constraints.maxWidth);
          final over = painter.didExceedMaxLines;
          painter.dispose();
          return !over;
        }

        var shown = text;
        if (!fits(text)) {
          // The most words that fit with the ellipsis after them.
          final words = text.split(' ');
          var low = 0;
          var high = words.length - 1;
          while (low < high) {
            final middle = (low + high + 1) ~/ 2;
            if (fits('${words.take(middle).join(' ')}$ellipsis')) {
              low = middle;
            } else {
              high = middle - 1;
            }
          }
          shown = low == 0
              ? ellipsis
              : '${words.take(low).join(' ').replaceAll(RegExp(r'[,;:—–&·/+-]+$'), '').trimRight()}$ellipsis';
        }
        return DpScript.hasBengali(shown)
            ? Text.rich(
                span(shown),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                // Whole when cut. Uncut, the spans read themselves, each in
                // its own voice (bn-BD, de-DE).
                semanticsLabel: shown == text ? null : text,
              )
            : Text(
                shown,
                style: style,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                semanticsLabel: text,
              );
      },
    );
  }
}

/// A headword that wraps rather than clipping or shrinking.
///
/// `accessibility-performance.md`: "Text scaling to 200 %; long compounds
/// soft-hyphenate" and "the headword is announced with article and gender".
///
/// It deliberately does NOT scale down to fit. Fitting
/// `Wohnungsgeberbestätigung` onto one line at 200 % takes it to about 3 % of
/// its nominal size — a few pixels tall — which inverts the setting the learner
/// chose. Wrapping onto two or three lines keeps the size they asked for, and a
/// break opportunity is offered so the wrap lands somewhere sensible.
class DpHeadword extends StatelessWidget {
  const DpHeadword(
    this.word, {
    super.key,
    this.article,
    this.role = DpTextRole.display,
    this.textAlign,
    this.weight,
    this.maxLines,
    this.colour,
    this.plural,
  });

  final String word;

  /// Printed, never implied by colour alone.
  final String? article;

  /// A noun's plural (`Word.forms`), if it has one: with *die* it is what
  /// says the noun is feminine and not a plural itself (#162).
  final String? plural;

  final DpTextRole role;
  final TextAlign? textAlign;

  /// The role's own unless given: a list row sets its headword at 600.
  final double? weight;

  /// Unlimited, so the word card wraps; a list row's fixed height takes one
  /// line ending in "…", as the artboards' `text-overflow: ellipsis`.
  final int? maxLines;

  /// Article and word in one colour, for a headword set on its gender's own
  /// fill (W1's header), where the article colour would vanish. The article
  /// is still printed, so the gender is not carried by colour alone.
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final articleColour = tokens.color.textForArticle(article);
    TextStyle style(Color colour) {
      final base = DpText.styleFor(tokens, role, color: colour);
      return weight == null
          ? base
          : base.copyWith(fontVariations: AppFonts.weight(weight!));
    }

    final articleStyle = style(colour ?? articleColour ?? tokens.color.ink);
    final wordStyle = style(colour ?? tokens.color.ink);
    final broken = DpScript.allowBreaks(
      word,
      threshold: DpScript.breakThreshold(context),
    );
    final text = Text.rich(
      TextSpan(
        children: <InlineSpan>[
          if (article != null) TextSpan(text: '$article ', style: articleStyle),
          TextSpan(text: broken, style: wordStyle),
        ],
      ),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );

    // Announced with its article and gender, the German in a German voice
    // and the gender in the app's ("die Wohnung, feminine"), as
    // accessibility-performance.md requires, and without the soft hyphen.
    final said = article == null ? word : '$article $word';
    final gender = _gender(
      Localizations.of<AppLocalizations>(context, AppLocalizations),
    );
    return Semantics(
      attributedLabel: AttributedString(
        gender == null ? said : '$said, $gender',
        attributes: <StringAttribute>[
          LocaleStringAttribute(
            range: TextRange(start: 0, end: said.length),
            locale: DpScript.deDE,
          ),
        ],
      ),
      excludeSemantics: true,
      // Every headword that may wrap: one too wide for its line breaks at a
      // syllable, whatever its length, and shows the "-" (#419).
      child: maxLines != null
          ? text
          : _Hyphenated(
              article: article,
              word: broken,
              articleStyle: articleStyle,
              wordStyle: wordStyle,
              child: text,
            ),
    );
  }

  /// The gender the article gives. None for *die* without a plural: a
  /// plural-only noun (die Leute, die Kosten) takes *die* too, and the
  /// course doesn't mark one, so "feminine" could be wrong (#162).
  String? _gender(AppLocalizations? l10n) => l10n == null
      ? null
      : switch (article) {
          'der' => l10n.genderMasculine,
          'das' => l10n.genderNeuter,
          'die' when plural != null => l10n.genderFeminine,
          _ => null,
        };
}

/// A headword, or a single-script text, that wraps at a syllable shows the
/// hyphen there, as print does: "Reiseversi-" over "cherung" (#419). Flutter breaks at a soft hyphen
/// but draws nothing (flutter/flutter#18443), so this breaks the lines
/// itself, as greedily as the paragraph would, keeping room for the "-" on
/// a line that ends at a syllable, and gives its [RichText] that text. Only
/// the picture changes: the headword's label is its own, and the
/// widget's text, what a test finds, is the word as it was.
class _Hyphenated extends SingleChildRenderObjectWidget {
  const _Hyphenated({
    required this.article,
    required this.word,
    required this.articleStyle,
    required this.wordStyle,
    required Widget super.child,
    this.locale,
  });

  final String? article;

  /// With its soft hyphens.
  final String word;
  final TextStyle articleStyle;
  final TextStyle wordStyle;

  /// The word's voice, for a screen reader: German's, or the app's (null).
  final Locale? locale;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHyphenated(this);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHyphenated renderObject,
  ) => renderObject.widget = this;
}

class _RenderHyphenated extends RenderProxyBox {
  _RenderHyphenated(this._widget);

  _Hyphenated _widget;
  set widget(_Hyphenated value) {
    _widget = value;
    _cache = null;
    markNeedsLayout();
  }

  /// The text's own paragraph: `Text` and `Text.rich` build one [RichText].
  RenderParagraph? get _paragraph =>
      child is RenderParagraph ? child! as RenderParagraph : null;

  /// The last lines worked out, for the width, style and scale they were for.
  (double, TextStyle?, TextScaler, TextSpan)? _cache;

  TextSpan _span(TextStyle? root, String? article, String word) => TextSpan(
    style: root,
    children: <InlineSpan>[
      if (article != null) TextSpan(text: article, style: _widget.articleStyle),
      // Read as it is, whatever lines it is drawn on: a screen reader hears
      // this paragraph when the text isn't a headword.
      TextSpan(
        text: word,
        style: _widget.wordStyle,
        locale: _widget.locale,
        semanticsLabel: _widget.word.replaceAll(DpScript.softHyphen, ''),
      ),
    ],
  );

  TextSpan _plain(TextStyle? root) {
    final article = _widget.article;
    return _span(root, article == null ? null : '$article ', _widget.word);
  }

  TextPainter _painter(RenderParagraph paragraph, InlineSpan text) =>
      TextPainter(
        text: text,
        textDirection: paragraph.textDirection,
        textScaler: paragraph.textScaler,
        textAlign: paragraph.textAlign,
        strutStyle: paragraph.strutStyle,
        textHeightBehavior: paragraph.textHeightBehavior,
        textWidthBasis: paragraph.textWidthBasis,
        locale: paragraph.locale,
      );

  /// The text as the lines to [width] show it: a line that ends at a
  /// syllable ends in "-". The text as it was when it fits on one line.
  TextSpan _shown(RenderParagraph paragraph, double width) {
    final root = (paragraph.text as TextSpan).style;
    final plain = _plain(root);
    // Nothing to break: no width to break to, or a paragraph that doesn't
    // wrap (an ambient `maxLines` or `softWrap: false`).
    if (!width.isFinite || paragraph.maxLines != null || !paragraph.softWrap) {
      return plain;
    }
    final cached = _cache;
    if (cached != null &&
        cached.$1 == width &&
        cached.$2 == root &&
        cached.$3 == paragraph.textScaler) {
      return cached.$4;
    }

    double widthOf(String line) {
      final painter = _painter(
        paragraph,
        TextSpan(
          style: root,
          children: <InlineSpan>[
            // As drawn, soft hyphens and all: they split the font's kerning,
            // and a line measured without them came out a hair too narrow.
            TextSpan(text: line, style: _widget.wordStyle),
          ],
        ),
      )..layout();
      final measured = painter.width;
      painter.dispose();
      return measured;
    }

    // A word too wide for a line of its own breaks at its syllables,
    // whatever its length: "selbstbewusst" (13) at T2's display size (#419).
    // One that fits keeps its letters together, and its kerning.
    final article = _widget.article;
    final full = [
      for (final word
          in (article == null ? _widget.word : '$article ${_widget.word}')
              .split(' '))
        !word.contains(DpScript.softHyphen) && widthOf(word) > width
            ? DpScript.allowBreaks(word, threshold: 4)
            : word,
    ].join(' ');

    // The pieces a line may end after, each with what follows it: a space
    // (the break takes its place), a soft hyphen (the break draws "-"), or
    // nothing, after a "-", "/" or dash, which the paragraph breaks after too.
    final pieces = <(String, String)>[];
    var from = 0;
    for (var i = 0; i < full.length; i++) {
      final c = full[i];
      if (c == ' ' || c == DpScript.softHyphen) {
        pieces.add((full.substring(from, i), c));
        from = i + 1;
      } else if ('-/–—'.contains(c) && i + 1 < full.length) {
        pieces.add((full.substring(from, i + 1), ''));
        from = i + 1;
      }
    }
    pieces.add((full.substring(from), ''));

    final lines = <String>[];
    var line = '';
    var after = '';
    for (final (piece, next) in pieces) {
      if (line.isEmpty && lines.isEmpty && after.isEmpty) {
        (line, after) = (piece, next);
        continue;
      }
      final longer = '$line$after$piece';
      // Room for the "-" should the line end at this piece's syllable.
      final end = next == DpScript.softHyphen ? '$longer-' : longer;
      if (widthOf(end) <= width) {
        (line, after) = (longer, next);
        continue;
      }
      lines.add(after == DpScript.softHyphen ? '$line-' : line);
      (line, after) = (piece, next);
    }
    lines.add(line);

    // On one line the paragraph draws it as it was. Otherwise the lines are
    // given, even when all break at spaces: left to itself, the paragraph
    // could break at a syllable the plan kept whole, with no "-" (#419).
    final TextSpan shown;
    if (lines.length == 1) {
      shown = plain;
    } else {
      final text = lines.join('\n');
      shown = article == null
          ? _span(root, null, text)
          : _span(
              root,
              text.substring(0, article.length + 1),
              text.substring(article.length + 1),
            );
    }
    _cache = (width, root, paragraph.textScaler, shown);
    return shown;
  }

  @override
  void performLayout() {
    final paragraph = _paragraph;
    if (paragraph != null) {
      invokeLayoutCallback<BoxConstraints>((constraints) {
        paragraph.text = _shown(paragraph, constraints.maxWidth);
      });
    }
    super.performLayout();
  }

  /// [measure] of the text laid out to [width] as it would be drawn.
  double _laidOut(
    double width,
    double Function(TextPainter painter) measure, {
    bool plain = false,
  }) {
    final paragraph = _paragraph!;
    final painter = _painter(
      paragraph,
      plain
          ? _plain((paragraph.text as TextSpan).style)
          : _shown(paragraph, width),
    )..layout(maxWidth: width);
    final measured = measure(painter);
    painter.dispose();
    return measured;
  }

  // The intrinsics and the dry layout are the text's as it will be drawn,
  // not the last layout's lines, which were for another width.
  @override
  double computeMinIntrinsicWidth(double height) => _paragraph == null
      ? super.computeMinIntrinsicWidth(height)
      : _laidOut(double.infinity, (p) => p.minIntrinsicWidth, plain: true);

  @override
  double computeMaxIntrinsicWidth(double height) => _paragraph == null
      ? super.computeMaxIntrinsicWidth(height)
      : _laidOut(double.infinity, (p) => p.maxIntrinsicWidth, plain: true);

  @override
  double computeMinIntrinsicHeight(double width) => _paragraph == null
      ? super.computeMinIntrinsicHeight(width)
      : _laidOut(width, (p) => p.height);

  @override
  double computeMaxIntrinsicHeight(double width) => _paragraph == null
      ? super.computeMaxIntrinsicHeight(width)
      : _laidOut(width, (p) => p.height);

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final paragraph = _paragraph;
    if (paragraph == null) return super.computeDryLayout(constraints);
    final painter = _painter(paragraph, _shown(paragraph, constraints.maxWidth))
      ..layout(minWidth: constraints.minWidth, maxWidth: constraints.maxWidth);
    final size = constraints.constrain(painter.size);
    painter.dispose();
    return size;
  }
}
