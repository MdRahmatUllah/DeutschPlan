// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/features/learn/learn_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/today_fixtures.dart';
import 'golden_harness.dart';

/// L1 · Learn — #112. The artboard's course: A1.1 and A1.2 passed, A2.1
/// current with eight cards left today, A2.2 on not started.
void main() {
  goldenTest(
    'learn',
    builder: (context) => ProviderScope(
      overrides: todayStub(artboardToday(reviseDone: 7)),
      child: const LearnScreen(),
    ),
  );
}
