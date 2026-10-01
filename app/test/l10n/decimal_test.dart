import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/features/me/model_manager_screen.dart';
import 'package:sogda/features/quiz/quiz_names.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/l10n/ui_digits.dart';

/// #1197: a decimal the code writes takes the UI language's separator, a
/// comma in Polish and Russian, in the language's digits.
void main() {
  AppLocalizations l10n(String code) => lookupAppLocalizations(Locale(code));

  test('#1197 decimal: a comma in pl and ru, a full stop in en and bn', () {
    final expected = <String, List<String>>{
      'en': ['1.0', '0.75', '2.3'],
      'bn': ['১.০', '০.৭৫', '২.৩'],
      'pl': ['1,0', '0,75', '2,3'],
      'ru': ['1,0', '0,75', '2,3'],
    };
    for (final MapEntry(key: code, value: want) in expected.entries) {
      final t = l10n(code);
      expect(
        [t.decimal(1, 1), t.decimal(0.75, 2), t.decimal(2.25 + 0.04, 1)],
        want,
        reason: code,
      );
    }
  });

  test('BR-ANS-04 FR-L13-01 #1197 a half point reads in the UI language', () {
    final expected = <String, List<String>>{
      'en': ['15.5', '16'],
      'bn': ['১৫.৫', '১৬'],
      'pl': ['15,5', '16'],
      'ru': ['15,5', '16'],
    };
    for (final MapEntry(key: code, value: want) in expected.entries) {
      final t = l10n(code);
      expect([quizPoints(t, 15.5), quizPoints(t, 16)], want, reason: code);
    }
  });

  test('FR-M4-01 #1197 a model size in gigabytes takes the separator, and a '
      'whole one none', () {
    expect(modelSize(l10n('pl'), 1100000000), contains('1,1'));
    expect(modelSize(l10n('ru'), 1100000000), contains('1,1'));
    expect(modelSize(l10n('en'), 1100000000), contains('1.1'));
    expect(modelSize(l10n('bn'), 1100000000), contains('১.১'));
    expect(modelSize(l10n('pl'), 64000000000), isNot(contains(',')));
    expect(modelSize(l10n('en'), 1960000000), contains('2 '));
  });
}
