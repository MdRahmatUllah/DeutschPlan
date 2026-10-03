// The ProviderScopes below are the only ones in the tree — the harness has
// none — so there is no parent scope for the lint's dependency list to
// describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:flutter/rendering.dart' show BackdropFilterLayer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/features/learn/learn_screen.dart';
import 'package:sogda/features/me/me_screen.dart';
import 'package:sogda/features/today/today_screen.dart';

import '../../features/me_fixtures.dart';
import '../../features/today_fixtures.dart';
import '../../golden/golden_harness.dart';

/// #709: L1, Today and Me put 6 to 19 glass panels on screen, each blurring
/// the backdrop: far over the budget of three. A panel in the screen's list
/// draws over the aurora with no blur of its own now; what keeps one is named
/// in `SgSurface`'s blur budget.
void main() {
  /// The blurs the engine draws for the frame on screen.
  int blurs(WidgetTester tester) =>
      tester.layers.whereType<BackdropFilterLayer>().length;

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
    testWidgets('#709 $name under glass keeps to the budget of three blurs', (
      tester,
    ) async {
      await tester.pumpGolden(
        builder: screen,
        mode: GoldenMode.glass,
        device: GoldenDevice.phone,
      );
      // L1 drew 19 on a phone, Today 7 and Me 6; none now, as their panels
      // are all in their lists (the shell's tab bar keeps its own).
      expect(blurs(tester), lessThanOrEqualTo(3));
    });
  }
}
