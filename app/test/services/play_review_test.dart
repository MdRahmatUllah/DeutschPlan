import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/services/play_review.dart';

import '../features/settings_fixtures.dart';

/// Play's In-App Review API, without Play: whether it's there, and each
/// request counted.
class _Api extends Fake implements InAppReview {
  _Api({this.available = true, this.fails = false});

  final bool available;
  final bool fails;
  int requested = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> requestReview() async {
    requested++;
    if (fails) throw StateError('Play said no');
  }
}

/// BR-RATE-01 (#1237): Play's review card, once, after the first passed
/// mock exam.
void main() {
  test(
    'BR-RATE-01 the first pass asks for the card, and no later one does',
    () async {
      final settings = StubSettings();
      final api = _Api();
      final review = PlayReview(settings, api: api);
      await review.afterPass();
      await review.afterPass();
      expect(api.requested, 1);
      expect(settings.read(SettingKeys.playReviewAsked), isTrue);
    },
  );

  test('BR-RATE-01 with Play not there, no card, and it counts as asked: a '
      'later pass with Play asks nothing', () async {
    final settings = StubSettings();
    await PlayReview(settings, api: _Api(available: false)).afterPass();
    expect(settings.read(SettingKeys.playReviewAsked), isTrue);
    final later = _Api();
    await PlayReview(settings, api: later).afterPass();
    expect(later.requested, 0);
  });

  test(
    'BR-RATE-01 a request Play refuses is caught, and counts as asked',
    () async {
      final settings = StubSettings();
      final api = _Api(fails: true);
      await PlayReview(settings, api: api).afterPass();
      expect(api.requested, 1);
      expect(settings.read(SettingKeys.playReviewAsked), isTrue);
    },
  );

  test('BR-RATE-01 Android only: the app is on Play alone', () async {
    final settings = StubSettings();
    final api = _Api();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await PlayReview(settings, api: api).afterPass();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    expect(api.requested, 0);
    expect(settings.read(SettingKeys.playReviewAsked), isFalse);
  });
}
