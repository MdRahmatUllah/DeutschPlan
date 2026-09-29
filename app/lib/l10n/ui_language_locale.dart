import 'dart:ui' show Locale;

import 'package:sogda/data/repositories/setting_keys.dart';

/// The locale for each app language. `UiLanguage` lives in the data layer,
/// which knows nothing of Flutter, so the mapping lives here: the app's and
/// a background task's (#158) alike.
extension UiLanguageLocale on UiLanguage {
  Locale get locale => switch (this) {
    UiLanguage.english => const Locale('en'),
    UiLanguage.bangla => const Locale('bn'),
    UiLanguage.polish => const Locale('pl'),
    UiLanguage.russian => const Locale('ru'),
  };

  /// The language's name in itself, the same in every app language (#1078):
  /// a learner finds their own in a list they can't read yet.
  String get nativeName => switch (this) {
    UiLanguage.english => 'English',
    UiLanguage.bangla => 'বাংলা',
    UiLanguage.polish => 'Polski',
    UiLanguage.russian => 'Русский',
  };
}

/// The app language a first run starts in (#1078): the phone's, when Sogda
/// speaks it, and English otherwise.
UiLanguage uiLanguageFor(Locale phone) => UiLanguage.values.firstWhere(
  (language) => language.locale.languageCode == phone.languageCode,
  orElse: () => UiLanguage.english,
);
