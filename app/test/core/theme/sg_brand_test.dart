import 'dart:io';

import 'package:sogda/core/theme/sg_brand.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The brand kit's colours (#602): the kit's own table, and the palette the
/// app's screens were drawn in, so the mark and the screens around it agree.
void main() {
  test('FR-S1-01 #602 the brand colours are the kit README table', () {
    // "| Lagoon (ground) | #00C2B2 |", one row per colour.
    final table = <String, Color>{
      for (final match
          in RegExp(
            r'^\| (\w+) \([^)]*\) \| #([0-9A-Fa-f]{6}) \|',
            multiLine: true,
          ).allMatches(
            File('../docs/sogda-brand-kit/README.md').readAsStringSync(),
          ))
        match.group(1)!: Color(int.parse('ff${match.group(2)}', radix: 16)),
    };

    expect(table, <String, Color>{
      'Lagoon': SgBrand.lagoon,
      'Sun': SgBrand.sun,
      'Ink': SgBrand.ink,
      'Paper': SgBrand.paper,
      'Night': SgBrand.night,
    });
  });

  test('FR-S1-01 #602 and they are the light palette and the two papers', () {
    expect(SgBrand.lagoon, SgPalette.light.primary);
    expect(SgBrand.sun, SgPalette.light.accent);
    expect(SgBrand.ink, SgPalette.light.ink);
    expect(SgBrand.paper, SgSurfaceTokens.light.paper);
    expect(SgBrand.night, SgSurfaceTokens.dark.paper);
  });
}
