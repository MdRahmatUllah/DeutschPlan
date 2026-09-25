// #167: the frame and search budgets (accessibility-performance.md), measured
// in a profile build on the emulator. Run by `tools/perf.py frames`, which
// uninstalls the app first:
//
//   flutter drive --profile --no-dds --keep-app-running \
//       --driver=test_driver/perf_driver.dart \
//       --target=integration_test/perf_test.dart -d emulator-5558
//
// Each measurement goes into the binding's `reportData`, which the driver
// writes to build/integration_response_data.json for perf.py to read.

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/glass_capability.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/features/study/study_screen.dart';
import 'package:deutschplan/features/today/today_components.dart';
import 'package:deutschplan/features/today/today_view.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart' as app;
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'smoke.dart';

/// The cards rated while the frames are watched. Day 1 has seven new words
/// (`daily_new`'s default), so five never reach T3.
const int _cards = 5;

/// What is typed into R1, a keystroke at a time: single letters, prefixes,
/// an umlaut and an ß, a phrase, English, and Bangla.
const List<String> _typed = <String>[
  'Haus',
  'schön',
  'Straße',
  'guten Morgen',
  'house',
  'বাড়ি',
];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Every frame the app asks for is drawn, as on a phone. The default draws
  // only the frames the test pumps, which would time the test, not the app.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'Y06: the card transition, the glass word list and search, measured',
    timeout: const Timeout(Duration(minutes: 10)),
    (tester) async {
      final l10n = await launch(tester);
      expect(
        await startsInSetup(tester, l10n),
        isTrue,
        reason: 'a fresh install: run tools/perf.py frames, which uninstalls',
      );
      // Blur stays on for the whole run. The emulator misses frames while it
      // warms up, and the watchdog would turn glass opaque for the session:
      // the list would then be measured without the BackdropFilter it is
      // budgeted for, or with it, depending on the run.
      final glass = tester
          .widget<GlassCapabilityScope>(find.byType(GlassCapabilityScope))
          .notifier!;
      glass.stopFrameWatchdog();
      await onboard(tester, l10n);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(app.DeutschPlanApp)),
        listen: false,
      );
      final data = binding.reportData ??= <String, dynamic>{};

      // (a) T2: each card turned over and rated Good, and the next one in.
      await tapOn(
        tester,
        find.byWidgetPredicate(
          (widget) =>
              widget is PrimaryActionBar && widget.action == TodayAction.start,
        ),
      );
      await binding.watchPerformance(
        () => _rateCards(tester, l10n),
        reportKey: 'card',
      );

      // (b) L2's word list under glass, flung down and back up.
      await container
          .read(themeProvider.notifier)
          .choose(ThemeModeSetting.glass);
      GoRouter.of(tester.element(find.byType(StudyScreen)))
          .go(const LearnStepRoute(code: 'A1.1').location);
      final list = find.byKey(const PageStorageKey<String>('step-words-A1.1'));
      await pumpUntil(tester, list);
      await tester.pump(const Duration(seconds: 2));
      data['glass'] = <String, Object>{
        'blur': glass.blurAllowed,
        'reasons': <String>[for (final reason in glass.reasons) reason.name],
      };
      await binding.watchPerformance(() async {
        for (var fling = 0; fling < 8; fling++) {
          await tester.fling(list, Offset(0, fling < 4 ? -600 : 600), 3000);
          await tester.pump(const Duration(milliseconds: 1500));
        }
      }, reportKey: 'list');

      // (c) R1's own call against the real content.db, three times per
      // keystroke: perf.py takes each one's median, so one slow run (the
      // emulator shares its host) is not the keystroke's time. The very
      // first is the cold one, reported on its own.
      final search = container.read(searchRepositoryProvider);
      final timings = <List<Object>>[];
      for (final word in _typed) {
        final runes = word.runes.toList();
        for (var length = 1; length <= runes.length; length++) {
          final query = String.fromCharCodes(runes.take(length));
          final runs = <double>[];
          for (var run = 0; run < 3; run++) {
            final clock = Stopwatch()..start();
            await search.search(query);
            runs.add(clock.elapsedMicroseconds / 1000);
          }
          timings.add(<Object>[query, runs]);
        }
      }
      data['search'] = <String, Object>{'keystrokes': timings};
    },
  );
}

/// T2, face down: *Show meaning*; face up: *Good* — disabled until the
/// intervals load, so a tap that did nothing is simply tried again. A card
/// counts as rated when the next one shows its face.
Future<void> _rateCards(WidgetTester tester, AppLocalizations l10n) async {
  final face = find.text(l10n.studyShowMeaning);
  final good = find.text(l10n.ratingGood);
  var rated = 0;
  var turned = false;
  final clock = Stopwatch()..start();
  while (true) {
    if (clock.elapsed > const Duration(minutes: 2)) {
      throw TestFailure('Rated $rated of $_cards cards in 2 minutes');
    }
    if (face.evaluate().isNotEmpty) {
      if (turned) rated++;
      turned = false;
      if (rated == _cards) break;
      await tester.tap(face.first, warnIfMissed: false);
    } else if (good.evaluate().isNotEmpty) {
      turned = true;
      await tester.tap(good.first, warnIfMissed: false);
    }
    await tester.pump(const Duration(milliseconds: 400));
  }
}
