import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:crypto/crypto.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/model_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/services/device_storage.dart';
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

  ModelManifest manifestOf(List<ModelFile> files) => ModelManifest(
    version: 1,
    models: <ModelEntry>[
      ModelEntry(
        id: 'hymt',
        name: 'Hy-MT 1.5',
        licence: 'test',
        disables: 'mt_enabled',
        regionExcluded: const <String>[],
        variants: <ModelVariant>[
          ModelVariant(id: 'q4_k_m', name: 'test build', files: files),
        ],
      ),
    ],
  );
  final manifest = manifestOf(<ModelFile>[
    file('one.gguf', one),
    file('two.gguf', two),
  ]);

  setUp(() async {
    support = Directory.systemTemp.createTempSync('dp_downloads');
    final db = AppDatabase.memory();
    addTearDown(db.close);
    settings = SettingsRepository(db);
    await settings.load();
    addTearDown(settings.dispose);
    models = ModelRepository(settings, support: support)..useManifest(manifest);
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

    test('Wi-Fi only is on by default, for every task, and a launch leaves '
        'running tasks running', () async {
      await downloads.attach();
      expect(downloader.wifi, RequireWiFi.forAllTasks);
      expect(downloader.rescheduled, isFalse);
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
    expect(downloader.rescheduled, isTrue);
    await downloads.setWifiOnly(on: true);
    expect(downloader.wifi, RequireWiFi.forAllTasks);
  });

  group('#156 across a restart', () {
    DownloadTask earlier(String name) => DownloadTask(
      url: 'https://example.invalid/$name',
      filename: name,
      group: 'hymt',
    );

    setUp(() async {
      await models.beginDownload('hymt');
      await land('one.gguf', one);
      await land('two.gguf', two);
    });

    test('a file that finished in an earlier session counts: with the other '
        'one\'s update, the model verifies', () async {
      downloader.database.records.add(
        TaskRecord(earlier('one.gguf'), TaskStatus.complete, 1, 300),
      );
      await downloads.attach();
      downloader.updates$.add(
        TaskStatusUpdate(earlier('two.gguf'), TaskStatus.complete),
      );
      await settled();

      expect((await downloads.watch('hymt').first).phase, DownloadPhase.ready);
      expect(
        downloader.database.records,
        isEmpty,
        reason: 'the next launch has nothing to verify',
      );
    });

    test('every file finished while the app was away: the model verifies '
        'at launch', () async {
      downloader.database.records.addAll(<TaskRecord>[
        TaskRecord(earlier('one.gguf'), TaskStatus.complete, 1, 300),
        TaskRecord(earlier('two.gguf'), TaskStatus.complete, 1, 100),
      ]);
      await downloads.attach();
      await settled();
      final active = await models.directoryFor('hymt');
      expect(File('${active.path}/two.gguf').readAsStringSync(), two);
    });
  });

  test('#156 an activation that throws fails the model, rather than leaving '
      'it verifying', () async {
    downloads = BackgroundModelDownloads(
      _RenameRefused(settings, support: support)..useManifest(manifest),
      settings,
      downloader,
    );
    await downloads.attach();
    await downloads.start('hymt');
    await report((t) => TaskStatusUpdate(t, TaskStatus.complete), 'one.gguf');
    await report((t) => TaskStatusUpdate(t, TaskStatus.complete), 'two.gguf');
    await settled();
    expect((await downloads.watch('hymt').first).phase, DownloadPhase.failed);
  });

  test('#156 a model with a file of no checksum is refused before a byte is '
      'fetched: it could never verify', () async {
    models.useManifest(
      manifestOf(<ModelFile>[
        ModelFile(
          name: 'one.gguf',
          url: Uri.parse('https://example.invalid/one.gguf'),
          bytes: 300,
          sha256: null,
        ),
      ]),
    );
    await expectLater(downloads.start('hymt'), throwsStateError);
    expect(downloader.queued, isEmpty);
  });

  test('FR-M4-01 pause and resume act on the model\'s files, not '
      'everyone\'s', () async {
    await downloads.pause('hymt');
    await downloads.resume('hymt');
    expect(downloader.calls, <String>['pause hymt', 'resume hymt']);
  });

  group('#428 FR-M4-01 not enough space', () {
    test('start refuses a model that would not fit, saying by how much with '
        'the margin, and queues nothing', () async {
      downloads = BackgroundModelDownloads(
        models,
        settings,
        downloader,
        _Storage(free: 300),
      );
      // 400 bytes of model and 100 MB to spare, over 300 bytes free.
      await expectLater(
        downloads.start('hymt'),
        throwsA(
          isA<NotEnoughSpace>().having(
            (e) => e.bytes,
            'bytes',
            100 * 1000 * 1000 + 100,
          ),
        ),
      );
      expect(downloader.queued, isEmpty);
      expect((await models.stagingFor('hymt')).existsSync(), isFalse);
    });

    test('and one that fits, margin and all, is queued', () async {
      downloads = BackgroundModelDownloads(
        models,
        settings,
        downloader,
        _Storage(free: 400 + ModelDownloads.spaceMargin),
      );
      expect(await downloads.shortfallFor('hymt'), 0);
      await downloads.start('hymt');
      expect(downloader.queued, hasLength(2));
    });
  });

  group('#428 FR-M4-01 waiting for Wi-Fi', () {
    late List<DownloadPhase> seen;

    setUp(() async {
      seen = <DownloadPhase>[];
      final sub = downloads.watch('hymt').listen((p) => seen.add(p.phase));
      addTearDown(sub.cancel);
      await downloads.attach();
    });

    test('queued off Wi-Fi with Wi-Fi only on: waiting from the moment it is '
        'queued, and the notification says so', () async {
      await downloads.start('hymt');
      await pumpEventQueue();
      expect(seen.last, DownloadPhase.waitingForWifi);
      expect(
        downloader.running!.title,
        'Waiting for Wi-Fi · {numFinished} of {numTotal} files',
      );
      expect(downloader.running!.body, 'Downloads on Wi-Fi, in the background');
    });

    test(
      'with Wi-Fi only off, off Wi-Fi is downloading, not waiting',
      () async {
        await settings.write(SettingKeys.modelsWifiOnly, false);
        await downloads.start('hymt');
        await pumpEventQueue();
        expect(seen.last, DownloadPhase.running);
        expect(
          downloader.running!.title,
          'Downloading models · {numFinished} of {numTotal} files',
        );
      },
    );

    test('queued on Wi-Fi: downloading, not waiting', () async {
      downloader.isWiFi = true;
      await downloads.start('hymt');
      await pumpEventQueue();
      expect(seen.last, DownloadPhase.running);
      expect(
        downloader.running!.title,
        'Downloading models · {numFinished} of {numTotal} files',
      );
    });

    test('the notification is in the language of the moment it is queued, '
        'not the launch\'s', () async {
      await settings.write(SettingKeys.uiLanguage, UiLanguage.bangla);
      await downloads.start('hymt');
      expect(downloader.running!.title, startsWith('ওয়াই-ফাইয়ের অপেক্ষায়'));
    });
  });

  group('#455 FR-M4-01 losing Wi-Fi mid-download, with Wi-Fi only on', () {
    late List<DownloadProgress> seen;
    const grace = Duration(milliseconds: 20);

    /// Past the moment a stop read on Wi-Fi waits for the reading.
    Future<void> graceOver() async {
      await Future<void>.delayed(grace * 3);
      await pumpEventQueue();
    }

    setUp(() async {
      downloads = BackgroundModelDownloads(
        models,
        settings,
        downloader,
        _Storage(free: 1 << 30),
        grace,
      );
      seen = <DownloadProgress>[];
      final sub = downloads.watch('hymt').listen(seen.add);
      addTearDown(sub.cancel);
      await downloads.attach();
      downloader.isWiFi = true;
      await downloads.start('hymt');
      await report((t) => TaskStatusUpdate(t, TaskStatus.running), 'one.gguf');
      await report((t) => TaskProgressUpdate(t, 0.5), 'one.gguf');
      await report((t) => TaskStatusUpdate(t, TaskStatus.running), 'two.gguf');
      downloader.calls.clear();
    });

    test('the file the system stopped comes back canceled: waiting for '
        'Wi-Fi, not failed, with nothing cancelled and nothing lost', () async {
      downloader.isWiFi = false;
      await report((t) => TaskStatusUpdate(t, TaskStatus.canceled), 'one.gguf');
      // The other file still runs until its own stop comes.
      expect(seen.last.phase, DownloadPhase.running);
      expect(downloader.calls, isEmpty, reason: 'nothing is cancelled');
      await report((t) => TaskStatusUpdate(t, TaskStatus.canceled), 'two.gguf');
      // 150 of 400 bytes, as before the drop.
      expect(seen.last, (
        phase: DownloadPhase.waitingForWifi,
        progress: 150 / 400,
      ));
      expect(downloader.calls, isEmpty);
    });

    test('the stop can come before the downloader hears Wi-Fi go: it is '
        'given a moment to, and waits', () async {
      await report((t) => TaskStatusUpdate(t, TaskStatus.canceled), 'one.gguf');
      downloader.isWiFi = false;
      await graceOver();
      await report((t) => TaskStatusUpdate(t, TaskStatus.canceled), 'two.gguf');
      expect(seen.last.phase, DownloadPhase.waitingForWifi);
      expect(downloader.calls, isEmpty);
    });

    test("a newer word on the file while its stop waits stands", () async {
      await report((t) => TaskStatusUpdate(t, TaskStatus.canceled), 'one.gguf');
      await report((t) => TaskProgressUpdate(t, 0.6), 'one.gguf');
      await graceOver();
      expect(seen.last, (phase: DownloadPhase.running, progress: 180 / 400));
      expect(downloader.calls, isEmpty);
    });

    test('back on Wi-Fi, the platform runs it again: downloading', () async {
      downloader.isWiFi = false;
      await report((t) => TaskStatusUpdate(t, TaskStatus.canceled), 'one.gguf');
      downloader.isWiFi = true;
      await report((t) => TaskStatusUpdate(t, TaskStatus.running), 'one.gguf');
      await report((t) => TaskProgressUpdate(t, 0.6), 'one.gguf');
      expect(seen.last, (phase: DownloadPhase.running, progress: 180 / 400));
    });

    test('the failed attempt\'s own cancels, late and off Wi-Fi, change '
        'nothing: its failed file holds it failed', () async {
      await report((t) => TaskStatusUpdate(t, TaskStatus.failed), 'two.gguf');
      expect(downloader.calls, <String>['cancel hymt']);
      downloader.isWiFi = false;
      await report((t) => TaskStatusUpdate(t, TaskStatus.canceled), 'one.gguf');
      expect(seen.last.phase, DownloadPhase.failed);
      expect(downloader.calls, <String>['cancel hymt']);
    });

    test('on Wi-Fi, a cancel no one here asked for (the notification\'s '
        '*Cancel*) is not a stop: failed, *Retry*', () async {
      await report((t) => TaskStatusUpdate(t, TaskStatus.canceled), 'one.gguf');
      await graceOver();
      expect(seen.last.phase, DownloadPhase.failed);
    });

    test(
      'with Wi-Fi only off, a cancel no one here asked for fails at once',
      () async {
        await settings.write(SettingKeys.modelsWifiOnly, false);
        downloader.isWiFi = false;
        await report(
          (t) => TaskStatusUpdate(t, TaskStatus.canceled),
          'one.gguf',
        );
        expect(seen.last.phase, DownloadPhase.failed);
      },
    );
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

    test('#428 a file that fails stops the rest of the attempt, once, so the '
        'one notification ends as failed', () async {
      final seen = <DownloadProgress>[];
      final sub = downloads.watch('hymt').listen(seen.add);
      addTearDown(sub.cancel);
      downloader.calls.clear();
      await report((t) => TaskStatusUpdate(t, TaskStatus.running), 'one.gguf');
      expect(downloader.calls, isEmpty);
      await report((t) => TaskStatusUpdate(t, TaskStatus.failed), 'two.gguf');
      expect(seen.last.phase, DownloadPhase.failed);
      expect(downloader.calls, <String>['cancel hymt']);
      await report((t) => TaskStatusUpdate(t, TaskStatus.canceled), 'one.gguf');
      expect(downloader.calls, <String>['cancel hymt']);
    });

    test('#428 a file waiting for the downloader\'s own retry is not a '
        'failure: nothing is cancelled', () async {
      downloader.isWiFi = true;
      final seen = <DownloadPhase>[];
      final sub = downloads.watch('hymt').listen((p) => seen.add(p.phase));
      addTearDown(sub.cancel);
      downloader.calls.clear();
      await report(
        (t) => TaskStatusUpdate(t, TaskStatus.waitingToRetry),
        'two.gguf',
      );
      expect(seen.last, DownloadPhase.running);
      expect(downloader.calls, isEmpty);
    });

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

    test('Retry after a checksum failure throws the files away and queues '
        'them all again', () async {
      await land('one.gguf', one);
      await land('two.gguf', 'corrupt');
      await report((t) => TaskStatusUpdate(t, TaskStatus.complete), 'one.gguf');
      await report((t) => TaskStatusUpdate(t, TaskStatus.complete), 'two.gguf');
      await settled();
      downloader.queued.clear();
      await downloads.retry('hymt');
      final staging = await models.stagingFor('hymt');
      expect(File('${staging.path}/two.gguf').existsSync(), isFalse);
      expect(downloader.queued.map((t) => t.filename), <String>[
        'one.gguf',
        'two.gguf',
      ]);
    });

    test('#156 Retry after a network failure keeps what arrived, and '
        'cancels the failed attempt', () async {
      await land('one.gguf', one);
      await report((t) => TaskStatusUpdate(t, TaskStatus.complete), 'one.gguf');
      await report((t) => TaskStatusUpdate(t, TaskStatus.failed), 'two.gguf');
      downloader.queued.clear();
      await downloads.retry('hymt');
      expect(downloader.calls, contains('cancel hymt'));
      expect(downloader.queued.map((t) => t.filename), <String>['two.gguf']);
      final staging = await models.stagingFor('hymt');
      expect(File('${staging.path}/one.gguf').readAsStringSync(), one);
    });

    test(
      '#428 Retry after a failed file checks the space for what did not '
      'arrive: a disk still full is refused, and nothing is fetched',
      () async {
        final storage = _Storage(free: 400 + ModelDownloads.spaceMargin);
        downloads = BackgroundModelDownloads(
          models,
          settings,
          downloader,
          storage,
        );
        downloader.queued.clear();
        await downloads.attach();
        await downloads.start('hymt');
        await land('one.gguf', one);
        await report(
          (t) => TaskStatusUpdate(t, TaskStatus.complete),
          'one.gguf',
        );
        await report((t) => TaskStatusUpdate(t, TaskStatus.failed), 'two.gguf');
        downloader.queued.clear();
        // The disk that failed two.gguf (100 bytes): 50 bytes left.
        storage.free = 50;
        await expectLater(
          downloads.retry('hymt'),
          throwsA(
            isA<NotEnoughSpace>().having(
              (e) => e.bytes,
              'bytes',
              100 + ModelDownloads.spaceMargin - 50,
            ),
          ),
        );
        expect(downloader.queued, isEmpty);
        // Room for the missing file and the margin, not the whole model.
        storage.free = 100 + ModelDownloads.spaceMargin;
        await downloads.retry('hymt');
        expect(downloader.queued.map((t) => t.filename), <String>['two.gguf']);
      },
    );

    test(
      '#428 and after a checksum failure, the whole model must fit',
      () async {
        final storage = _Storage(free: 400 + ModelDownloads.spaceMargin);
        downloads = BackgroundModelDownloads(
          models,
          settings,
          downloader,
          storage,
        );
        downloader.queued.clear();
        await downloads.attach();
        await downloads.start('hymt');
        await land('one.gguf', one);
        await land('two.gguf', 'corrupt');
        await report(
          (t) => TaskStatusUpdate(t, TaskStatus.complete),
          'one.gguf',
        );
        await report(
          (t) => TaskStatusUpdate(t, TaskStatus.complete),
          'two.gguf',
        );
        await settled();
        downloader.queued.clear();
        storage.free = 50;
        await expectLater(
          downloads.retry('hymt'),
          throwsA(isA<NotEnoughSpace>()),
        );
        expect(downloader.queued, isEmpty);
      },
    );

    test('#156 a task Retry replaced has no say', () async {
      await report((t) => TaskStatusUpdate(t, TaskStatus.failed), 'two.gguf');
      final old = downloader.queued.firstWhere((t) => t.filename == 'two.gguf');
      downloader.queued.clear();
      await downloads.retry('hymt');
      await report((t) => TaskStatusUpdate(t, TaskStatus.running), 'two.gguf');
      downloader.updates$.add(TaskStatusUpdate(old, TaskStatus.canceled));
      await pumpEventQueue();
      expect(
        (await downloads.watch('hymt').first).phase,
        DownloadPhase.running,
      );
    });
  });
}

class _Downloader implements FileDownloader {
  final List<DownloadTask> queued = <DownloadTask>[];

  /// The downloader's own reading of the network: off Wi-Fi until a test
  /// says otherwise.
  @override
  bool isWiFi = false;

  final List<String> calls = <String>[];
  final StreamController<TaskUpdate> updates$ =
      StreamController<TaskUpdate>.broadcast();
  RequireWiFi? wifi;
  bool? rescheduled;
  TaskNotification? running;
  String? notification;
  bool? progressBar;

  @override
  final _Records database = _Records();

  @override
  Stream<TaskUpdate> get updates => updates$.stream;

  @override
  Future<bool> cancelAll({Iterable<Task>? tasks, String? group}) async {
    calls.add('cancel $group');
    return true;
  }

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
    rescheduled = rescheduleRunningTasks as bool;
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

/// The downloader's record of its tasks, which outlives the app.
class _Records implements Database {
  final List<TaskRecord> records = <TaskRecord>[];

  @override
  Future<List<TaskRecord>> allRecords({String? group}) async => <TaskRecord>[
    for (final record in records)
      if (group == null || record.group == group) record,
  ];

  @override
  Future<void> deleteAllRecords({String? group}) async =>
      records.removeWhere((record) => group == null || record.group == group);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A phone with [free] bytes to spare.
class _Storage implements DeviceStorage {
  _Storage({required this.free});

  int free;

  @override
  Future<StorageSpace?> space() async => (free: free, total: free * 10);
}

/// A repository whose rename into place fails, as on a full disk.
class _RenameRefused extends ModelRepository {
  _RenameRefused(super.settings, {super.support});

  @override
  Future<ModelStatus> activate(String modelId, ModelVariant variant) =>
      throw const FileSystemException('rename refused');
}
