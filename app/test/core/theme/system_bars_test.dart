import 'dart:io';

import 'package:flutter/services.dart' show MethodCall, SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/theme/app_theme.dart';
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
      'lib/features/search/search_header.dart',
      'lib/features/onboarding/onboarding_shell.dart',
      'lib/features/exam/exam_results_screen.dart',
      'lib/features/exam/exam_runner_screen.dart',
      'lib/features/quiz/quiz_result_screen.dart',
      'lib/features/words/word_detail_screen.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        matches(RegExp(r'SgHeaderFill\(|barsOver\(')),
        reason: path,
      );
    }
  });

  // #1070, the review of #1074: Flutter sends a style only where it finds
  // one under the status bar, so a header's style outlived the header,
  // scrolled away or on the next screen. The page's own region takes over.
  testWidgets('#1070 a header scrolled away hands the status bar back to the '
      "page: dark icons for Learn's yellow, then light over the dark paper", (
    tester,
  ) async {
    final sent = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'SystemChrome.setSystemUIOverlayStyle') {
          final style = call.arguments as Map<Object?, Object?>;
          sent.add('${style['statusBarIconBrightness']}');
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
    final tokens = SgTokens.dark();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: AdaptiveScaffold(
          body: ListView(
            controller: scroll,
            padding: EdgeInsets.zero,
            children: <Widget>[
              SgHeaderFill(
                color: tokens.color.accent,
                child: const SizedBox(height: 200),
              ),
              const SizedBox(height: 3000),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(sent.last, 'Brightness.dark', reason: 'the yellow header');

    scroll.jumpTo(1000);
    await tester.pump();
    await tester.pump();
    expect(sent.last, 'Brightness.light', reason: 'the dark paper');
  });
}
