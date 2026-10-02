import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart' show Fake;
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/data/repositories/model_repository.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/features/me/model_manager_screen.dart';
import 'package:sogda/services/device_storage.dart';
import 'package:sogda/services/model_downloads.dart';
import 'package:sogda/services/notification_permission.dart';
import 'package:sogda/services/tts/tts_engine.dart';

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
  variants: <ModelVariant>[
    ModelVariant(
      id: 'default',
      name: 'Supertonic 3',
      files: <ModelFile>[_file('vector_estimator.onnx', 399237419)],
    ),
  ],
);

/// The manifest's translation model, Hy-MT2 at its real size (#409's Q4_K_M, #154).
final ModelEntry translationEntry = ModelEntry(
  id: ModelRepository.translationModel,
  name: 'Hy-MT2 translation',
  licence: 'Apache-2.0',
  disables: 'mt_enabled',
  variants: <ModelVariant>[
    ModelVariant(
      id: 'q4_k_m',
      name: '4-bit build',
      files: <ModelFile>[_file('Hy-MT2-1.8B-Q4_K_M.gguf', 1133080448)],
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

  /// Holds [start] until completed: the manager still taking it.
  Completer<void>? startGate;

  @override
  Future<void> start(String modelId) async {
    calls.add('start $modelId');
    await startGate?.future;
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

  /// Another model's download in flight, as M4's *Delete* asks (#154).
  @override
  bool downloading = false;
}

/// The model files, recording what M4 deletes, with the voice [voice].
class FakeModels extends Fake implements ModelRepository {
  final List<String> deleted = <String>[];

  /// Each delete's `keepPartial` (#154).
  final List<bool> keptPartial = <bool>[];

  ModelStatus voice = ModelStatus.notDownloaded;

  @override
  Future<void> delete(ModelEntry entry, {bool keepPartial = false}) async {
    if (deleteFails) throw StateError('files in use');
    deleted.add(entry.id);
    keptPartial.add(keepPartial);
  }

  /// A delete whose files won't go (#721).
  bool deleteFails = false;

  @override
  Future<ModelManifest> manifest() async =>
      ModelManifest(version: 1, models: <ModelEntry>[voiceEntry]);

  @override
  Future<ModelState> stateOf(
    ModelEntry entry,
    ModelVariant variant, {
    bool sized = true,
  }) async =>
      ModelState(entry: entry, variant: variant, status: voice, bytesOnDisk: 0);
}

/// M4 without a disk, a downloader or a voice: the artboard's cards, or what
/// the test gives. [read] hears each card's id as it is read.
List<Override> modelManagerStub({
  ModelCard? voice,
  ModelCard? translation,
  StorageSpace? space = artboardSpace,
  FakeDownloads? downloads,
  ModelRepository? models,
  TtsEngine? supertonic,
  SettingsRepository? settings,
  NotificationPermission? permission,
  void Function(String id)? read,
}) => <Override>[
  modelCardProvider(ModelRepository.voiceModel).overrideWith((ref) {
    read?.call(ModelRepository.voiceModel);
    return Stream.value(voice ?? artboardVoice);
  }),
  modelCardProvider(ModelRepository.translationModel).overrideWith((ref) {
    read?.call(ModelRepository.translationModel);
    return Stream.value(translation ?? artboardTranslation);
  }),
  phoneSpaceProvider.overrideWith((ref) async => space),
  modelDownloadsProvider.overrideWithValue(downloads ?? FakeDownloads()),
  modelRepositoryProvider.overrideWithValue(models ?? FakeModels()),
  supertonicTtsProvider.overrideWithValue(supertonic ?? FakeTts()),
  settingsProvider.overrideWithValue(settings ?? StubSettings()),
  // #501: a download asks first; no platform to answer in a test.
  notificationPermissionProvider.overrideWithValue(
    permission ?? FakeNotificationPermission(),
  ),
];

/// The notification question a download asks (#501): counted, and answered
/// [allowed].
class FakeNotificationPermission implements NotificationPermission {
  FakeNotificationPermission({this.allowed = true});

  final bool allowed;
  int asked = 0;

  @override
  Future<bool> request() async {
    asked++;
    return allowed;
  }

  @override
  Future<bool> granted() async => allowed;

  @override
  Future<bool> openSettings() async => true;
}
