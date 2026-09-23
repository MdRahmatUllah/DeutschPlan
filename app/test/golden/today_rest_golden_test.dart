// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/features/today/today_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/today_fixtures.dart';
import 'golden_harness.dart';

/// T1 · Today, rest day — #97. The TodayRest artboard's own Sunday.
void main() {
  goldenTest(
    'today_rest',
    builder: (context) => ProviderScope(
      overrides: todayStub(artboardRest()),
      child: const TodayScreen(),
    ),
  );
}
