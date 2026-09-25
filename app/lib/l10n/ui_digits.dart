import 'package:deutschplan/l10n/generated/app_localizations.dart';

final RegExp _latinDigit = RegExp('[0-9]');

/// Numbers in the UI language's own digits (#425).
extension UiDigits on AppLocalizations {
  /// [value] with Bangla's ০–৯ in the Bangla UI, as the ARB's number
  /// placeholders are formatted there; as it is otherwise. For a number the
  /// code writes itself — a score, a timer, a stepper's value. UI text only:
  /// German content keeps its digits.
  String digits(Object value) {
    final text = '$value';
    // The language, not the tag: a `bn_BD` would be Bangla too.
    if (localeName.split(RegExp('[_-]')).first != 'bn') return text;
    return text.replaceAllMapped(
      _latinDigit,
      (digit) => String.fromCharCode(0x09E6 + digit[0]!.codeUnitAt(0) - 0x30),
    );
  }
}
