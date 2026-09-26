import 'dart:ui' show LocaleStringAttribute, StringAttribute;

import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/app_fonts.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:flutter/foundation.dart' show listEquals;
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

  /// The next role down: what is asked while typing past 130 % (the lead's
  /// call on #571: reduce first, then scroll). `caption` is already the
  /// bottom. A step down then up is the role again, so Bangla keeps its one
  /// step over the Latin; but a Bangla run of a `display` role doesn't
  /// shrink (`headline.oneStepLarger` is `display`), moot while no prompt
  /// sets Bangla at display.
  DpTextRole get oneStepSmaller => switch (this) {
    DpTextRole.display => DpTextRole.headline,
    DpTextRole.headline => DpTextRole.title,
    DpTextRole.title => DpTextRole.bodyLarge,
    DpTextRole.bodyLarge => DpTextRole.body,
    DpTextRole.body => DpTextRole.label,
    DpTextRole.label => DpTextRole.caption,
    DpTextRole.caption => DpTextRole.caption,
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
  /// (flutter/flutter#18443 is open); a headword and `DpText` draw it
  /// themselves (`_Hyphenated`, #419, #502).
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

  /// [text] with syllables to break at only in a word wider than [width] at
  /// [style] and [scaler], for text the planner can't lay out: T2's cloze,
  /// whose gap is a widget (#539). A word that fits keeps its letters
  /// together, so 100 % stays as drawn.
  // ponytail: Flutter draws no "-" at the break (flutter/flutter#18443);
  // a placeholder in `_Hyphenated`'s planner is the upgrade.
  static String breakTooWide(
    String text, {
    required TextStyle style,
    required double width,
    required TextScaler scaler,
  }) {
    if (!width.isFinite) return text;
    bool wider(String word) {
      final painter = TextPainter(
        text: TextSpan(text: word, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      final over = painter.width > width;
      painter.dispose();
      return over;
    }

    return [
      for (final word in text.split(' '))
        word.isEmpty || word.contains(softHyphen) || !wider(word)
            ? word
            : hasBengali(word)
            ? banglaBreaks(word)
            : allowBreaks(word, threshold: 4),
    ].join(' ');
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

  /// Whether the keyboard is up at [large] text, where the room above it is
  /// a few lines and a typed question's screen gives its top bar's row to
  /// what is asked (L8, L12, #554). Read it above the scaffold, which takes
  /// the keyboard out of its body's inset (#529).
  static bool largeTyping(BuildContext context) =>
      large(context) && MediaQuery.viewInsetsOf(context).bottom > 0;

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

  /// How small a Bangla word too wide for its line may shrink before it
  /// breaks instead (#522): the owner's "reduced size". Shrink first, and
  /// break between aksharas, with no "-", only when even this doesn't fit.
  // ponytail: 80 %, a floor that keeps a pronunciation legible beside its
  // German; the owner can move it.
  static const double banglaShrink = 0.8;

  /// [word], Bangla too wide for its line, with a soft hyphen between its
  /// aksharas (#504): before a consonant the letter before doesn't join
  /// with a hasanta, so no conjunct is split and a vowel sign stays on its
  /// letter. That takes in the content's own joints, a hasanta with a
  /// zero-width non-joiner ("…কাইট্‌|স…", "…কার্টেন্‌|আউ…"). Never before a
  /// consonant, or a conjunct, that such a joint, khanda-ta or the word's end
  /// closes ("…লা|ন্ট্‌" would take it from its syllable), before khanda-ta (ৎ),
  /// which ends one too, nor before an independent vowel but after a joint
  /// ("কা|ইট" would split a diphthong). Two aksharas from either end at
  /// least, so nothing breaks right after an opening "/" or "(".

  // ponytail: a legacy khanda-ta (ত্‍, a hasanta and a zero-width joiner)
  // isn't read as closed; the content writes ৎ.
  static String banglaBreaks(String word) {
    const hasanta = 0x9CD, joint = 0x200C, khandaTa = 0x9CE;
    int at(int i) => i >= 0 && i < word.length ? word.codeUnitAt(i) : 0;
    bool consonant(int c) =>
        (c >= 0x995 && c <= 0x9B9) || (c >= 0x9DC && c <= 0x9DF);
    bool vowel(int c) => c >= 0x985 && c <= 0x994;
    bool closed(int i) {
      var last = i;
      while (at(last + 1) == hasanta && consonant(at(last + 2))) {
        last += 2;
      }
      // Closed by a joint, the word's end, or khanda-ta ("…শ্মে|র্ৎ" would
      // start a line with র্ৎ).
      return at(last + 1) == hasanta &&
          (at(last + 2) == joint ||
              at(last + 2) == 0 ||
              at(last + 2) == khandaTa);
    }

    // Where each akshara begins, whether a line may start there or not: a
    // consonant no hasanta joins to the one before, or an independent vowel.
    final aksharas = <int>[
      for (var i = 0; i < word.length; i++)
        if ((consonant(at(i)) && at(i - 1) != hasanta) || vowel(at(i))) i,
    ];
    bool twoEachSide(int i) =>
        aksharas.where((a) => a < i).length >= 2 &&
        aksharas.where((a) => a >= i).length >= 2;
    final breaks = <int>[
      for (var i = 1; i < word.length; i++)
        if (((consonant(at(i)) && at(i - 1) != hasanta && !closed(i)) ||
                (vowel(at(i)) && at(i - 1) == joint)) &&
            twoEachSide(i))
          i,
    ];
    return breaks.reversed.fold(
      word,
      (broken, at) =>
          '${broken.substring(0, at)}$softHyphen${broken.substring(at)}',
    );
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
    this.breakTooWide = false,
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

  /// A word too wide for its line breaks at a syllable, with its "-", even
  /// in a text that offers no soft hyphen: T2's and W1's caption, whose
  /// Bangla pronunciation can be wider than a line at 200 % with no long
  /// German beside it (#504). A text with a soft hyphen always does.
  final bool breakTooWide;

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
    // A line that ends at a syllable shows its "-" (#419), in German, the
    // app's copy or Bangla among them (#502), and not when a caller labels
    // the whole.
    Widget hyphenated(Widget child, List<TextSpan> runs) =>
        maxLines != null ||
            semanticsLabel != null ||
            !(breakTooWide || german || text.contains(DpScript.softHyphen))
        ? child
        : _Hyphenated(runs: runs, child: child);

    if (!german && !DpScript.hasBengali(text)) {
      return hyphenated(
        Text(
          text,
          style: base,
          textAlign: textAlign,
          maxLines: maxLines,
          semanticsLabel: semanticsLabel,
        ),
        [TextSpan(text: text, style: base)],
      );
    }

    // accessibility-performance.md: German is tagged de-DE and Bangla bn-BD,
    // so TalkBack and VoiceOver switch voices mid-string. The spans carry
    // the tags: a label on the whole would drop them (#162), so only a
    // caller's own replaces them.
    final spans = DpScript.spans(
      text,
      latin: base,
      bengali: dressed(role.oneStepLarger),
      german: german,
    );
    return hyphenated(
      Text.rich(
        TextSpan(children: spans),
        textAlign: textAlign,
        maxLines: maxLines,
        semanticsLabel: semanticsLabel,
      ),
      spans,
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
              runs: <TextSpan>[
                if (article != null)
                  TextSpan(text: '$article ', style: articleStyle),
                TextSpan(text: broken, style: wordStyle),
              ],
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

/// Text in runs of their own style and voice, laid out as [DpText] is: a
/// word too wide for its line breaks at a syllable and shows its "-", in
/// its run's style (#419), and a screen reader hears each run whole in its
/// own voice (#162). For a text whose parts differ: T2's verdict, the
/// German marked in the app's copy (#539).
class DpRuns extends StatelessWidget {
  const DpRuns(
    this.runs, {
    super.key,
    this.style,
    this.textAlign,
    this.textScaler,
    this.locale,
  });

  /// Each run's text, style over [style], voice (`locale`) and tap.
  final List<TextSpan> runs;

  /// What every run's style is over.
  final TextStyle? style;
  final TextAlign? textAlign;

  /// None for a [WidgetSpan]'s text, scaled with its sentence already.
  final TextScaler? textScaler;

  /// The paragraph's, for shaping.
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    final merged = <TextSpan>[
      for (final run in runs)
        TextSpan(
          text: run.text,
          style: style?.merge(run.style) ?? run.style,
          recognizer: run.recognizer,
          locale: run.locale,
        ),
    ];
    return _Hyphenated(
      runs: merged,
      child: Text.rich(
        TextSpan(children: merged),
        locale: locale,
        textAlign: textAlign,
        textScaler: textScaler,
      ),
    );
  }
}

/// The course's German in runs of their own style, as R1 draws a sentence
/// with the searched word marked: [DpRuns], every run in a German voice
/// (#535, #539).
class DpGermanRuns extends StatelessWidget {
  const DpGermanRuns(
    this.runs, {
    super.key,
    this.style,
    this.textAlign,
    this.textScaler,
  });

  /// Each run's text, style over [style], and tap (T5's word look-up).
  final List<TextSpan> runs;

  /// What every run's style is over.
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextScaler? textScaler;

  @override
  Widget build(BuildContext context) => DpRuns(
    <TextSpan>[
      for (final run in runs)
        TextSpan(
          text: run.text,
          style: run.style,
          recognizer: run.recognizer,
          locale: DpScript.deDE,
        ),
    ],
    style: style,
    textAlign: textAlign,
    textScaler: textScaler,
    locale: DpScript.deDE,
  );
}

/// A headword, or a text, that wraps at a syllable shows the hyphen there,
/// as print does: "Reiseversi-" over "cherung" (#419). Flutter breaks at a
/// soft hyphen but draws nothing (flutter/flutter#18443), so this breaks
/// the lines itself, as greedily as the paragraph would, keeping room for
/// the "-" on a line that ends at a syllable, and gives its [RichText] that
/// text. Only the picture changes: the headword's label is its own, each
/// run of a text is read as it was, and the widget's text, what a test
/// finds, is the text as it was.
class _Hyphenated extends SingleChildRenderObjectWidget {
  const _Hyphenated({required this.runs, required Widget super.child});

  /// The text in runs of one style and voice, with their soft hyphens: a
  /// headword's article and word, or a text's scripts, German or the app's
  /// copy and Bangla one role larger (`DpScript.spans`, #502).
  final List<TextSpan> runs;

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
    // A rebuild with the same text keeps the lines worked out.
    if (listEquals(value.runs, _widget.runs)) return;
    _widget = value;
    _cache = null;
    markNeedsLayout();
  }

  /// The text's own paragraph: `Text` and `Text.rich` build one [RichText].
  RenderParagraph? get _paragraph =>
      child is RenderParagraph ? child! as RenderParagraph : null;

  /// The last lines worked out, for the width, style and scale they were for.
  (double, TextStyle?, TextScaler, TextSpan)? _cache;

  /// [runs], drawn as [texts] say.
  TextSpan _span(
    TextStyle? root,
    List<TextSpan> runs,
    List<String> texts,
  ) => TextSpan(
    style: root,
    children: <InlineSpan>[
      for (final (i, run) in runs.indexed)
        // Read as it is, whatever lines it is drawn on, in its own voice: a
        // screen reader hears this paragraph when the text isn't a headword.
        TextSpan(
          text: texts[i],
          style: run.style,
          recognizer: run.recognizer,
          locale: run.locale,
          semanticsLabel: run.text!.replaceAll(DpScript.softHyphen, ''),
        ),
    ],
  );

  TextSpan _plain(TextStyle? root) =>
      _span(root, _widget.runs, [for (final run in _widget.runs) run.text!]);

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

    // As drawn, soft hyphens and all: they split the font's kerning, and a
    // line measured without them came out a hair too narrow.
    double widthOf(List<InlineSpan> spans) {
      final painter = _painter(
        paragraph,
        TextSpan(style: root, children: spans),
      )..layout();
      final measured = painter.width;
      painter.dispose();
      return measured;
    }

    // [word] in [style], as small as it must be to fit a line of its own,
    // down to [DpScript.banglaShrink] of its size; null if even that is
    // too wide.
    TextStyle? fitted(String word, TextStyle? style) {
      final size = style?.fontSize ?? root?.fontSize;
      if (size == null) return null;
      for (var scale = 0.95; scale >= DpScript.banglaShrink - 0.001;) {
        final smaller = (style ?? const TextStyle()).copyWith(
          fontSize: size * scale,
        );
        if (widthOf([TextSpan(text: word, style: smaller)]) <= width) {
          return smaller;
        }
        scale -= 0.05;
      }
      return null;
    }

    // A word too wide for a line of its own breaks at its syllables,
    // whatever its length: "selbstbewusst" (13) at T2's display size (#419).
    // One that fits keeps its letters together, and its kerning. A Bangla
    // one, a long compound's pronunciation, first shrinks to fit, in a run
    // of its own; only one still too wide breaks, between aksharas (#504),
    // and with no "-" (the owner's call, #522). German keeps its "-".
    final runs = <TextSpan>[];
    final texts = <String>[];
    var shrunk = false;
    for (final run in _widget.runs) {
      var said = '';
      var shown = '';
      void part(String text, String drawn, TextStyle? style) {
        if (text.isEmpty) return;
        runs.add(
          TextSpan(
            text: text,
            style: style,
            recognizer: run.recognizer,
            locale: run.locale,
          ),
        );
        texts.add(drawn);
      }

      for (final (i, word) in run.text!.split(' ').indexed) {
        final space = i == 0 ? '' : ' ';
        final fits =
            word.isEmpty ||
            word.contains(DpScript.softHyphen) ||
            widthOf([TextSpan(text: word, style: run.style)]) <= width;
        if (!fits && DpScript.hasBengali(word)) {
          // Shrunk to fit; or, too wide even at the floor, broken between
          // aksharas at that reduced size, the owner's order (#522).
          final smaller = fitted(word, run.style);
          final size = run.style?.fontSize ?? root?.fontSize;
          final reduced =
              smaller ??
              (size == null
                  ? run.style
                  : (run.style ?? const TextStyle()).copyWith(
                      fontSize: size * DpScript.banglaShrink,
                    ));
          part('$said$space', '$shown$space', run.style);
          part(
            word,
            smaller == null ? DpScript.banglaBreaks(word) : word,
            reduced,
          );
          (said, shown, shrunk) = ('', '', true);
          continue;
        }
        said += '$space$word';
        shown +=
            '$space${fits
                ? word
                : DpScript.hasBengali(word)
                ? DpScript.banglaBreaks(word)
                : DpScript.allowBreaks(word, threshold: 4)}';
      }
      part(said, shown, run.style);
    }
    final full = texts.join();
    // A soft hyphen in Bangla breaks with no "-" (#522).
    bool bare(int at) =>
        at + 1 < full.length && DpScript.isBengaliRune(full.codeUnitAt(at + 1));
    final starts = [0];
    for (final text in texts) {
      starts.add(starts.last + text.length);
    }

    // [full] from [from] to [to], each part in its run's style, and [end]
    // in the last's.
    List<InlineSpan> stretch(int from, int to, String end) {
      final spans = <TextSpan>[];
      for (final (i, run) in runs.indexed) {
        final a = from > starts[i] ? from : starts[i];
        final b = to < starts[i + 1] ? to : starts[i + 1];
        if (a < b) {
          spans.add(TextSpan(text: full.substring(a, b), style: run.style));
        }
      }
      if (end.isNotEmpty && spans.isNotEmpty) {
        spans.add(TextSpan(text: end, style: spans.last.style));
      }
      return spans;
    }

    // The pieces a line may end after, [from, to), each with what follows
    // it: a space (the break takes its place), a soft hyphen (the break
    // draws "-"), or nothing, after a "-", "/" or dash, which the paragraph
    // breaks after too. Not a space before a "/", ")", "!", "," and the like,
    // which the paragraph never breaks before (UAX #14, LB13): "· /…/"
    // goes on together, as the paragraph put it.
    // ponytail: an opening "/" can end a line, apart from its
    // pronunciation, as the paragraph's own breaking has it. Keeping them
    // together needs a look-ahead for when the two no longer fit a line.
    final pieces = <(int, int, String)>[];
    var from = 0;
    for (var i = 0; i < full.length; i++) {
      final c = full[i];
      final held = i + 1 < full.length && '/)]}!?,.;:'.contains(full[i + 1]);
      if ((c == ' ' && !held) || c == DpScript.softHyphen) {
        pieces.add((from, i, c));
        from = i + 1;
      } else if ('-/–—'.contains(c) && i + 1 < full.length) {
        pieces.add((from, i + 1, ''));
        from = i + 1;
      }
    }
    pieces.add((from, full.length, ''));

    // Where each line but the last ends, and what it ends at.
    final ends = <int, String>{};
    var (line, end, after) = pieces.first;
    for (final (start, to, next) in pieces.skip(1)) {
      // Room for the "-" should the line end at this piece's syllable.
      final hyphen = next == DpScript.softHyphen && !bare(to) ? '-' : '';
      if (widthOf(stretch(line, to, hyphen)) <= width) {
        (end, after) = (to, next);
        continue;
      }
      ends[end] = after;
      (line, end, after) = (start, to, next);
    }

    // On one line the paragraph draws it as it was. Otherwise the lines are
    // given, even when all break at spaces: left to itself, the paragraph
    // could break at a syllable the plan kept whole, with no "-" (#419).
    // Each run takes its own part, so it keeps its style and voice (#502).
    String drawn(int run) {
      final text = StringBuffer();
      for (var i = starts[run]; i < starts[run + 1]; i++) {
        text.write(switch (ends[i]) {
          ' ' => '\n',
          DpScript.softHyphen => bare(i) ? '\n' : '-\n',
          _ => full[i],
        });
        // After a dash, the line ends after it.
        if (ends[i + 1] == '') text.write('\n');
      }
      return text.toString();
    }

    final shown = ends.isEmpty && !shrunk
        ? plain
        : _span(root, runs, [for (var i = 0; i < texts.length; i++) drawn(i)]);
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

  /// Whether the paragraph measures itself: when this breaks no lines, as
  /// under an ambient `maxLines` or `softWrap: false`.
  bool get _asIs {
    final paragraph = _paragraph;
    return paragraph == null ||
        paragraph.maxLines != null ||
        !paragraph.softWrap;
  }

  // The intrinsics and the dry layout are the text's as it will be drawn,
  // not the last layout's lines, which were for another width.
  @override
  double computeMinIntrinsicWidth(double height) => _asIs
      ? super.computeMinIntrinsicWidth(height)
      : _laidOut(double.infinity, (p) => p.minIntrinsicWidth, plain: true);

  @override
  double computeMaxIntrinsicWidth(double height) => _asIs
      ? super.computeMaxIntrinsicWidth(height)
      : _laidOut(double.infinity, (p) => p.maxIntrinsicWidth, plain: true);

  @override
  double computeMinIntrinsicHeight(double width) => _asIs
      ? super.computeMinIntrinsicHeight(width)
      : _laidOut(width, (p) => p.height);

  @override
  double computeMaxIntrinsicHeight(double width) => _asIs
      ? super.computeMaxIntrinsicHeight(width)
      : _laidOut(width, (p) => p.height);

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    if (_asIs) return super.computeDryLayout(constraints);
    final paragraph = _paragraph!;
    final painter = _painter(paragraph, _shown(paragraph, constraints.maxWidth))
      ..layout(minWidth: constraints.minWidth, maxWidth: constraints.maxWidth);
    final size = constraints.constrain(painter.size);
    painter.dispose();
    return size;
  }
}
