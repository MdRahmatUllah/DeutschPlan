import 'dart:io';

import 'package:deutschplan/core/components/dp_rating_bar.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/features/study/study_card.dart';
import 'package:deutschplan/features/study/study_motion.dart';
import 'package:deutschplan/features/study/study_screen.dart';
import 'package:deutschplan/features/study/study_session.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/router/routes.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../services/fake_tts.dart';

import '../db/content_fixture.dart';

/// T2 · swipe to rate, haptics and card motion — #106.
void main() {
  const today = '2026-09-21';
  const haus = ContentFixture.haus;
  const tuer = ContentFixture.tuer;

  late AppDatabase db;
  late SettingsRepository settings;
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  const args = SessionArgs(
    planDate: today,
    blocks: <SessionBlock>[
      SessionBlock(SessionBlockKind.newWords, <String>[haus, tuer]),
    ],
  );

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    bool swipe = false,
    bool reveal = true,
  }) async {
    await tester.runAsync(() async {
      db = AppDatabase.memory();
      final directory = Directory.systemTemp.createTempSync('dp_motion');
      final content = ContentFixture.write('${directory.path}/content.db');
      await db.customStatement(
        "ATTACH DATABASE '${ContentDao.attachPath(content.file)}' AS c",
      );
      await db.customStatement('''
INSERT INTO plan_items (plan_date, word_uid, kind, sublevel_code) VALUES
  ('$today', '$haus', 'new', 'A1.1'),
  ('$today', '$tuer', 'new', 'A1.1')
''');
      settings = SettingsRepository(db);
      await settings.load();
      await settings.write(SettingKeys.autoplayHeadword, false);
      await settings.write(SettingKeys.swipeToRate, swipe);
    });
    addTearDown(
      () => tester.runAsync(() async {
        await settings.dispose();
        await db.close();
      }),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWithValue(settings),
          ttsProvider.overrideWithValue(FakeTts()),
          clockProvider.overrideWithValue(() => DateTime(2026, 9, 21, 9)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          home: const StudyScreen(args: args),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(StudyScreen.bannerTime);
    await tester.pumpAndSettle();
    if (reveal) {
      await tester.tap(find.text(l10n.studyShowMeaning));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }
    return ProviderScope.containerOf(tester.element(find.byType(StudyScreen)));
  }

  Future<List<int>> ratings() async => <int>[
    for (final row
        in await db
            .customSelect('SELECT rating FROM review_log ORDER BY id')
            .get())
      row.read<int>('rating'),
  ];

  /// Drags the card, lets the write land, and settles.
  Future<void> drag(WidgetTester tester, Offset by) async {
    await tester.runAsync(() async {
      await tester.drag(find.byType(StudyWordCard), by);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
  }

  String? current(ProviderContainer container) =>
      container.read(studySessionProvider(args)).value?.current?.uid;

  group('FR-T2-08 swipe to rate', () {
    testWidgets('off by default: a swipe does nothing', (tester) async {
      final container = await pump(tester);
      await drag(tester, const Offset(-300, 0));
      expect(await tester.runAsync(ratings), isEmpty);
      expect(current(container), haus);
    });

    testWidgets('on: left is Again', (tester) async {
      final container = await pump(tester, swipe: true);
      await drag(tester, const Offset(-300, 0));
      expect(await tester.runAsync(ratings), <int>[1]);
      expect(current(container), tuer);
    });

    testWidgets('right is Good', (tester) async {
      final container = await pump(tester, swipe: true);
      await drag(tester, const Offset(300, 0));
      expect(await tester.runAsync(ratings), <int>[3]);
      expect(current(container), tuer);
    });

    testWidgets('a rated card leaves from where the finger let go', (
      tester,
    ) async {
      await pump(tester, swipe: true);
      await tester.runAsync(() async {
        await tester.drag(find.byType(StudyWordCard), const Offset(-300, 0));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      // The swiped card, on its way out: still where it was dragged to.
      final swiped = find.ancestor(
        of: find.text('das Haus', findRichText: true),
        matching: find.byType(StudySwipeToRate),
      );
      final held = tester.widget<Transform>(
        find.descendant(of: swiped, matching: find.byType(Transform)).first,
      );
      expect(held.transform.getTranslation().x, lessThan(-200));
      await tester.pumpAndSettle();
    });

    testWidgets('a short drag springs back and rates nothing', (tester) async {
      final container = await pump(tester, swipe: true);
      await drag(tester, const Offset(-40, 0));
      expect(await tester.runAsync(ratings), isEmpty);
      expect(current(container), haus);
      final shift = tester.widget<Transform>(
        find
            .descendant(
              of: find.byType(StudySwipeToRate),
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(shift.transform.getTranslation().x, 0);
    });

    testWidgets('#164 under reduce motion a short drag is back at once', (
      tester,
    ) async {
      await pump(tester, swipe: true);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pump();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(StudyWordCard)),
      );
      await gesture.moveBy(const Offset(-20, 0));
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      final shift = tester.widget<Transform>(
        find
            .descendant(
              of: find.byType(StudySwipeToRate),
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(shift.transform.getTranslation().x, 0, reason: 'no spring');
    });

    testWidgets('a fling counts, however short', (tester) async {
      final container = await pump(tester, swipe: true);
      await tester.runAsync(() async {
        await tester.fling(
          find.byType(StudyWordCard),
          const Offset(60, 0),
          1500,
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(await tester.runAsync(ratings), <int>[3]);
      expect(current(container), tuer);
    });

    testWidgets('face down, a swipe does nothing', (tester) async {
      final container = await pump(tester, swipe: true, reveal: false);
      await drag(tester, const Offset(-300, 0));
      expect(await tester.runAsync(ratings), isEmpty);
      expect(current(container), haus);
    });

    testWidgets('every swipe keeps its button: the bar stays', (tester) async {
      await pump(tester, swipe: true);
      expect(find.byType(DpRatingBar), findsOneWidget);
    });
  });

  group('haptics', () {
    late List<String> felt;

    setUp(() => felt = <String>[]);

    void listen(WidgetTester tester) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            felt.add(call.arguments as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
    }

    testWidgets('light on a rating', (tester) async {
      await pump(tester);
      listen(tester);
      await tester.runAsync(() async {
        await tester.tap(find.text(l10n.ratingGood));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(felt, <String>['HapticFeedbackType.lightImpact']);
    });

    testWidgets('medium on Again', (tester) async {
      await pump(tester);
      listen(tester);
      await tester.runAsync(() async {
        await tester.tap(find.text(l10n.ratingAgain));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(felt, <String>['HapticFeedbackType.mediumImpact']);
    });

    testWidgets('and a swipe feels the same as its button', (tester) async {
      await pump(tester, swipe: true);
      listen(tester);
      await drag(tester, const Offset(-300, 0));
      expect(felt, <String>['HapticFeedbackType.mediumImpact']);
    });
  });

  group('the card motion', () {
    /// Where [card] is drawn, mid-transition: the offset its motion adds.
    Offset shift(WidgetTester tester, Finder card) {
      final transform = tester.widget<Transform>(
        find.ancestor(of: card, matching: find.byType(Transform)).last,
      );
      final t = transform.transform.getTranslation();
      return Offset(t.x, t.y);
    }

    Finder word(String german) => find.ancestor(
      of: find.text(german, findRichText: true),
      matching: find.byType(StudyWordCard),
    );

    Future<void> rateMidway(WidgetTester tester, String rating) async {
      await tester.runAsync(() async {
        await tester.tap(find.text(rating));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('Again slides the card left', (tester) async {
      await pump(tester);
      await rateMidway(tester, l10n.ratingAgain);
      final out = shift(tester, word('das Haus'));
      expect(out.dx, lessThan(0));
      expect(out.dy, 0);
      await tester.pumpAndSettle();
    });

    testWidgets('the others lift it up', (tester) async {
      await pump(tester);
      await rateMidway(tester, l10n.ratingEasy);
      final out = shift(tester, word('das Haus'));
      expect(out.dx, 0);
      expect(out.dy, lessThan(0));
      await tester.pumpAndSettle();
    });

    testWidgets('and the next card rises from 16 px below', (tester) async {
      await pump(tester);
      await rateMidway(tester, l10n.ratingGood);
      final rising = shift(tester, word('die Tür'));
      expect(rising.dx, 0);
      // study-session.md: "the next card rises from 16 px below".
      expect(rising.dy, inExclusiveRange(0, 16));
      expect(StudyCardMotion.rise, 16);
      await tester.pumpAndSettle();
      expect(word('das Haus'), findsNothing);
      expect(shift(tester, word('die Tür')).dy, 0);
    });

    testWidgets('reduced motion: a cross-fade, nothing moves', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pump(tester);
      await rateMidway(tester, l10n.ratingAgain);
      expect(
        find.descendant(
          of: find.byType(StudyCardMotion),
          matching: find.byType(FadeTransition),
        ),
        findsWidgets,
      );
      // The framework all but skips the switch when motion is reduced; the
      // card that comes does not rise.
      expect(shift(tester, word('die Tür')), Offset.zero);
      await tester.pumpAndSettle();
    });
  });

  test('the database writes off the UI isolate, by construction', () {
    // accessibility-performance.md: "DB write off the UI isolate". The real
    // database is opened through drift_flutter's background isolate.
    final source = File('lib/data/db/app_database.dart').readAsStringSync();
    final open = source.substring(source.indexOf('AppDatabase.open('));
    expect(open.substring(0, open.indexOf(';')), contains('driftDatabase('));
  });
}
