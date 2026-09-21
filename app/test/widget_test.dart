import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the app boots and renders localised copy', (tester) async {
    await tester.pumpWidget(const DeutschPlanApp());
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(supportedLocales.first);
    expect(find.text(l10n.loadingCourse), findsOneWidget);
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
