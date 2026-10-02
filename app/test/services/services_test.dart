import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/repositories/model_repository.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/services/model_downloads.dart';
import 'package:sogda/services/tts/system_tts.dart';
import 'package:sogda/services/tts/tts_engine.dart';

import '../db/content_fixture.dart' show tempDir;

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
      support = tempDir('sogda_models');
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

    group("#755 the phone's TTS engine died under the app", () {
      // A speak goes unanswered for [stuck], and a binding may take
      // [rebinding]: short here, seconds on a phone.
      SystemTts engine(_FakeFlutterTts tts) => SystemTts(
        tts,
        const Duration(milliseconds: 50),
        const Duration(milliseconds: 200),
      );

      test('a speak it parked: bound again, the replay stopped, German '
          'said again', () async {
        final tts = _FakeFlutterTts(available: true)..dead = true;

        expect(await engine(tts).speak('Guten Tag!'), isTrue);
        expect(tts.calls, <String>[
          'setLanguage de-DE',
          'setSpeechRate 0.5',
          'speak Guten Tag!',
          'setEngine com.google.android.tts',
          'stop',
          'setLanguage de-DE',
          'setSpeechRate 0.5',
          'speak Guten Tag!',
        ]);
      });

      test('a speak it answered 0: bound again too', () async {
        final tts = _FakeFlutterTts(available: true)..nextSpeak = 0;

        expect(await engine(tts).speak('Guten Tag!'), isTrue);
        expect(tts.calls, contains('setEngine com.google.android.tts'));
      });

      test('no engine comes back: no, so the no-voice state shows (#452), '
          'not silence', () async {
        final tts = _FakeFlutterTts(available: true)
          ..dead = true
          ..neverBinds = true;

        expect(await engine(tts).speak('Guten Tag!'), isFalse);
        expect(
          tts.calls.last,
          'setEngine com.google.android.tts',
          reason: 'given up at once, not spoken into nothing again',
        );
      });

      test('asked for its engine, the plugin never answers: no, in the '
          'bound', () async {
        final tts = _FakeFlutterTts(available: true)
          ..dead = true
          ..engineUnanswered = true;

        expect(await engine(tts).speak('Guten Tag!'), isFalse);
      });

      test('bound again and still no German: the next question binds no '
          'more', () async {
        final tts = _FakeFlutterTts(available: true);
        final voice = engine(tts);
        expect(await voice.isAvailable(), isTrue);

        tts.available = false;
        expect(await voice.isAvailable(), isFalse);
        expect(await voice.isAvailable(), isFalse);
        expect(tts.calls.where((c) => c.startsWith('setEngine')), hasLength(1));
      });

      test('no engine on the phone at all: no', () async {
        final tts = _FakeFlutterTts(available: true)
          ..dead = true
          ..defaultEngine = null;

        expect(await engine(tts).speak('Guten Tag!'), isFalse);
      });

      test('killed after German was there, every question reads "not '
          'bound": bound again once, and it speaks', () async {
        // On the emulator: `isLanguageAvailable failed: not bound to TTS
        // engine`, so the speak never reached the engine at all.
        final tts = _FakeFlutterTts(available: true);
        final voice = engine(tts);
        expect(await voice.speak('Hallo'), isTrue);

        tts
          ..dead = true
          ..unboundSaysNo = true
          ..calls.clear();
        expect(await voice.speak('Guten Tag!'), isTrue);
        expect(tts.calls, <String>[
          'setEngine com.google.android.tts',
          'setLanguage de-DE',
          'setSpeechRate 0.5',
          'speak Guten Tag!',
        ]);
      });

      test(
        'a phone that never had German is not bound again on every tap',
        () async {
          final tts = _FakeFlutterTts(available: false);

          expect(await engine(tts).speak('Guten Tag!'), isFalse);
          expect(tts.calls, isNot(contains(startsWith('setEngine'))));
        },
      );
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

    test('V03 a stop that overtakes a speak still setting up the voice '
        'keeps it silent (#153)', () async {
      final tts = _FakeFlutterTts(available: true);
      final engine = SystemTts(tts);
      final spoke = engine.speak('Hallo');
      await engine.stop();
      expect(await spoke, isTrue, reason: 'stopped, not failed');
      expect(tts.calls, isNot(contains('speak Hallo')));

      expect(await engine.speak('Tschüss'), isTrue);
      expect(tts.calls.last, 'speak Tschüss', reason: 'the next one speaks');
      await engine.dispose();
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
  bool isWiFi = true;

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
  }) => this;

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

  Object available;
  final bool throws;
  final List<String> calls = <String>[];

  /// #755: the engine's process died. flutter_tts parks a speak until an
  /// engine starts, and replays it then.
  bool dead = false;

  /// #755: what the next speak answers, once (flutter_tts says 0 for no).
  Object? nextSpeak;

  /// #755: a new binding that never comes up.
  bool neverBinds = false;

  /// #755: the phone's default engine, if it has one.
  Object? defaultEngine = 'com.google.android.tts';

  /// #755: asked for its default engine, the plugin never answers.
  bool engineUnanswered = false;

  final List<Completer<dynamic>> _parked = <Completer<dynamic>>[];

  @override
  Future<dynamic> get getDefaultEngine => engineUnanswered
      ? Completer<dynamic>().future
      : Future<dynamic>.value(defaultEngine);

  @override
  Future<dynamic> setEngine(String engine) {
    calls.add('setEngine $engine');
    if (neverBinds) return Completer<dynamic>().future;
    dead = false;
    for (final parked in _parked) {
      parked.complete(1);
    }
    _parked.clear();
    return Future<dynamic>.value(1);
  }

  @override
  Future<dynamic> isLanguageAvailable(String language) async {
    if (throws) throw PlatformException(code: 'TTS', message: 'not bound');
    if (dead && unboundSaysNo) return false;
    return available;
  }

  /// #755: a dead engine answers no to every question (the emulator's
  /// "isLanguageAvailable failed: not bound to TTS engine").
  bool unboundSaysNo = false;

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
  Future<dynamic> speak(String text, {bool focus = false}) {
    calls.add('speak $text');
    if (dead) {
      final parked = Completer<dynamic>();
      _parked.add(parked);
      return parked.future;
    }
    final answer = nextSpeak ?? 1;
    nextSpeak = null;
    return Future<dynamic>.value(answer);
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
