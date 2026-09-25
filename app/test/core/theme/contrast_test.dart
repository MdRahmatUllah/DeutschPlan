import 'dart:math' as math;

import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// #163 · WCAG 2.2 AA over the token combinations the app draws: text at
/// 4.5:1 and, since #437, the progress track at 3:1 (1.4.11, non-text), in
/// Light, Dark and both Glass variants. Glass is checked on a
/// card over each aurora blob at its peak opacity — theming.md: "against the
/// brightest blob it can overlay" — so a failure is fixed in the tokens, never
/// per screen.
void main() {
  double channel(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  double ratio(Color a, Color b) {
    final (x, y) = (luminance(a), luminance(b));
    return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
  }

  final themes = <String, DpTokens>{
    'light': DpTokens.light(),
    'dark': DpTokens.dark(),
    'glass': DpTokens.glass(),
    'glass dark': DpTokens.glassDark(),
  };

  for (final MapEntry(key: name, value: t) in themes.entries) {
    final c = t.color;
    final s = t.surface;

    /// What a surface is drawn over: the paper, or under glass the backdrop
    /// with each blob at its peak.
    final backdrops = <String, Color>{
      if (!t.isGlass) 'paper': s.paper,
      if (t.isGlass)
        for (final (blob, colour) in <(String, Color)>[
          ('Lagoon', c.primary),
          ('Sun', c.accent),
          ('Raspberry', c.die),
          ('Cobalt', c.der),
        ])
          'the $blob blob': Color.alphaBlend(
            colour.withValues(alpha: s.auroraOpacity),
            s.paper,
          ),
    };

    test('#163 $name: every text colour on every card', () {
      final failures = <String>[];
      final colours = <String, Color>{
        'ink': c.ink,
        'textSecondary': c.textSecondary,
        'link': c.link,
        'derText': c.derText,
        'dieText': c.dieText,
        'dasText': c.dasText,
        'correctText': c.correctText,
        'almostText': c.almostText,
        'wrongText': c.wrongText,
      };
      for (final MapEntry(key: where, value: backdrop) in backdrops.entries) {
        final grounds = <String, Color>{
          if (!t.isGlass) where: backdrop,
          'a card over $where': Color.alphaBlend(s.card, backdrop),
          'a strong card over $where': Color.alphaBlend(s.cardStrong, backdrop),
        };
        for (final MapEntry(key: ground, value: g) in grounds.entries) {
          for (final MapEntry(key: role, value: colour) in colours.entries) {
            final r = ratio(colour, g);
            if (r < 4.5) {
              failures.add('$role on $ground: ${r.toStringAsFixed(2)}');
            }
          }
        }
      }
      expect(failures, isEmpty);
    });

    test('#163 $name: primary and secondary text on the backdrop and muted '
        'chips', () {
      final failures = <String>[];
      for (final MapEntry(key: where, value: backdrop) in backdrops.entries) {
        for (final (ground, g) in <(String, Color)>[
          (where, backdrop),
          ('a muted chip over $where', Color.alphaBlend(s.muted, backdrop)),
        ]) {
          for (final (role, colour) in <(String, Color)>[
            ('ink', c.ink),
            ('textSecondary', c.textSecondary),
          ]) {
            final r = ratio(colour, g);
            if (r < 4.5) {
              failures.add('$role on $ground: ${r.toStringAsFixed(2)}');
            }
          }
        }
      }
      expect(failures, isEmpty);
    });

    test('#163 $name: a label on its fill (buttons, gender swatches, the '
        'rating bar, the snackbar)', () {
      final failures = <String>[];
      for (final (label, fg, bg) in <(String, Color, Color)>[
        ('onPrimary on primary', c.onPrimary, c.primary),
        ('onAccent on accent', c.onAccent, c.accent),
        ('onDer on der', c.onDer, c.der),
        ('onAccent on again', c.onAccent, c.again),
        ('onAccent on hard', c.onAccent, c.hard),
        ('onAccent on good', c.onAccent, c.good),
        ('onAccent on easy', c.onAccent, c.easy),
        ('onAccent on learning', c.onAccent, c.learning),
        ('inverseLink on ink', c.inverseLink, c.ink),
      ]) {
        final r = ratio(fg, bg);
        if (r < 4.5) {
          failures.add('$label: ${r.toStringAsFixed(2)}');
        }
      }
      expect(failures, isEmpty);
    });

    test('#437 $name: the M1 header, name and subtitle, on its Cobalt', () {
      // Cobalt solid on paper; under glass a Cobalt tint (DpSurface's 22 %)
      // over the backdrop, with the page's ink on it. The subtitle is this
      // colour itself, never a fainter one made on the screen.
      final failures = <String>[];
      for (final MapEntry(key: where, value: backdrop) in backdrops.entries) {
        final fill = t.isGlass
            ? Color.alphaBlend(c.der.withValues(alpha: 0.22), backdrop)
            : c.der;
        final r = ratio(t.isGlass ? c.ink : c.onDer, fill);
        if (r < 4.5) failures.add('over $where: ${r.toStringAsFixed(2)}');
      }
      expect(failures, isEmpty);
    });

    test('#437 $name: WCAG 1.4.11, the track at 3:1 wherever it is drawn '
        '(the ring, bars, a slider, the heat-map)', () {
      final failures = <String>[];
      final wheres = <String, Color>{
        ...backdrops,
        if (t.isGlass) 'the backdrop between blobs': s.paper,
      };
      for (final MapEntry(key: where, value: backdrop) in wheres.entries) {
        for (final (ground, g) in <(String, Color)>[
          (where, backdrop),
          ('a card over $where', Color.alphaBlend(s.card, backdrop)),
          (
            'a strong card over $where',
            Color.alphaBlend(s.cardStrong, backdrop),
          ),
        ]) {
          final r = ratio(Color.alphaBlend(s.track, g), g);
          if (r < 3) failures.add('track on $ground: ${r.toStringAsFixed(2)}');
        }
      }
      expect(failures, isEmpty);
    });
  }
}
