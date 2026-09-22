import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart';
import 'package:deutschplan/router/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp, ThemeMode;

void main() {
  testWidgets('the app boots into the shell with Today showing', (
    tester,
  ) async {
    await tester.pumpWidget(const DeutschPlanApp(mode: DpMode.light));
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(supportedLocales.first);
    expect(find.byType(AppShell), findsOneWidget);
    expect(find.text(l10n.tabToday), findsWidgets);
    expect(find.text('T1'), findsOneWidget, reason: 'Today is the first tab');
  });

  testWidgets('the resolved mode is what the app renders', (tester) async {
    // bootstrap() resolves `theme_mode` against the platform before the first
    // frame; if the app ignored it, the learner would see a frame of the
    // wrong theme every launch.
    for (final pair in const <(DpMode, ThemeMode)>[
      (DpMode.light, ThemeMode.light),
      (DpMode.dark, ThemeMode.dark),
    ]) {
      await tester.pumpWidget(DeutschPlanApp(mode: pair.$1));
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, pair.$2, reason: '${pair.$1}');
    }
  });

  testWidgets('following the system keeps following it', (tester) async {
    // `theme_mode = system` resolves to a concrete mode for the first frame.
    // Passing that straight to MaterialApp would pin the app to whatever the
    // phone was on at launch.
    await tester.pumpWidget(
      const DeutschPlanApp(mode: DpMode.dark, followsPlatform: true),
    );
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
  });

  test('English leads supportedLocales so it is the fallback locale', () {
    expect(supportedLocales.first.languageCode, 'en');
    expect(
      supportedLocales.map((l) => l.languageCode).toSet(),
      AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet(),
      reason: 'a language was added to lib/l10n/ without adding it to supportedLocales',
    );
  });
}
