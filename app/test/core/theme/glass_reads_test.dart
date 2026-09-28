// The ProviderScopes below are the only ones in the tree — the harness has
// none — so there is no parent scope for the lint's dependency list to
// describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:sogda/features/learn/learn_screen.dart';
import 'package:sogda/features/me/me_screen.dart';
import 'package:sogda/features/today/today_screen.dart';
import 'package:flutter/rendering.dart' show BackdropFilterLayer, BackdropKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/me_fixtures.dart';
import '../../features/today_fixtures.dart';
import '../../golden/golden_harness.dart';

/// #709: L1, Today and Me put 6 to 12 glass panels on screen, and each read
/// the backdrop on its own. The panels in a screen's list share one read now;
/// what keeps a read of its own is named in `SgSurface`'s blur budget.
void main() {
  /// How many times the engine reads the backdrop for the frame on screen:
  /// once per shared key, and once for each blur that has none.
  (int blurs, int reads) backdrop(WidgetTester tester) {
    final keys = <BackdropKey?>[
      for (final layer in tester.layers)
        if (layer is BackdropFilterLayer) layer.backdropKey,
    ];
    return (
      keys.length,
      keys.where((key) => key == null).length + keys.nonNulls.toSet().length,
    );
  }

  for (final (name, screen) in <(String, WidgetBuilder)>[
    (
      'L1',
      (_) => ProviderScope(
        overrides: todayStub(artboardToday(reviseDone: 7)),
        child: const LearnScreen(),
      ),
    ),
    (
      'Today',
      (_) => ProviderScope(overrides: todayStub(), child: const TodayScreen()),
    ),
    ('Me', (_) => ProviderScope(overrides: meStub(), child: const MeScreen())),
  ]) {
    testWidgets('#709: $name under glass reads its backdrop once', (
      tester,
    ) async {
      await tester.pumpGolden(
        builder: screen,
        mode: GoldenMode.glass,
        device: GoldenDevice.phone,
      );
      final (blurs, reads) = backdrop(tester);
      // L1 has 19 on a phone, Today 7 and Me 6.
      expect(blurs, greaterThan(5), reason: 'the panels still blur');
      expect(reads, 1, reason: '$blurs panels');
    });
  }
}
