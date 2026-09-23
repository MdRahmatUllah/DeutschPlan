// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/features/today/today_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/today_fixtures.dart';
import 'golden_harness.dart';

/// T1 · Today, all done — #96. The TodayDone artboard's own day.
void main() {
  goldenTest(
    'today_done',
    builder: (context) => ProviderScope(
      overrides: todayStub(artboardDone()),
      child: const TodayScreen(),
    ),
  );
}
