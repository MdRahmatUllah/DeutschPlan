@TestOn('vm')
library;

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/domain/placement.dart';
import 'package:deutschplan/features/onboarding/onboarding_start_page.dart';
import 'package:deutschplan/features/onboarding/placement_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/services/tts/tts_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/placement_test.dart' show wordFor;

/// S3 · the placement check on screen — #93. The walk itself is
/// `placement_test.dart`'s; this is the screen around it.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  const steps = <String>[
    'A1.1', 'A1.2', 'A2.1', 'A2.2', 'B1.1', 'B1.2', //
    'B2.1', 'B2.2', 'C1.1', 'C1.2', 'C2.1', 'C2.2',
  ];

  late _PoolDao dao;
  late List<String?> done;
  late AppDatabase db;

  Future<void> pump(
    WidgetTester tester, {
    DpMode mode = DpMode.light,
    double textScale = 1,
  }) async {
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    db = AppDatabase.memory();
    addTearDown(db.close);
    dao = _PoolDao(db);
    done = <String?>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          contentDaoProvider.overrideWithValue(dao),
          courseStepsProvider.overrideWith(
            (ref) async => <CourseStep>[
              for (final code in steps)
                (code: code, levelCode: code.split('.').first, wordCount: 12),
            ],
          ),
          systemTtsProvider.overrideWithValue(_SilentTts()),
        ],
        child: MaterialApp(
          theme: switch (mode) {
            DpMode.light => AppTheme.light(),
            DpMode.dark => AppTheme.dark(),
            DpMode.glass => AppTheme.glass(),
          },
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: PlacementScreen(seed: 11, onDone: done.add),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  Finder options() => find.descendant(
    of: find.byType(SingleChildScrollView),
    matching: find.byType(DpSurface),
  );

  /// Picks the right option when [right], a wrong one otherwise, and moves
  /// on — the screen's own answer, read off the item it drew.
  Future<void> answer(WidgetTester tester, {required bool right}) async {
    final item = tester
        .state<PlacementScreenState>(find.byType(PlacementScreen))
        .currentItem!;
    final index = right ? item.answer : (item.answer + 1) % item.options.length;

    await tester.tap(options().at(index));
    await tester.pump();
    await tester.tap(find.widgetWithText(DpButton, l10n.placementNext));
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  group('the check', () {
    testWidgets('starts at A1.1, question 1 of 20', (tester) async {
      await pump(tester);

      expect(find.text(l10n.placementQuestionOf(1, 20)), findsOneWidget);
      expect(dao.asked.first, 'A1.1');
      expect(options(), findsWidgets);
    });

    testWidgets('Next waits for an answer', (tester) async {
      await pump(tester);

      final next = find.widgetWithText(DpButton, l10n.placementNext);
      expect(tester.widget<DpButton>(next).onPressed, isNull);

      await tester.tap(options().first);
      await tester.pump();
      expect(tester.widget<DpButton>(next).onPressed, isNotNull);
    });

    testWidgets('FR-S3-01 two right move it up a step', (tester) async {
      await pump(tester);

      await answer(tester, right: true);
      await answer(tester, right: true);

      expect(find.text(l10n.placementQuestionOf(3, 20)), findsOneWidget);
      expect(dao.asked.last, 'A1.2');
    });

    testWidgets('and it ends with the step it settled on', (tester) async {
      // Six right climb to A2.2; then right, wrong, right hold it there for
      // three, and after the ninth the check stops.
      await pump(tester);
      for (final right in <bool>[
        true, true, true, true, true, true, true, false, true, //
      ]) {
        await answer(tester, right: right);
      }

      expect(done, <String?>['A2.2']);
    });

    testWidgets('FR-S3-02 each step is read once, however often it returns', (
      tester,
    ) async {
      await pump(tester);
      // Up to A1.2 and back down to A1.1.
      await answer(tester, right: true);
      await answer(tester, right: true);
      await answer(tester, right: false);
      await answer(tester, right: false);
      await answer(tester, right: true);

      expect(dao.asked.where((s) => s == 'A1.1'), hasLength(1));
    });
  });

  group('FR-S3-04 closing', () {
    testWidgets('hands back nothing, however far in', (tester) async {
      await pump(tester);
      await answer(tester, right: true);
      await answer(tester, right: true);

      await tester.tap(find.bySemanticsLabel(l10n.placementClose));
      await tester.pump();

      expect(done, <String?>[null]);
    });
  });

  group('FR-S3-03 nothing is written', () {
    testWidgets('word_state stays empty through a whole check', (tester) async {
      await pump(tester);
      for (final right in <bool>[true, true, false, true, false, false]) {
        await answer(tester, right: right);
      }

      final rows = await tester.runAsync(
        () =>
            db.customSelect('SELECT COUNT(*) AS n FROM word_state').getSingle(),
      );
      expect(rows!.read<int>('n'), 0);
    });
  });

  group('it is built from the design system', () {
    testWidgets('no Material chrome', (tester) async {
      await pump(tester);

      expect(find.byType(AdaptiveScaffold), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(RadioListTile<int>), findsNothing);
    });

    for (final mode in <DpMode>[DpMode.dark, DpMode.glass]) {
      testWidgets('and ${mode.name} renders it', (tester) async {
        await pump(tester, mode: mode);
        expect(options(), findsWidgets);
        // Glass has no paper of its own: without the aurora behind it the
        // screen is black, and every option still "renders".
        expect(
          find.byType(AuroraBackdrop),
          mode == DpMode.glass ? findsOneWidget : findsNothing,
        );
      });
    }
  });

  group('accessibility', () {
    testWidgets('the options are one group, and the picked one says so', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester);

      await tester.tap(options().first);
      await tester.pump();

      expect(
        tester.getSemantics(options().first),
        isSemantics(
          isSelected: true,
          isInMutuallyExclusiveGroup: true,
          isButton: true,
        ),
      );

      handle.dispose();
    });

    testWidgets('and it holds together at 200 % text', (tester) async {
      await pump(tester, textScale: 2);

      expect(tester.takeException(), isNull);
    });
  });
}

class _PoolDao extends ContentDao {
  _PoolDao(super.db);

  final List<String> asked = <String>[];

  @override
  Future<List<PlacementWord>> placementPool(String step) async {
    asked.add(step);
    return <PlacementWord>[for (var i = 0; i < 12; i++) wordFor(step, i)];
  }
}

class _SilentTts implements TtsEngine {
  @override
  Future<bool> speak(String text) async => true;

  @override
  Future<void> stop() async {}
}
