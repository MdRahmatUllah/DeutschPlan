import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:deutschplan/data/repositories/model_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/l10n/ui_language_locale.dart';
import 'package:deutschplan/services/device_storage.dart';

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

/// FR-M4 *Not enough space* (#428): [ModelDownloads.start] refused, because
/// the phone is [bytes] short of the model and its margin.
class NotEnoughSpace implements Exception {
  const NotEnoughSpace(this.bytes);

  final int bytes;

  @override
  String toString() => 'NotEnoughSpace: $bytes bytes short';
}

/// One file of a model's current attempt: its task, and the platform's last
/// word on it.
typedef _File = ({
  String task,
  DateTime created,
  TaskStatus status,
  double done,
});

/// The model downloads (FR-M4-01): started, paused, resumed and retried by
/// the learner; carried on by the platform's downloader with the app in the
/// background or closed; and checked before anything uses them.
abstract interface class ModelDownloads {
  /// What a download leaves free beyond the model's own bytes (#428): a
  /// phone filled to 0 bytes fails every app's writes, not just this one.
  static const int spaceMargin = 100 * 1000 * 1000;

  /// Once, at launch: the progress notification, the downloader's updates,
  /// its record of what was in flight, and the *Wi-Fi only* rule.
  Future<void> attach();

  /// Queues every file of [modelId]'s first variant into its staging
  /// directory, and returns once they are queued, not once they arrive.
  /// Throws [NotEnoughSpace] when [shortfallFor] says it wouldn't fit.
  Future<void> start(String modelId);

  /// The bytes the phone lacks for [modelId]'s download and [spaceMargin]:
  /// what a disabled *Download* states. 0 when it fits, or when the phone
  /// won't say.
  Future<int> shortfallFor(String modelId);

  Future<void> pause(String modelId);
  Future<void> resume(String modelId);

  /// *Retry* after a failure. After a network failure, the files that
  /// arrived stay and the rest come again. After a checksum failure,
  /// everything the attempt left is thrown away and every file comes again.
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
    DeviceStorage? storage,
  ]) : _downloader = downloader ?? FileDownloader(),
       _storage = storage ?? const PlatformDeviceStorage();

  final ModelRepository _models;
  final SettingsRepository _settings;
  final FileDownloader _downloader;
  final DeviceStorage _storage;

  /// Per model, per file: the current attempt's task, and the platform's last
  /// word on it. Forgotten once the model is verified, which is how *Retry*
  /// tells a checksum failure from a network one.
  final Map<String, Map<String, _File>> _files = <String, Map<String, _File>>{};
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
    // Before `start()`, which queues again the tasks the system killed.
    _notify(waiting: false);
    _updates = _downloader.updates.listen((update) => unawaited(_on(update)));
    // The downloader's own record: a task the system or the learner killed
    // is scheduled again, and one that finished while the app was away says
    // so now.
    await _downloader.start();
    // A file that finished in an earlier session never reports again, so
    // its record stands in for the update (#156, AC 1).
    final manifest = await _models.manifest();
    for (final record in await _downloader.database.allRecords()) {
      if (manifest.model(record.group) == null) continue;
      final files = _files.putIfAbsent(record.group, () => <String, _File>{});
      final known = files[record.task.filename];
      // What this launch has heard since, or a later attempt, stands.
      if (known != null && !record.task.creationTime.isAfter(known.created)) {
        continue;
      }
      files[record.task.filename] = (
        task: record.taskId,
        created: record.task.creationTime,
        status: record.status,
        done: record.status == TaskStatus.complete
            ? 1.0
            : (record.progress < 0 ? 0.0 : record.progress),
      );
    }
    for (final modelId in _files.keys.toList()) {
      await _settle(modelId);
    }
    // Not rescheduling running tasks: every launch would pause and queue
    // them again.
    await _applyWifi(reschedule: false);
  }

  @override
  Future<void> start(String modelId) async {
    final short = await shortfallFor(modelId);
    if (short > 0) throw NotEnoughSpace(short);
    await _queue(modelId);
  }

  @override
  Future<int> shortfallFor(String modelId) async {
    final model = (await _models.manifest()).model(modelId);
    if (model == null || model.variants.isEmpty) return 0;
    return shortfall(
      needed: model.variants.first.bytes + ModelDownloads.spaceMargin,
      space: await _storage.space(),
    );
  }

  /// One notification for every file of every model, in the UI language of
  /// the moment. The tokens are the downloader's own, filled in on the
  /// device.
  // ponytail: the platform keeps the texts each task was queued with, for
  // the whole of a model's download: files queued off Wi-Fi still say
  // *Waiting for Wi-Fi* once it arrives (their count moves), and a Wi-Fi
  // drop mid-download still says *Downloading*. A notification of our own,
  // updated from [_settle], is the upgrade (#428).
  void _notify({required bool waiting}) {
    final l10n = lookupAppLocalizations(
      _settings.read(SettingKeys.uiLanguage).locale,
    );
    _downloader.configureNotification(
      running: waiting
          ? TaskNotification(
              l10n.modelNotifyWaiting('{numFinished}', '{numTotal}'),
              l10n.modelNotifyWaitingNote,
            )
          : TaskNotification(
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
  }

  /// *Wi-Fi only* is on and the phone is off Wi-Fi: a queued file waits,
  /// by the downloader's own reading of the network.
  bool get _offWifi =>
      _settings.read(SettingKeys.modelsWifiOnly) && !_downloader.isWiFi;

  /// Queues [modelId]'s files, or those [only] names, as the current attempt.
  Future<void> _queue(
    String modelId, {
    bool Function(String name)? only,
  }) async {
    final model = (await _models.manifest()).model(modelId);
    if (model == null || model.variants.isEmpty) {
      throw ArgumentError.value(modelId, 'modelId', 'is not in the manifest');
    }
    // ponytail: the first variant, as the manifest has one per model (#409);
    // tag each task with its variant's id once a model offers two.
    final variant = model.variants.first;
    // A file with no checksum can never verify: 100–600 MB fetched to fail.
    if (!variant.isPinned) {
      throw StateError('$modelId has a file with no pinned checksum');
    }
    await _models.beginDownload(modelId);

    final tasks = <DownloadTask>[
      for (final file in variant.files)
        if (only == null || only(file.name))
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
    ];
    final files = _files.putIfAbsent(modelId, () => <String, _File>{});
    for (final task in tasks) {
      files[task.filename] = (
        task: task.taskId,
        created: task.creationTime,
        status: TaskStatus.enqueued,
        done: 0,
      );
    }
    _notify(waiting: _offWifi);
    await _downloader.enqueueAll(tasks);
    // Said now, not at the platform's first word: page 5 reads *Waiting for
    // Wi-Fi* or *Downloading* the moment it is queued (#428).
    await _settle(modelId);
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
    // The failed attempt's tasks stop, and their late updates have no say.
    await _downloader.cancelAll(group: modelId);
    final files = _files[modelId];
    if (files == null) {
      // A checksum failed (verifying forgets the files), or nothing is known:
      // a corrupt file resumed would never verify, so everything comes again.
      await _models.restartDownload(modelId);
      return _queue(modelId);
    }
    // A network failure: what arrived stays, and the rest comes again.
    await _queue(
      modelId,
      only: (name) => files[name]?.status != TaskStatus.complete,
    );
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

  Future<void> _applyWifi({bool reschedule = true}) => _downloader.requireWiFi(
    _settings.read(SettingKeys.modelsWifiOnly)
        ? RequireWiFi.forAllTasks
        : RequireWiFi.forNoTasks,
    rescheduleRunningTasks: reschedule,
  );

  Future<void> _on(TaskUpdate update) async {
    final modelId = update.task.group;
    final files = _files.putIfAbsent(modelId, () => <String, _File>{});
    final name = update.task.filename;
    final before = files[name];
    // A task of an earlier attempt, which *Retry* cancelled, has no say.
    if (before != null &&
        before.task != update.task.taskId &&
        !update.task.creationTime.isAfter(before.created)) {
      return;
    }
    final was = before?.status ?? TaskStatus.enqueued;
    final sofar = before?.done ?? 0.0;
    final (:status, :done) = switch (update) {
      TaskStatusUpdate(status: final now) => (
        status: now,
        done: now == TaskStatus.complete ? 1.0 : sofar,
      ),
      // Negative progress is the downloader's own signal (failed, paused,
      // waiting), which its status update carries.
      TaskProgressUpdate(:final progress) when progress >= 0 => (
        status: was == TaskStatus.enqueued ? TaskStatus.running : was,
        done: progress,
      ),
      _ => (status: was, done: sofar),
    };
    files[name] = (
      task: update.task.taskId,
      created: update.task.creationTime,
      status: status,
      done: done,
    );
    await _settle(modelId);
  }

  /// Verifies [modelId] once every file is in; until then, says how far it
  /// has come.
  Future<void> _settle(String modelId) async {
    final model = (await _models.manifest()).model(modelId);
    final files = _files[modelId];
    if (model == null || model.variants.isEmpty || files == null) return;
    final variant = model.variants.first;

    final complete = variant.files.every(
      (file) => files[file.name]?.status == TaskStatus.complete,
    );
    if (complete) {
      if (!_checking.add(modelId)) return;
      _emit(modelId, (phase: DownloadPhase.verifying, progress: 1));
      var status = ModelStatus.failed;
      try {
        // FR-M4-01: only a variant whose every checksum passes is put in
        // place.
        status = await _models.activate(modelId, variant);
      } on Object {
        // A rename refused (a full disk, a file held open): failed, *Retry*.
      }
      _checking.remove(modelId);
      _files.remove(modelId);
      _emit(modelId, (
        phase: status == ModelStatus.ready
            ? DownloadPhase.ready
            : DownloadPhase.failed,
        progress: 1,
      ));
      // Done with: the next launch mustn't verify a staging folder that was
      // renamed into place, or that *Retry* throws away.
      await _downloader.database.deleteAllRecords(group: modelId);
      return;
    }
    var arrived = 0.0;
    for (final file in variant.files) {
      arrived += file.bytes * (files[file.name]?.done ?? 0);
    }
    final wasFailed = _last[modelId]?.phase == DownloadPhase.failed;
    final phase = _phaseOf(<TaskStatus>[
      for (final file in variant.files)
        files[file.name]?.status ?? TaskStatus.enqueued,
    ]);
    _emit(modelId, (
      phase: phase,
      progress: variant.bytes == 0 ? 0 : arrived / variant.bytes,
    ));
    // One file failed (a full disk, a host gone): the attempt stops. The
    // rest let go of what they held, and the platform's one notification,
    // which says *failed* only once no file is left running, says so (#428).
    if (phase == DownloadPhase.failed && !wasFailed) {
      await _downloader.cancelAll(group: modelId);
    }
  }

  /// The model's phase from its files': one that failed fails it, one paused
  /// pauses it, one running runs it. Still queued is waiting for Wi-Fi when
  /// *Wi-Fi only* is on off Wi-Fi, and otherwise the platform's own queue,
  /// a second or two.
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
    return _offWifi ? DownloadPhase.waitingForWifi : DownloadPhase.running;
  }

  void _emit(String modelId, DownloadProgress progress) {
    _last[modelId] = progress;
    _watchers[modelId]?.add(progress);
  }
}
