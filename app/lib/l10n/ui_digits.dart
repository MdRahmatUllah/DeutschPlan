import 'package:deutschplan/l10n/generated/app_localizations.dart';

/// Numbers in the UI language's own digits (#425).
extension UiDigits on AppLocalizations {
  /// [value] with Bangla's ০–৯ in the Bangla UI, as the ARB's number
  /// placeholders are formatted there; as it is otherwise. For a number the
  /// code writes itself — a score, a timer, a stepper's value. UI text only:
  /// German content keeps its digits.
  String digits(Object value) {
    final text = '$value';
    if (localeName != 'bn') return text;
    return text.replaceAllMapped(
      RegExp('[0-9]'),
      (digit) => String.fromCharCode(0x09E6 + digit[0]!.codeUnitAt(0) - 0x30),
    );
  }
}
