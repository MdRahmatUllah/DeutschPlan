import 'dart:io';

import 'dart:ui' show Brightness, Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/theme/system_bars.dart';

void main() {
  // #1070: the status bar's icons follow a coloured header's fill, where
  // the last app bar's white stayed on Learn's yellow, T6's lime and S1's
  // cyan in dark mode.
  test('#1070 dark icons on the light fills, light icons on the dark ones, '
      'in light and dark', () {
    for (final tokens in <SgTokens>[SgTokens.light(), SgTokens.dark()]) {
      final c = tokens.color;
      for (final fill in <Color>[c.accent, c.easy, c.primary]) {
        expect(
          barsOver(fill).statusBarIconBrightness,
          Brightness.dark,
          reason: '$fill',
        );
        expect(barsOver(fill).statusBarBrightness, Brightness.light);
      }
    }
    expect(
      barsOver(SgTokens.light().color.der).statusBarIconBrightness,
      Brightness.light,
      reason: "Me's Cobalt in light: white icons",
    );
    // The bars stay transparent, their scrim off, as ever.
    expect(barsOver(SgTokens.light().color.accent).statusBarColor, isNotNull);
    expect(
      barsOver(SgTokens.light().color.accent).systemStatusBarContrastEnforced,
      isFalse,
    );
  });

  test('#1070 every screen drawing a coloured fill under the status bar sets '
      'its icons for it', () {
    for (final path in <String>[
      'lib/features/today/today_components.dart',
      'lib/features/me/me_screen.dart',
      'lib/features/learn/learn_screen.dart',
      'lib/features/learn/step_detail_screen.dart',
      'lib/features/learn/grammar_topic_screen.dart',
      'lib/features/learn/grammar_practice_screen.dart',
      'lib/features/search/search_screen.dart',
      'lib/features/search/add_word_screen.dart',
      'lib/features/onboarding/onboarding_shell.dart',
      'lib/features/exam/exam_results_screen.dart',
      'lib/features/exam/exam_runner_screen.dart',
      'lib/features/quiz/quiz_result_screen.dart',
      'lib/features/day_complete/day_complete_screen.dart',
      'lib/features/splash/splash_screen.dart',
      'lib/features/words/word_detail_screen.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        matches(RegExp(r'SgHeaderFill\(|barsOver\(')),
        reason: path,
      );
    }
  });
}
