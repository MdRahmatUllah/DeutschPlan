import 'dart:async';

import 'package:deutschplan/core/providers/app_providers.dart'
    show settingsSourceProvider;
import 'package:deutschplan/data/repositories/model_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/features/me/settings_screen.dart';
import 'package:deutschplan/features/today/today_providers.dart'
    show voiceInstalledProvider;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// Settings without a database: every default, and writes kept in memory.
class StubSettings extends Fake implements SettingsRepository {
  final Map<String, Object?> _values = <String, Object?>{};
  final StreamController<SettingKey<Object?>> _changes =
      StreamController<SettingKey<Object?>>.broadcast();

  @override
  Stream<SettingKey<Object?>> get changes => _changes.stream;

  @override
  T read<T>(SettingKey<T> key) =>
      _values.containsKey(key.name) ? _values[key.name] as T : key.defaultValue;

  @override
  Future<void> write<T>(SettingKey<T> key, T value) async {
    put(key, value);
    _changes.add(key);
  }

  /// A value from before the test, heard by nothing.
  void put<T>(SettingKey<T> key, T value) => _values[key.name] = value;
}

/// M3 without a database: the documented defaults, no learned words, and no
/// translation model in the manifest — or what the test gives.
List<Override> settingsStub({
  SettingsRepository? settings,
  List<double> stabilities = const <double>[],
  ModelState? model,
}) => <Override>[
  settingsSourceProvider.overrideWithValue(settings ?? StubSettings()),
  learnedStabilitiesProvider.overrideWith((ref) async => stabilities),
  translationModelProvider.overrideWith((ref) async => model),
  // The artboards' voice is on the phone (#345).
  voiceInstalledProvider.overrideWith((ref) async => true),
];

/// The Settings artboards' learner: Mon–Sat with the 19:30 reminder, only
/// when something is due; translation on and downloading.
StubSettings artboardSettings() => StubSettings()
  ..put(SettingKeys.studyDaysMask, 63)
  ..put(SettingKeys.reminderEnabled, true)
  ..put(SettingKeys.mtEnabled, true);

/// 110 words at a stability of ten days: at 90 % each comes round every ten
/// days, so ≈ 11 reviews a day, as the artboard's retention line reads.
final List<double> artboardStabilities = List<double>.filled(110, 10);

/// Hy-MT 1.5 at the artboard's 42 %.
ModelState downloadingModel([ModelStatus status = ModelStatus.downloading]) =>
    ModelState(
      variant: ModelVariant(
        id: 'q4_k_m',
        name: '4-bit build',
        files: <ModelFile>[
          ModelFile(
            name: 'hymt.gguf',
            url: Uri.parse('https://example.invalid/hymt.gguf'),
            bytes: 100,
            sha256: null,
          ),
        ],
      ),
      status: status,
      bytesOnDisk: 42,
    );

/// [settingsStub] with the artboard's values.
List<Override> artboardSettingsStub() => settingsStub(
  settings: artboardSettings(),
  stabilities: artboardStabilities,
  model: downloadingModel(),
);
