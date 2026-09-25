import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/app_fonts.dart';
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

  static bool _isLetterOrMark(int rune) {
    if (rune >= 0x41 && rune <= 0x5A) return true; // A-Z
    if (rune >= 0x61 && rune <= 0x7A) return true; // a-z
    if (rune >= 0xC0 && rune <= 0x24F) return true; // Latin-1 supplement + ext
    if (rune == 0x1E9E || rune == 0xDF) return true; // ẞ ß
    return isBengaliRune(rune);
  }

  /// The soft hyphen. Flutter breaks a line here and renders a hyphen only when
  /// it does, which is what `accessibility-performance.md` asks for with "long
  /// compounds soft-hyphenate".
  static const String softHyphen = '\u00AD';

  /// Lets a long German compound break rather than overflow.
  ///
  /// This is **not** German hyphenation — that needs a dictionary, and breaking
  /// `Wohnungsgeberbestätigung` in the wrong place is worse than not breaking it
  /// for someone learning the word. Soft hyphens already present in the content
  /// are respected; beyond that a word only gets break opportunities once it is
  /// longer than [threshold], and only at the boundaries the content supplies.
  static String allowBreaks(String text, {int threshold = 14}) {
    if (text.contains(softHyphen)) return text;

    return text
        .split(' ')
        .map((word) => word.length <= threshold ? word : _breakLongWord(word))
        .join(' ');
  }

  /// Inserts one break opportunity near the middle of an over-long word, at a
  /// consonant boundary so the break lands between syllables more often than
  /// not. A single conservative break beats scattering them.
  static String _breakLongWord(String word) {
    const vowels = 'aeiouäöüAEIOUÄÖÜ';
    final middle = word.length ~/ 2;

    for (var offset = 0; offset < word.length ~/ 4; offset++) {
      for (final index in <int>[middle + offset, middle - offset]) {
        if (index <= 2 || index >= word.length - 2) continue;
        final before = word[index - 1];
        final at = word[index];
        if (!vowels.contains(before) && vowels.contains(at)) {
          return '${word.substring(0, index)}$softHyphen${word.substring(index)}';
        }
      }
    }
    return word;
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

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = allowBreaks ? DpScript.allowBreaks(data) : data;

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

    if (!DpScript.hasBengali(text)) {
      return Text(
        text,
        style: base,
        textAlign: textAlign,
        maxLines: maxLines,
        semanticsLabel: semanticsLabel,
      );
    }

    final larger = dressed(role.oneStepLarger);

    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          for (final (runText, bengali) in DpScript.runs(text))
            TextSpan(
              text: runText,
              style: bengali ? larger : base,
              // accessibility-performance.md: German is tagged de-DE and Bangla
              // bn-BD so TalkBack and VoiceOver switch voices mid-string.
              locale: bengali
                  ? const Locale('bn', 'BD')
                  : const Locale('de', 'DE'),
            ),
        ],
      ),
      textAlign: textAlign,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel ?? text,
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
            children: <InlineSpan>[
              for (final (run, bengali) in DpScript.runs(line))
                TextSpan(
                  text: run,
                  style: bengali ? larger : style,
                  locale: bengali
                      ? const Locale('bn', 'BD')
                      : const Locale('de', 'DE'),
                ),
            ],
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
              : '${words.take(low).join(' ').replaceAll(RegExp(r'[,;:—–-]+$'), '').trimRight()}$ellipsis';
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
  });

  final String word;

  /// Printed, never implied by colour alone.
  final String? article;

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

    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          if (article != null)
            TextSpan(
              text: '$article ',
              style: style(colour ?? articleColour ?? tokens.color.ink),
            ),
          TextSpan(
            text: DpScript.allowBreaks(word),
            style: style(colour ?? tokens.color.ink),
            locale: const Locale('de', 'DE'),
          ),
        ],
      ),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      // Announced with its article, as accessibility-performance.md requires,
      // and without the soft hyphen a screen reader would otherwise voice.
      semanticsLabel: article == null ? word : '$article $word',
    );
  }
}
