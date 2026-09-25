import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:crypto/crypto.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/model_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/services/model_downloads.dart';
import 'package:flutter_test/flutter_test.dart';

/// The download manager (#156, FR-M4-01) over a fake platform downloader: the
/// notification, the record of what was in flight, *Wi-Fi only*, pause and
/// resume, the progress a card draws, and nothing activated until it verifies.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory support;
  late SettingsRepository settings;
  late ModelRepository models;
  late _Downloader downloader;
  late BackgroundModelDownloads downloads;

  /// Two files, 300 and 100 bytes, hashed for real.
  final one = 'a' * 300;
  final two = 'b' * 100;
  ModelFile file(String name, String content) => ModelFile(
    name: name,
    url: Uri.parse('https://example.invalid/$name'),
    bytes: content.length,
    sha256: sha256.convert(utf8.encode(content)).toString(),
  );

  setUp(() async {
    support = Directory.systemTemp.createTempSync('dp_downloads');
    final db = AppDatabase.memory();
    addTearDown(db.close);
    settings = SettingsRepository(db);
    await settings.load();
    addTearDown(settings.dispose);
    models = ModelRepository(settings, support: support)
      ..useManifest(
        ModelManifest(
          version: 1,
          models: <ModelEntry>[
            ModelEntry(
              id: 'hymt',
              name: 'Hy-MT 1.5',
              licence: 'test',
              disables: 'mt_enabled',
              regionExcluded: const <String>[],
              variants: <ModelVariant>[
                ModelVariant(
                  id: 'q1_25',
                  name: 'test build',
                  files: <ModelFile>[
                    file('one.gguf', one),
                    file('two.gguf', two),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
    downloader = _Downloader();
    downloads = BackgroundModelDownloads(models, settings, downloader);
  });

  tearDown(() {
    try {
      support.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows lets go of the directory a moment later.
    }
  });

  /// The downloader reports on [name], and the service has had its turn.
  Future<void> report(
    TaskUpdate Function(DownloadTask task) update,
    String name,
  ) async {
    final task = downloader.queued.firstWhere((t) => t.filename == name);
    downloader.updates$.add(update(task));
    await pumpEventQueue();
  }

  /// Until the checksums have been read: hashing reads the files for real.
  Future<void> settled() => downloads
      .watch('hymt')
      .firstWhere(
        (p) =>
            p.phase == DownloadPhase.ready || p.phase == DownloadPhase.failed,
      )
      .timeout(const Duration(seconds: 10));

  Future<void> land(String name, String content) async {
    final staging = await models.stagingFor('hymt');
    File('${staging.path}/$name').writeAsStringSync(content);
  }

  group('FR-M4-01 attach, at launch', () {
    test('one notification for every file, with a progress bar', () async {
      await downloads.attach();
      expect(downloader.notification, 'models');
      expect(downloader.progressBar, isTrue);
      expect(downloader.running!.title, contains('{numFinished}'));
      expect(downloader.running!.title, contains('{numTotal}'));
    });

    test('the downloader picks up what was in flight: killed tasks are '
        'scheduled again', () async {
      await downloads.attach();
      expect(downloader.calls, contains('start'));
    });

    test('Wi-Fi only is on by default, for every task', () async {
      await downloads.attach();
      expect(downloader.wifi, RequireWiFi.forAllTasks);
    });

    test('attaching twice listens once', () async {
      await downloads.attach();
      await downloads.attach();
      expect(downloader.calls.where((c) => c == 'start'), hasLength(1));
    });
  });

  test('FR-M4-01 the Wi-Fi only switch is the setting and the rule, running '
      'tasks included', () async {
    await downloads.attach();
    await downloads.setWifiOnly(on: false);
    expect(settings.read(SettingKeys.modelsWifiOnly), isFalse);
    expect(downloader.wifi, RequireWiFi.forNoTasks);
    await downloads.setWifiOnly(on: true);
    expect(downloader.wifi, RequireWiFi.forAllTasks);
  });

  test('FR-M4-01 pause and resume act on the model\'s files, not '
      'everyone\'s', () async {
    await downloads.pause('hymt');
    await downloads.resume('hymt');
    expect(downloader.calls, <String>['pause hymt', 'resume hymt']);
  });

  group('FR-M4-01 the card\'s progress', () {
    setUp(() async {
      await downloads.attach();
      await downloads.start('hymt');
    });

    test('bytes arrived over the model\'s bytes, file by file', () async {
      final seen = <DownloadProgress>[];
      final sub = downloads.watch('hymt').listen(seen.add);
      addTearDown(sub.cancel);
      await report((t) => TaskStatusUpdate(t, TaskStatus.running), 'one.gguf');
      await report((t) => TaskProgressUpdate(t, 0.5), 'one.gguf');
      // 150 of 400 bytes.
      expect(seen.last, (phase: DownloadPhase.running, progress: 150 / 400));
    });

    test('queued with Wi-Fi only on: "Paused — resumes on Wi-Fi"', () async {
      final seen = <DownloadProgress>[];
      final sub = downloads.watch('hymt').listen(seen.add);
      addTearDown(sub.cancel);
      await report((t) => TaskStatusUpdate(t, TaskStatus.enqueued), 'one.gguf');
      expect(seen.last.phase, DownloadPhase.waitingForWifi);
    });

    test(
      'paused by the learner, and a file that fails fails the model',
      () async {
        final seen = <DownloadProgress>[];
        final sub = downloads.watch('hymt').listen(seen.add);
        addTearDown(sub.cancel);
        await report((t) => TaskStatusUpdate(t, TaskStatus.paused), 'one.gguf');
        expect(seen.last.phase, DownloadPhase.paused);
        await report((t) => TaskStatusUpdate(t, TaskStatus.failed), 'two.gguf');
        expect(seen.last.phase, DownloadPhase.failed);
      },
    );

    test('a late listener gets the last word first', () async {
      await report((t) => TaskStatusUpdate(t, TaskStatus.paused), 'one.gguf');
      expect((await downloads.watch('hymt').first).phase, DownloadPhase.paused);
    });
  });

  group('FR-M4-01 nothing activates until it verifies', () {
    setUp(() async {
      await downloads.attach();
      await downloads.start('hymt');
    });

    test('every file in and every checksum right: verified, then ready and '
        'in place', () async {
      final seen = <DownloadPhase>[];
      final sub = downloads.watch('hymt').listen((p) => seen.add(p.phase));
      addTearDown(sub.cancel);
      await land('one.gguf', one);
      await land('two.gguf', two);
      await report((t) => TaskStatusUpdate(t, TaskStatus.complete), 'one.gguf');
      expect(
        seen,
        isNot(contains(DownloadPhase.verifying)),
        reason: 'one of two files: nothing to check yet',
      );
      await report((t) => TaskStatusUpdate(t, TaskStatus.complete), 'two.gguf');
      await settled();

      expect(
        seen,
        containsAllInOrder(<DownloadPhase>[
          DownloadPhase.verifying,
          DownloadPhase.ready,
        ]),
      );
      final active = await models.directoryFor('hymt');
      expect(File('${active.path}/one.gguf').readAsStringSync(), one);
    });

    test('a file that does not verify: failed, and nothing in place', () async {
      final seen = <DownloadPhase>[];
      final sub = downloads.watch('hymt').listen((p) => seen.add(p.phase));
      addTearDown(sub.cancel);
      await land('one.gguf', one);
      await land('two.gguf', 'not what the manifest hashed');
      await report((t) => TaskStatusUpdate(t, TaskStatus.complete), 'one.gguf');
      await report((t) => TaskStatusUpdate(t, TaskStatus.complete), 'two.gguf');
      await settled();

      expect(seen.last, DownloadPhase.failed);
      expect((await models.directoryFor('hymt')).existsSync(), isFalse);
    });

    test('Retry throws the failed files away and queues them again', () async {
      await land('two.gguf', 'corrupt');
      downloader.queued.clear();
      await downloads.retry('hymt');
      final staging = await models.stagingFor('hymt');
      expect(File('${staging.path}/two.gguf').existsSync(), isFalse);
      expect(downloader.queued.map((t) => t.filename), <String>[
        'one.gguf',
        'two.gguf',
      ]);
    });
  });
}

class _Downloader implements FileDownloader {
  final List<DownloadTask> queued = <DownloadTask>[];
  final List<String> calls = <String>[];
  final StreamController<TaskUpdate> updates$ =
      StreamController<TaskUpdate>.broadcast();
  RequireWiFi? wifi;
  TaskNotification? running;
  String? notification;
  bool? progressBar;

  @override
  Stream<TaskUpdate> get updates => updates$.stream;

  @override
  Future<List<bool>> enqueueAll(Iterable<Task> tasks) async {
    queued.addAll(tasks.cast<DownloadTask>());
    return <bool>[for (final _ in tasks) true];
  }

  @override
  FileDownloader configureNotification({
    TaskNotification? running,
    TaskNotification? complete,
    TaskNotification? error,
    TaskNotification? paused,
    TaskNotification? canceled,
    bool progressBar = false,
    bool tapOpensFile = false,
    String groupNotificationId = '',
  }) {
    this.running = running;
    this.progressBar = progressBar;
    notification = groupNotificationId;
    return this;
  }

  @override
  Future<void> start({
    bool doTrackTasks = true,
    bool markDownloadedComplete = true,
    bool doRescheduleKilledTasks = true,
    bool autoCleanDatabase = false,
  }) async {
    calls.add('start');
  }

  @override
  Future<bool> requireWiFi(
    RequireWiFi requirement, {
    rescheduleRunningTasks = true,
    alsoRestartUploads = false,
  }) async {
    wifi = requirement;
    return true;
  }

  @override
  Future<List<DownloadTask>> pauseAll({
    Iterable<DownloadTask>? tasks,
    String? group,
  }) async {
    calls.add('pause $group');
    return <DownloadTask>[];
  }

  @override
  Future<List<Task>> resumeAll({
    Iterable<DownloadTask>? tasks,
    String? group,
    Duration interval = const Duration(milliseconds: 50),
  }) async {
    calls.add('resume $group');
    return <Task>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
