// #167: the frame and search budgets (accessibility-performance.md), measured
// in a profile build on the emulator. Run by `tools/perf.py frames`, which
// uninstalls the app first:
//
//   flutter drive --profile --no-dds --driver=test_driver/perf_driver.dart \
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

  /// Watches the frames of [action] under [key]. Inside, only the app asks
  /// for frames, as on a phone, and the test's pumps just wait; outside, the
  /// smoke helpers' pumps drive the frames as usual.
  Future<void> trace(String key, Future<void> Function() action) async {
    binding.framePolicy =
        LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
    try {
      await binding.watchPerformance(action, reportKey: key);
    } finally {
      binding.framePolicy =
          LiveTestWidgetsFlutterBindingFramePolicy.fadePointers;
    }
  }

  testWidgets(
    'Y06: the card transition, the glass word list and search, measured',
    timeout: const Timeout(Duration(minutes: 10)),
    (tester) async {
      final l10n = await launch(tester);
      // Blur stays on for the whole run, so the list is always measured with
      // the BackdropFilter it is budgeted for. The emulator misses frames,
      // and the watchdog would turn glass opaque for the session: it is
      // stopped the moment bootstrap hands it over.
      final scope = find.byType(GlassCapabilityScope);
      await pumpUntil(tester, scope, timeout: launchTimeout);
      final glass = tester.widget<GlassCapabilityScope>(scope).notifier!;
      glass.stopFrameWatchdog();
      expect(
        await startsInSetup(tester, l10n),
        isTrue,
        reason: 'a fresh install: run tools/perf.py frames, which uninstalls',
      );
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
      await trace('card', () => _rateCards(tester, l10n));

      // (b) L2's word list under glass, flung down and back up.
      final theme = container.read(themeProvider.notifier);
      await theme.choose(ThemeModeSetting.glass);
      const LearnStepRoute(code: 'A1.1')
          .go(tester.element(find.byType(StudyScreen)));
      final list = find.byKey(const PageStorageKey<String>('step-words-A1.1'));
      await pumpUntil(tester, list);
      await tester.pump(const Duration(seconds: 2));
      data['glass'] = <String, Object>{
        'blur': glass.blurAllowed,
        'reasons': <String>[for (final reason in glass.reasons) reason.name],
      };
      await trace('list', () async {
        for (var fling = 0; fling < 8; fling++) {
          await tester.fling(list, Offset(0, fling < 4 ? -600 : 600), 3000);
          await tester.pump(const Duration(milliseconds: 1500));
        }
      });

      // (c) R1's own call against the real content.db, at each keystroke:
      // the whole list three times over, not each query three times running,
      // which would time SQLite's page cache. perf.py takes each keystroke's
      // median; the very first run, the cold one, is reported on its own.
      final search = container.read(searchRepositoryProvider);
      final keystrokes = <String>[
        for (final word in _typed)
          for (var length = 1; length <= word.runes.length; length++)
            String.fromCharCodes(word.runes.take(length)),
      ];
      final runs = <List<double>>[for (final _ in keystrokes) <double>[]];
      for (var pass = 0; pass < 3; pass++) {
        for (var i = 0; i < keystrokes.length; i++) {
          final clock = Stopwatch()..start();
          await search.search(keystrokes[i]);
          runs[i].add(clock.elapsedMicroseconds / 1000);
        }
      }
      data['search'] = <String, Object>{
        'keystrokes': <List<Object>>[
          for (var i = 0; i < keystrokes.length; i++)
            <Object>[keystrokes[i], runs[i]],
        ],
      };

      // The default theme back, should the app outlive the run.
      await theme.choose(ThemeModeSetting.system);
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
