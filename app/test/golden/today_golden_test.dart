// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sogda/features/today/today_screen.dart';

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
  // #1078: in Polish, as a Polish phone's first run shows it.
  goldenTest(
    'today_pl',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    textAudit: false,
    locale: const Locale('pl'),
    builder: (context) =>
        ProviderScope(overrides: todayStub(), child: const TodayScreen()),
  );
  // #1079: in Russian: Cyrillic drawn, not boxes.
  goldenTest(
    'today_ru',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    textAudit: false,
    locale: const Locale('ru'),
    builder: (context) =>
        ProviderScope(overrides: todayStub(), child: const TodayScreen()),
  );
  // #1280: 5 of the 12 new words from documents, named apart from the
  // course's category; the audit's 150/200 % passes in every language take
  // the longer line.
  goldenTest(
    'today_documents',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    builder: (context) => ProviderScope(
      overrides: todayStub(artboardToday(newTotal: 12, newFromDocuments: 5)),
      child: const TodayScreen(),
    ),
  );
  // #165: at 200 % text.
  goldenTest(
    'today_200',
    builder: (context) =>
        ProviderScope(overrides: todayStub(), child: const TodayScreen()),
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    textScale: 2,
    textAudit: false,
  );
}
