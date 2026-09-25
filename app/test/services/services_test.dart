import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/model_repository.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/services/model_downloads.dart';
import 'package:deutschplan/services/tts/system_tts.dart';
import 'package:deutschplan/services/tts/tts_engine.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// The seams S2 page 5 stands on (#91). The page's own tests fake these;
/// these are the real ones, with only the plugin behind each faked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FR-S2-06 BackgroundModelDownloads', () {
    late Directory support;
    late ModelRepository models;
    late SettingsRepository settings;
    late _FakeDownloader downloader;

    setUp(() async {
      support = Directory.systemTemp.createTempSync('deutschplan_models');
      final db = AppDatabase.memory();
      addTearDown(db.close);
      settings = SettingsRepository(db);
      await settings.load();
      addTearDown(settings.dispose);
      models = ModelRepository(settings, support: support);
      // The bundled manifest with Supertonic's files pinned: `start` fetches
      // nothing that could never verify (#156), and the real hashes wait on
      // #245.
      final bundled = await models.manifest();
      final voice = bundled.model('supertonic3')!;
      models.useManifest(
        ModelManifest(
          version: bundled.version,
          models: <ModelEntry>[
            ModelEntry(
              id: voice.id,
              name: voice.name,
              licence: voice.licence,
              disables: voice.disables,
              regionExcluded: voice.regionExcluded,
              variants: <ModelVariant>[
                for (final variant in voice.variants)
                  ModelVariant(
                    id: variant.id,
                    name: variant.name,
                    files: <ModelFile>[
                      for (final file in variant.files)
                        ModelFile(
                          name: file.name,
                          url: file.url,
                          bytes: file.bytes,
                          sha256: '0' * 64,
                        ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      );
      downloader = _FakeDownloader();
    });

    tearDown(() {
      try {
        support.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows lets go of the directory a moment later.
      }
    });

    test("queues every file of the voice, from the manifest", () async {
      await BackgroundModelDownloads(
        models,
        settings,
        downloader,
      ).start('supertonic3');

      final manifest = await models.manifest();
      final files = manifest.model('supertonic3')!.variants.first.files;
      expect(
        downloader.queued.map((t) => (t.url, t.filename)),
        files.map((f) => (f.url.toString(), f.name)),
      );
    });

    test('into the staging directory ModelRepository verifies', () async {
      // The bytes have to land where `verify` looks, or a finished download
      // is a download nothing can find.
      await BackgroundModelDownloads(
        models,
        settings,
        downloader,
      ).start('supertonic3');

      for (final task in downloader.queued) {
        expect(task.baseDirectory, BaseDirectory.applicationSupport);
        expect(task.directory, ModelRepository.stagingPath('supertonic3'));
      }
      final staging = await models.stagingFor('supertonic3');
      expect(
        staging.path,
        '${support.path}/${ModelRepository.stagingPath('supertonic3')}',
      );
      expect(staging.existsSync(), isTrue, reason: 'made ready for them');
    });

    test('and refuses a model the manifest does not have', () async {
      expect(
        BackgroundModelDownloads(models, settings, downloader).start('nothing'),
        throwsArgumentError,
      );
      expect(downloader.queued, isEmpty);
    });
  });

  group('V01 SystemTts', () {
    test('is the `system` engine of the tts_engine setting', () {
      expect(SystemTts(_FakeFlutterTts(available: true)).name, 'system');
    });

    test('speaks German when the phone has a German voice', () async {
      final tts = _FakeFlutterTts(available: true);

      expect(await SystemTts(tts).speak('Guten Tag!'), isTrue);
      expect(tts.calls, <String>[
        'setLanguage de-DE',
        'setSpeechRate 0.5',
        'speak Guten Tag!',
      ]);
    });

    test(
      'FR-T2-09 the speed is halved: flutter_tts reads 0.5 as normal',
      () async {
        final tts = _FakeFlutterTts(available: true);

        await SystemTts(tts).speak('Guten Tag!', speed: 0.75);
        expect(tts.calls, contains('setSpeechRate 0.375'));
      },
    );

    test('and says no, silently, when it does not', () async {
      // False rather than a speak call into nothing: page 5 tells the learner
      // there is no German voice instead of showing a speaker that is mute.
      final tts = _FakeFlutterTts(available: false);

      expect(await SystemTts(tts).speak('Guten Tag!'), isFalse);
      expect(tts.calls, isEmpty);
    });

    test('and a platform error is a no, not a throw', () async {
      // An engine that failed to bind throws from the channel. Page 5 relies
      // on false to show the slashed speaker.
      final tts = _FakeFlutterTts(available: true, throws: true);

      expect(await SystemTts(tts).speak('Guten Tag!'), isFalse);
    });

    test('an answer that is not a plain yes is a no', () async {
      final tts = _FakeFlutterTts(available: 1);

      expect(await SystemTts(tts).speak('Guten Tag!'), isFalse);
    });

    test('V01 isAvailable reports the German voice honestly', () async {
      // The speaker is slashed on this answer (accessibility-performance.md),
      // so "maybe" and "the engine threw" are both no.
      expect(
        await SystemTts(_FakeFlutterTts(available: true)).isAvailable(),
        isTrue,
      );
      expect(
        await SystemTts(_FakeFlutterTts(available: false)).isAvailable(),
        isFalse,
      );
      expect(
        await SystemTts(_FakeFlutterTts(available: 1)).isAvailable(),
        isFalse,
      );
      expect(
        await SystemTts(_FakeFlutterTts(available: true, throws: true))
            .isAvailable(),
        isFalse,
      );
    });

    test('V01 a callback after dispose is ignored, not thrown', () async {
      // An utterance can finish after its container is gone.
      final tts = _FakeFlutterTts(available: true);
      final engine = SystemTts(tts);
      await engine.dispose();

      tts.onDone!();
      tts.onStart!();
      await engine.stop();
    });

    test('V01 state: playing while sound is out, idle when it ends, is '
        'cancelled, fails or is stopped', () async {
      final tts = _FakeFlutterTts(available: true);
      final engine = SystemTts(tts);
      final states = <TtsState>[];
      final sub = engine.state.listen(states.add);

      tts.onStart!();
      tts.onDone!();
      tts.onStart!();
      tts.onCancel!();
      tts.onStart!();
      tts.onError!('synthesis failed');
      tts.onStart!();
      await engine.stop();
      await pumpEventQueue();

      expect(states, <TtsState>[
        for (var i = 0; i < 4; i++) ...<TtsState>[
          TtsState.playing,
          TtsState.idle,
        ],
      ]);
      expect(tts.calls, <String>['stop']);
      await sub.cancel();
      await engine.dispose();
    });
  });
}

class _FakeDownloader implements FileDownloader {
  final List<DownloadTask> queued = <DownloadTask>[];

  @override
  Future<List<bool>> enqueueAll(Iterable<Task> tasks) async {
    queued.addAll(tasks.cast<DownloadTask>());
    return <bool>[for (final _ in tasks) true];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFlutterTts implements FlutterTts {
  _FakeFlutterTts({required this.available, this.throws = false});

  final Object available;
  final bool throws;
  final List<String> calls = <String>[];

  @override
  Future<dynamic> isLanguageAvailable(String language) async {
    if (throws) throw PlatformException(code: 'TTS', message: 'not bound');
    return available;
  }

  @override
  Future<dynamic> setLanguage(String language) async {
    calls.add('setLanguage $language');
    return 1;
  }

  @override
  Future<dynamic> setSpeechRate(double rate) async {
    calls.add('setSpeechRate $rate');
    return 1;
  }

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    calls.add('speak $text');
    return 1;
  }

  @override
  Future<dynamic> stop() async {
    calls.add('stop');
    return 1;
  }

  void Function()? onStart;
  void Function()? onDone;
  void Function()? onCancel;
  void Function(dynamic)? onError;

  @override
  void setStartHandler(void Function() callback) => onStart = callback;

  @override
  void setCompletionHandler(void Function() callback) => onDone = callback;

  @override
  void setCancelHandler(void Function() callback) => onCancel = callback;

  @override
  void setErrorHandler(void Function(dynamic) handler) => onError = handler;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
