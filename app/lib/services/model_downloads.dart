import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:deutschplan/data/repositories/model_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/l10n/ui_language_locale.dart';

/// What a model's download is doing (FR-M4-01, #156), for M4's card.
enum DownloadPhase {
  /// Bytes are arriving.
  running,

  /// Queued, and held back: with *Wi-Fi only* on, the platform starts it
  /// only on Wi-Fi. "Paused — resumes on Wi-Fi".
  waitingForWifi,

  /// Paused by the learner.
  paused,

  /// Every file is in, and the checksums are being read.
  verifying,

  /// Verified and in place.
  ready,

  /// A file failed to download, or to verify. *Retry*.
  failed,
}

/// A model's download: its phase, and how much of it has arrived (0–1).
typedef DownloadProgress = ({DownloadPhase phase, double progress});

/// The model downloads (FR-M4-01): started, paused, resumed and retried by
/// the learner; carried on by the platform's downloader with the app in the
/// background or closed; and checked before anything uses them.
abstract interface class ModelDownloads {
  /// Once, at launch: the progress notification, the downloader's updates,
  /// its record of what was in flight, and the *Wi-Fi only* rule.
  Future<void> attach();

  /// Queues every file of [modelId]'s first variant into its staging
  /// directory, and returns once they are queued, not once they arrive.
  Future<void> start(String modelId);

  Future<void> pause(String modelId);
  Future<void> resume(String modelId);

  /// *Retry* after a failure: what the failed attempt left is thrown away,
  /// and the files come again.
  Future<void> retry(String modelId);

  /// M4's *Wi-Fi only* switch: `models_wifi_only`, and the downloader's rule
  /// for every task, running ones included.
  Future<void> setWifiOnly({required bool on});

  /// [modelId]'s download as it moves, from its last known state on.
  Stream<DownloadProgress> watch(String modelId);
}

class BackgroundModelDownloads implements ModelDownloads {
  BackgroundModelDownloads(
    this._models,
    this._settings, [
    FileDownloader? downloader,
  ]) : _downloader = downloader ?? FileDownloader();

  final ModelRepository _models;
  final SettingsRepository _settings;
  final FileDownloader _downloader;

  /// Per model, per file: the platform's last word on it.
  final Map<String, Map<String, ({TaskStatus status, double done})>> _files =
      <String, Map<String, ({TaskStatus status, double done})>>{};
  final Map<String, StreamController<DownloadProgress>> _watchers =
      <String, StreamController<DownloadProgress>>{};
  final Map<String, DownloadProgress> _last = <String, DownloadProgress>{};

  /// The models being verified: a burst of late updates must not verify a
  /// model twice.
  final Set<String> _checking = <String>{};

  StreamSubscription<TaskUpdate>? _updates;

  @override
  Future<void> attach() async {
    if (_updates != null) return;
    final l10n = lookupAppLocalizations(
      _settings.read(SettingKeys.uiLanguage).locale,
    );
    // One notification for every file of every model. The tokens are the
    // downloader's own, filled in on the device.
    _downloader.configureNotification(
      running: TaskNotification(
        l10n.modelNotifyRunning('{numFinished}', '{numTotal}'),
        l10n.modelNotifyRunningNote,
      ),
      paused: TaskNotification(
        l10n.modelNotifyPaused,
        l10n.modelNotifyPausedNote,
      ),
      complete: TaskNotification(
        l10n.modelNotifyComplete,
        l10n.modelNotifyCompleteNote,
      ),
      error: TaskNotification(
        l10n.modelNotifyFailed,
        l10n.modelNotifyFailedNote,
      ),
      progressBar: true,
      groupNotificationId: 'models',
    );
    _updates = _downloader.updates.listen((update) => unawaited(_on(update)));
    // The downloader's own record: a task the system or the learner killed
    // is scheduled again, and one that finished while the app was away says
    // so now.
    await _downloader.start();
    await _applyWifi();
  }

  @override
  Future<void> start(String modelId) async {
    final model = (await _models.manifest()).model(modelId);
    if (model == null || model.variants.isEmpty) {
      throw ArgumentError.value(modelId, 'modelId', 'is not in the manifest');
    }
    await _models.beginDownload(modelId);

    await _downloader.enqueueAll(<Task>[
      for (final file in model.variants.first.files)
        DownloadTask(
          url: file.url.toString(),
          filename: file.name,
          // Relative to app support, where `ModelRepository` keeps its
          // staging directories, so the platform resolves the same place.
          baseDirectory: BaseDirectory.applicationSupport,
          directory: ModelRepository.stagingPath(modelId),
          group: modelId,
          displayName: model.name,
          updates: Updates.statusAndProgress,
          allowPause: true,
          retries: 3,
        ),
    ]);
  }

  @override
  Future<void> pause(String modelId) async {
    await _downloader.pauseAll(group: modelId);
  }

  @override
  Future<void> resume(String modelId) async {
    await _downloader.resumeAll(group: modelId);
  }

  @override
  Future<void> retry(String modelId) async {
    await _models.restartDownload(modelId);
    _files.remove(modelId);
    await start(modelId);
  }

  @override
  Future<void> setWifiOnly({required bool on}) async {
    await _settings.write(SettingKeys.modelsWifiOnly, on);
    await _applyWifi();
  }

  @override
  Stream<DownloadProgress> watch(String modelId) async* {
    final controller = _watchers.putIfAbsent(
      modelId,
      StreamController<DownloadProgress>.broadcast,
    );
    if (_last[modelId] case final last?) yield last;
    yield* controller.stream;
  }

  Future<void> _applyWifi() => _downloader.requireWiFi(
    _settings.read(SettingKeys.modelsWifiOnly)
        ? RequireWiFi.forAllTasks
        : RequireWiFi.forNoTasks,
  );

  Future<void> _on(TaskUpdate update) async {
    final modelId = update.task.group;
    final model = (await _models.manifest()).model(modelId);
    if (model == null || model.variants.isEmpty) return;
    final variant = model.variants.first;
    final files = _files.putIfAbsent(
      modelId,
      () => <String, ({TaskStatus status, double done})>{},
    );
    final name = update.task.filename;
    final before = files[name] ?? (status: TaskStatus.enqueued, done: 0.0);
    files[name] = switch (update) {
      TaskStatusUpdate(:final status) => (
        status: status,
        done: status == TaskStatus.complete ? 1.0 : before.done,
      ),
      // Negative progress is the downloader's own signal (failed, paused,
      // waiting), which its status update carries.
      TaskProgressUpdate(:final progress) when progress >= 0 => (
        status: before.status == TaskStatus.enqueued
            ? TaskStatus.running
            : before.status,
        done: progress,
      ),
      _ => before,
    };

    final complete = variant.files.every(
      (file) => files[file.name]?.status == TaskStatus.complete,
    );
    if (complete) {
      if (!_checking.add(modelId)) return;
      _emit(modelId, (phase: DownloadPhase.verifying, progress: 1));
      // FR-M4-01: only a variant whose every checksum passes is put in place.
      final status = await _models.activate(modelId, variant);
      _checking.remove(modelId);
      _files.remove(modelId);
      _emit(modelId, (
        phase: status == ModelStatus.ready
            ? DownloadPhase.ready
            : DownloadPhase.failed,
        progress: 1,
      ));
      return;
    }
    var arrived = 0.0;
    for (final file in variant.files) {
      arrived += file.bytes * (files[file.name]?.done ?? 0);
    }
    _emit(modelId, (
      phase: _phaseOf(<TaskStatus>[
        for (final file in variant.files)
          files[file.name]?.status ?? TaskStatus.enqueued,
      ]),
      progress: variant.bytes == 0 ? 0 : arrived / variant.bytes,
    ));
  }

  /// The model's phase from its files': one that failed fails it, one paused
  /// pauses it, one running runs it. Queued with *Wi-Fi only* on is the
  /// platform waiting for Wi-Fi.
  // ponytail: the downloader doesn't say why a task is still queued, and a
  // Wi-Fi-only one off Wi-Fi is the long wait; a network listener would tell
  // it apart from the platform's own queue, for a second or two at the start.
  DownloadPhase _phaseOf(List<TaskStatus> statuses) {
    if (statuses.any(
      (s) =>
          s == TaskStatus.failed ||
          s == TaskStatus.notFound ||
          s == TaskStatus.canceled,
    )) {
      return DownloadPhase.failed;
    }
    if (statuses.contains(TaskStatus.paused)) return DownloadPhase.paused;
    if (statuses.contains(TaskStatus.running)) return DownloadPhase.running;
    return _settings.read(SettingKeys.modelsWifiOnly)
        ? DownloadPhase.waitingForWifi
        : DownloadPhase.running;
  }

  void _emit(String modelId, DownloadProgress progress) {
    _last[modelId] = progress;
    _watchers[modelId]?.add(progress);
  }
}
