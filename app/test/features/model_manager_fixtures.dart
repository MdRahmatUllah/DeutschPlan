import 'dart:async';

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/repositories/model_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/features/me/model_manager_screen.dart';
import 'package:deutschplan/services/device_storage.dart';
import 'package:deutschplan/services/model_downloads.dart';
import 'package:deutschplan/services/tts/tts_engine.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart' show Fake;

import '../services/fake_tts.dart';
import 'settings_fixtures.dart';

ModelFile _file(String name, int bytes) => ModelFile(
  name: name,
  url: Uri.parse('https://example.invalid/$name'),
  bytes: bytes,
  sha256: 'a' * 64,
);

/// The manifest's voice, at its real size (#152's nine files, 399 MB).
final ModelEntry voiceEntry = ModelEntry(
  id: ModelRepository.voiceModel,
  name: 'Supertonic 3 voice',
  licence: 'OpenRAIL-M',
  disables: 'tts_engine',
  regionExcluded: const <String>[],
  variants: <ModelVariant>[
    ModelVariant(
      id: 'default',
      name: 'Supertonic 3',
      files: <ModelFile>[_file('vector_estimator.onnx', 399237419)],
    ),
  ],
);

/// The manifest's translation model, at its real size (#409's Q4_K_M).
final ModelEntry translationEntry = ModelEntry(
  id: ModelRepository.translationModel,
  name: 'Hy-MT 1.5 translation',
  licence: 'Tencent HY',
  disables: 'mt_enabled',
  regionExcluded: const <String>['EU', 'GB', 'KR'],
  variants: <ModelVariant>[
    ModelVariant(
      id: 'q4_k_m',
      name: '4-bit build',
      files: <ModelFile>[_file('HY-MT1.5-1.8B-Q4_K_M.gguf', 1133080512)],
    ),
  ],
);

/// [entry]'s card: what is [installed], the download [live], and the
/// shortfall a new one would have.
ModelCard cardOf(
  ModelEntry entry, {
  ModelStatus installed = ModelStatus.notDownloaded,
  DownloadProgress? live,
  int shortfall = 0,
}) {
  final variant = entry.variants.first;
  final onDisk = switch (installed) {
    ModelStatus.ready || ModelStatus.updateAvailable => variant.bytes,
    _ when live != null => (variant.bytes * live.progress).round(),
    _ => 0,
  };
  return (
    entry: entry,
    variant: variant,
    installed: ModelState(
      entry: entry,
      variant: variant,
      status: installed,
      bytesOnDisk: onDisk,
    ),
    live: live,
    shortfall: shortfall,
  );
}

/// The artboard's phone: 12.4 GB free of 64 GB.
const StorageSpace artboardSpace = (free: 12400000000, total: 64000000000);

/// The artboard's cards: the voice ready, the translation model 42 % in.
final ModelCard artboardVoice = cardOf(
  voiceEntry,
  installed: ModelStatus.ready,
);
final ModelCard artboardTranslation = cardOf(
  translationEntry,
  installed: ModelStatus.downloading,
  live: (phase: DownloadPhase.running, progress: 0.42),
);

/// The download manager, recording what M4 asks of it.
class FakeDownloads extends Fake implements ModelDownloads {
  FakeDownloads({this.settings});

  final List<String> calls = <String>[];

  /// Where *Wi-Fi only* is kept, when a test reads it back.
  final SettingsRepository? settings;

  /// What [shortfallFor] answers: the manager's space check (#428).
  int shortfall = 0;

  @override
  Future<int> shortfallFor(String modelId) async => shortfall;

  /// What [start] throws, once.
  Object? startFails;

  @override
  Future<void> start(String modelId) async {
    calls.add('start $modelId');
    final fails = startFails;
    startFails = null;
    if (fails != null) throw fails;
  }

  @override
  Future<void> pause(String modelId) async => calls.add('pause $modelId');

  @override
  Future<void> resume(String modelId) async => calls.add('resume $modelId');

  @override
  Future<void> retry(String modelId) async => calls.add('retry $modelId');

  @override
  Future<void> setWifiOnly({required bool on}) async {
    calls.add('wifi $on');
    await settings?.write(SettingKeys.modelsWifiOnly, on);
  }

  /// Each model's download, as a test moves it.
  final Map<String, StreamController<DownloadProgress>> live =
      <String, StreamController<DownloadProgress>>{};

  @override
  Stream<DownloadProgress> watch(String modelId) => live
      .putIfAbsent(modelId, StreamController<DownloadProgress>.broadcast)
      .stream;
}

/// The model files, recording what M4 deletes.
class FakeModels extends Fake implements ModelRepository {
  final List<String> deleted = <String>[];

  @override
  Future<void> delete(ModelEntry entry) async => deleted.add(entry.id);
}

/// M4 without a disk, a downloader or a voice: the artboard's cards, or what
/// the test gives.
List<Override> modelManagerStub({
  ModelCard? voice,
  ModelCard? translation,
  StorageSpace? space = artboardSpace,
  FakeDownloads? downloads,
  ModelRepository? models,
  TtsEngine? supertonic,
  SettingsRepository? settings,
}) => <Override>[
  modelCardProvider(ModelRepository.voiceModel)
      .overrideWith((ref) => Stream.value(voice ?? artboardVoice)),
  modelCardProvider(ModelRepository.translationModel)
      .overrideWith((ref) => Stream.value(translation ?? artboardTranslation)),
  phoneSpaceProvider.overrideWith((ref) async => space),
  modelDownloadsProvider.overrideWithValue(downloads ?? FakeDownloads()),
  modelRepositoryProvider.overrideWithValue(models ?? FakeModels()),
  supertonicTtsProvider.overrideWithValue(supertonic ?? FakeTts()),
  settingsProvider.overrideWithValue(settings ?? StubSettings()),
];
