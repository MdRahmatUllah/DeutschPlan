/// Play's in-app review card (#1237, BR-RATE-01): asked for once, after the
/// learner's first passed mock exam.
library;

import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/settings_repository.dart';

/// BR-RATE-01: once, after the first passed mock exam, with no question
/// before it, no incentive and no button of its own (Google's rules). Only
/// that it asked is kept (`play_review_asked`). Whether Play shows the card
/// is Play's call (its quota), and Sogda sends nothing about the learner.
class PlayReview {
  PlayReview(this._settings, {InAppReview? api})
    : _api = api ?? InAppReview.instance;

  final SettingsRepository _settings;
  final InAppReview _api;

  /// L13 shows a passed mock exam: ask, unless the app has asked before.
  /// Android only: the app is on Play alone (v1 scope).
  Future<void> afterPass() async {
    if (defaultTargetPlatform != TargetPlatform.android ||
        _settings.read(SettingKeys.playReviewAsked)) {
      return;
    }
    // Recorded first: a card that fails, or that Play never shows, is never
    // asked for again.
    await _settings.write(SettingKeys.playReviewAsked, true);
    try {
      if (await _api.isAvailable()) await _api.requestReview();
    } on Object catch (error) {
      debugPrint('play review: $error');
    }
  }
}
