// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/features/me/me_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/me_fixtures.dart';
import 'golden_harness.dart';

/// M1 · Me — #144. The artboard's learner: Maruf on a 12-day streak, 1,248
/// words done, two days behind, A1.1 and A1.2 passed and A2.1 current.
void main() {
  goldenTest(
    'me',
    builder: (context) =>
        ProviderScope(overrides: meStub(), child: const MeScreen()),
  );
}
