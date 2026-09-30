// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Scrollable;
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/data/repositories/course_meanings.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/features/learn/step_detail_screen.dart';
import 'package:sogda/router/routes.dart';

import '../features/settings_fixtures.dart';
import '../features/today_fixtures.dart';
import 'golden_harness.dart';

/// L7 · Custom quiz — #122. The QuizSetup artboard's sheet over L2's Quiz
/// tab: DE → EN, 20 questions, this step's learned words, timer off.
void main() {
  Future<void> openCustom(WidgetTester tester) async {
    // At large text the tiles stack, and Custom is below the fold, not yet
    // built (#165). Only then: scrollUntilVisible ends in ensureVisible,
    // which would move the page at 100 % too.
    if (find.text(tester.l10n.quizCustom).hitTestable().evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        find.text(tester.l10n.quizCustom),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text(tester.l10n.quizCustom));
    await tester.pumpAndSettle();
  }

  goldenTest(
    'quiz_custom',
    builder: (context) => ProviderScope(
      overrides: todayStub(),
      child: const StepDetailScreen(code: 'A2.1', tab: StepTab.quiz),
    ),
    act: openCustom,
  );

  // #1120: a Russian learner who reads English second: DE → Русский, DE →
  // EN and Русский → DE.
  goldenTest(
    'quiz_custom_ru_meanings',
    builder: (context) => ProviderScope(
      overrides: <Override>[
        ...todayStub(),
        courseLanguagesProvider.overrideWith(
          (ref) async => const <CourseLanguageName>[
            ...baseLanguages,
            (code: 'ru', ownName: 'Русский'),
          ],
        ),
      ],
      child: const StepDetailScreen(code: 'A2.1', tab: StepTab.quiz),
    ),
    act: (tester) async {
      (ProviderScope.containerOf(tester.element(find.byType(StepDetailScreen)))
                .read(settingsSourceProvider)
            as StubSettings)
        ..put(SettingKeys.meaningPrimary, 'ru')
        ..put(SettingKeys.meaningSecondary, 'en');
      await openCustom(tester);
    },
  );

  // iOS: the sheet slides up as a Cupertino popup.
  goldenTest(
    'quiz_custom_ios',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
    builder: (context) => ProviderScope(
      overrides: todayStub(),
      child: const StepDetailScreen(code: 'A2.1', tab: StepTab.quiz),
    ),
    act: openCustom,
  );
}
