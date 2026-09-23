// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/features/today/today_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/today_fixtures.dart';
import 'golden_harness.dart';

/// T1 · Today in progress — #95.
///
/// The artboard's own day: 12 of 20, A2.1 on day 34, a backlog of 14 from
/// Tuesday to Wednesday, and Konjunktiv II this week.
void main() {
  goldenTest(
    'today',
    builder: (context) =>
        ProviderScope(overrides: todayStub(), child: const TodayScreen()),
  );
}
