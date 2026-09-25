import 'dart:ui' show Locale;

import 'package:deutschplan/data/repositories/setting_keys.dart';

/// The locale for each app language. `UiLanguage` lives in the data layer,
/// which knows nothing of Flutter, so the mapping lives here: the app's and
/// a background task's (#158) alike.
extension UiLanguageLocale on UiLanguage {
  Locale get locale => switch (this) {
    UiLanguage.english => const Locale('en'),
    UiLanguage.bangla => const Locale('bn'),
  };
}
