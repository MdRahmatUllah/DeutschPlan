import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/repositories/model_repository.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/data/repositories/synthesis_cache.dart';
import 'package:sogda/services/model_downloads.dart';
import 'package:sogda/services/tts/supertonic_tts.dart';
import 'package:sogda/services/tts/tts_engine.dart';
import 'package:sogda/services/tts/tts_service.dart' show VoiceRelease;

import '../../db/content_fixture.dart' show tempDir;
import '../../timing.dart';

/// `SupertonicTts` (#152): the engine over a fake voice and player, and the
/// pipeline's own arithmetic against the reference SDK's numbers. The ONNX
/// sessions themselves run on the device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the pipeline, as the SDK has it', () {
    // Supertonic 3's tts.json.
    const config = SupertonicConfig(
      sampleRate: 44100,
      baseChunkSize: 512,
      chunkCompressFactor: 6,
      latentDim: 24,
    );

    test('#152 the latent is 144 channels, a frame per 3072 samples: 19 '
        'frames for "Haus" (1.28 s) and 35 for the greeting (2.39 s), as the '
        'SDK made them', () {
      expect(config.latentChannels, 144);
      expect(config.latentFrames(1.28), 19);
      expect(config.latentFrames(2.39), 35);
      expect(config.latentFrames(3072 / 44100), 1);
      expect(config.latentFrames(3073 / 44100), 2);
    });

    test('#152 the noise is the standard normal, for an odd length too', () {
      final noise = OrtSupertonicModel.gaussian(20001, math.Random(7));
      final mean = noise.reduce((a, b) => a + b) / noise.length;
      final variance =
          noise.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) /
          noise.length;
      expect(mean.abs(), lessThan(0.03));
      expect(variance, closeTo(1, 0.05));
      expect(noise.last, isNot(0));
    });

    test('#152 a clip is a mono 16-bit PCM WAV at the model\'s rate, clipped '
        'to full scale', () {
      final wav = SupertonicTts.wavBytes(
        Float32List.fromList(<double>[0, 0.5, -0.5, 1, 2, -2]),
        44100,
      );
      final bytes = ByteData.sublistView(wav);
      expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
      expect(ascii.decode(wav.sublist(8, 16)), 'WAVEfmt ');
      expect(bytes.getUint16(20, Endian.little), 1, reason: 'PCM');
      expect(bytes.getUint16(22, Endian.little), 1, reason: 'mono');
      expect(bytes.getUint32(24, Endian.little), 44100);
      expect(bytes.getUint16(34, Endian.little), 16);
      expect(bytes.getUint32(40, Endian.little), 12);
      expect(wav.length, 44 + 12);
      expect(
        <int>[
          for (var i = 0; i < 6; i++) bytes.getInt16(44 + i * 2, Endian.little),
        ],
        <int>[0, 16384, -16384, 32767, 32767, -32767],
      );
    });

    test('#712 a clip is encoded in an isolate of its own, byte for byte the '
        'same', () async {
      final samples = Float32List.fromList(<double>[0, 0.5, -0.5, 1, 2, -2]);
      expect(
        await SupertonicTts.wavInIsolate(samples, 44100),
        SupertonicTts.wavBytes(samples, 44100),
      );
    });
  });

  group('the engine', () {
    late Directory support;
    late SettingsRepository settings;
    late ModelRepository models;
    late SynthesisCache cache;
    late _Model model;
    late List<Directory> loads;
    late _Player player;
    late SupertonicTts tts;

    /// A voice style, as the download has it: [value] fills both tensors.
    String styleOf(double value) => jsonEncode(<String, Object?>{
      'style_ttl': <String, Object?>{
        'dims': <int>[1, 1, 2],
        'data': <Object?>[
          <Object?>[
            <double>[value, value],
          ],
        ],
      },
      'style_dp': <String, Object?>{
        'dims': <int>[1, 1, 2],
        'data': <Object?>[
          <Object?>[
            <double>[value, value],
          ],
        ],
      },
    });
    final style = styleOf(1);

    setUp(() async {
      support = tempDir('sg_supertonic');
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
                id: ModelRepository.voiceModel,
                name: 'Supertonic 3 voice',
                licence: 'test',
                disables: 'tts_engine',
                variants: <ModelVariant>[
                  ModelVariant(
                    id: 'default',
                    name: 'Supertonic 3',
                    files: <ModelFile>[
                      ModelFile(
                        name: 'F1.json',
                        url: Uri.parse('https://example.invalid/F1.json'),
                        bytes: style.length,
                        sha256: sha256.convert(utf8.encode(style)).toString(),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      cache = SynthesisCache(support: support);
      model = _Model();
      loads = <Directory>[];
      player = _Player();
      tts = SupertonicTts(
        models: models,
        settings: settings,
        cache: cache,
        load: (dir) async {
          loads.add(dir);
          return model;
        },
        player: player,
      );
    });

    /// Until the model has been asked for [n] clips: the disk is real.
    Future<void> untilAsked(int n) async {
      await until(() => model.asked.length >= n);
    }

    Future<void> install() async {
      final staging = await models.beginDownload(ModelRepository.voiceModel);
      File('${staging.path}/F1.json').writeAsStringSync(style);
      final entry = (await models.manifest()).model(
        ModelRepository.voiceModel,
      )!;
      expect(
        await models.activate(entry.id, entry.variants.first),
        ModelStatus.ready,
      );
    }

    test('#152 is the supertonic engine of tts_engine', () {
      expect(tts.name, 'supertonic');
    });

    test('#152 without the verified model: not available, and speak says no '
        'without loading anything', () async {
      expect(await tts.isAvailable(), isFalse);
      expect(await tts.speak('Haus'), isFalse);
      expect(loads, isEmpty);
    });

    test('#152 the first time: opens the model, synthesises in F1 at the '
        'SDK\'s normal pace, caches the clip and plays it', () async {
      await install();
      final states = <TtsState>[];
      final sub = tts.state.listen(states.add);
      addTearDown(sub.cancel);

      expect(await tts.isAvailable(), isTrue);
      expect(await tts.speak('Haus'), isTrue);
      await pumpEventQueue();

      expect(loads.single.path, endsWith(ModelRepository.voiceModel));
      expect(model.asked, <(String, String, double)>[
        ('Haus', 'F1.json', 1.05),
      ], reason: 'Anna is F1 (#245)');
      final clip = await cache.fileFor('Haus', voice: 'Anna', speed: 1);
      expect(clip.existsSync(), isTrue);
      expect(player.played.single.path, clip.path);
      expect(states, <TtsState>[
        TtsState.loading,
        TtsState.playing,
      ], reason: 'speak resolves once the clip plays, as the phone voice does');
      player.finish();
      await pumpEventQueue();
      expect(states.last, TtsState.idle, reason: 'the clip ended');
    });

    test('#152 the second time comes from the cache: nothing synthesised, '
        'no loading', () async {
      await install();
      await tts.speak('Haus');
      final states = <TtsState>[];
      final sub = tts.state.listen(states.add);
      addTearDown(sub.cancel);

      await tts.speak('Haus');
      player.finish();
      await pumpEventQueue();
      expect(model.asked, hasLength(1));
      expect(loads, hasLength(1), reason: 'the sessions stay open');
      expect(player.played, hasLength(2));
      expect(states, <TtsState>[TtsState.playing, TtsState.idle]);
    });

    test('#152 FR-T2-09 the slow long-press is its own clip, synthesised at '
        '0.75 of the normal pace', () async {
      await install();
      await tts.speak('Haus');
      await tts.speak('Haus', speed: 0.75);
      expect(model.asked.last.$3, closeTo(1.05 * 0.75, 1e-9));
      expect(
        (await cache.fileFor('Haus', voice: 'Anna', speed: 0.75)).existsSync(),
        isTrue,
      );
    });

    test('#152 Jonas is M1 and Lena F2, the owner\'s styles, through the one '
        'open model', () async {
      await install();
      for (final (name, style) in <(String, String)>[
        ('Jonas', 'M1.json'),
        ('Lena', 'F2.json'),
      ]) {
        await settings.write(SettingKeys.ttsVoice, name);
        await tts.speak('Haus');
        expect(model.asked.last.$2, style, reason: name);
        expect(
          (await cache.fileFor('Haus', voice: name, speed: 1)).existsSync(),
          isTrue,
          reason: 'a clip is cached per voice',
        );
      }
      expect(loads, hasLength(1), reason: 'a voice is a style, not a reload');
    });

    test('#152 a voice this download does not have speaks as Anna', () async {
      await install();
      await settings.write(SettingKeys.ttsVoice, 'Klaus');
      await tts.speak('Haus');
      expect(model.asked.single.$2, 'F1.json');
      expect(
        (await cache.fileFor('Haus', voice: 'Anna', speed: 1)).existsSync(),
        isTrue,
      );
    });

    test('#152 a synthesis that fails throws, for the service to fall back, '
        'and leaves the speaker idle', () async {
      await install();
      model.fail = true;
      final states = <TtsState>[];
      final sub = tts.state.listen(states.add);
      addTearDown(sub.cancel);

      await expectLater(tts.speak('Haus'), throwsStateError);
      await pumpEventQueue();
      expect(states.last, TtsState.idle);
      expect(player.played, isEmpty);
      expect(await tts.isAvailable(), isTrue, reason: 'one text failed');
    });

    test('#152 a model that fails to open is remembered for the session: the '
        'next tap goes straight to the phone\'s voice', () async {
      await install();
      tts = SupertonicTts(
        models: models,
        settings: settings,
        cache: cache,
        load: (dir) async {
          loads.add(dir);
          throw const FileSystemException('out of memory');
        },
        player: player,
      );
      await expectLater(tts.speak('Haus'), throwsA(isA<FileSystemException>()));
      expect(await tts.isAvailable(), isFalse);
      expect(await tts.speak('Haus'), isFalse);
      expect(loads, hasLength(1));
    });

    test(
      '#152 a clip that cannot be played is thrown out of the cache',
      () async {
        await install();
        await tts.speak('Haus');
        player.fail = true;
        await expectLater(tts.speak('Haus'), throwsStateError);
        expect(
          (await cache.fileFor('Haus', voice: 'Anna', speed: 1)).existsSync(),
          isFalse,
        );
      },
    );

    test(
      '#152 a model that has gone is let go of: its sessions close',
      () async {
        await install();
        await tts.speak('Haus');
        (await models.directoryFor(ModelRepository.voiceModel))
            .deleteSync(recursive: true);
        expect(await tts.isAvailable(), isFalse);
        expect(model.closed, isTrue);
      },
    );

    test('#155 #436 a download of the voice that lands (M4 Update) '
        'reopens the model from its files, and its old clips go', () async {
      await install();
      final downloads = StreamController<DownloadProgress>();
      addTearDown(downloads.close);
      var failing = false;
      tts = SupertonicTts(
        models: models,
        settings: settings,
        cache: cache,
        load: (dir) async {
          loads.add(dir);
          if (failing) throw const FileSystemException('out of memory');
          return model;
        },
        player: player,
        downloads: downloads.stream,
      );
      await tts.speak('Haus');
      downloads.add((phase: DownloadPhase.running, progress: 0.5));
      await pumpEventQueue();
      expect(model.closed, isFalse, reason: 'not while it downloads');

      downloads.add((phase: DownloadPhase.ready, progress: 1));
      await pumpEventQueue();
      expect(model.closed, isTrue);
      expect(
        (await cache.fileFor('Haus', voice: 'Anna', speed: 1)).existsSync(),
        isFalse,
        reason: "the old model's clip",
      );
      await tts.speak('Haus');
      expect(loads, hasLength(2));
      expect(model.asked, hasLength(2));

      // A failure to open is forgotten once new files land.
      failing = true;
      downloads
        ..add((phase: DownloadPhase.running, progress: 0.5))
        ..add((phase: DownloadPhase.ready, progress: 1));
      await pumpEventQueue();
      await expectLater(tts.speak('Tür'), throwsA(isA<FileSystemException>()));
      expect(await tts.isAvailable(), isFalse);
      failing = false;
      downloads
        ..add((phase: DownloadPhase.running, progress: 0.5))
        ..add((phase: DownloadPhase.ready, progress: 1));
      await pumpEventQueue();
      expect(await tts.isAvailable(), isTrue);
    });

    test("#155 a rebuilt engine hearing the manager's last word, ready, "
        'reloads nothing', () async {
      await install();
      final downloads = StreamController<DownloadProgress>();
      addTearDown(downloads.close);
      tts = SupertonicTts(
        models: models,
        settings: settings,
        cache: cache,
        load: (dir) async {
          loads.add(dir);
          return model;
        },
        player: player,
        downloads: downloads.stream,
      );
      await tts.speak('Haus');
      downloads.add((phase: DownloadPhase.ready, progress: 1));
      await pumpEventQueue();
      expect(model.closed, isFalse);
      expect(
        (await cache.fileFor('Haus', voice: 'Anna', speed: 1)).existsSync(),
        isTrue,
      );
    });

    test('#155 a reload lets the clip in synthesis finish before the '
        'sessions close under it', () async {
      await install();
      model.gate = Completer<void>();
      final speaking = tts.speak('Haus');
      await until(() => model.asked.isNotEmpty);
      final reloading = tts.reload();
      await pumpEventQueue();
      expect(model.closed, isFalse, reason: 'still synthesising');
      model.gate!.complete();
      expect(await speaking, isTrue);
      await reloading;
      expect(model.closed, isTrue);
    });

    test('#155 a model deleted takes its clips with it', () async {
      await install();
      await tts.speak('Haus');
      (await models.directoryFor(ModelRepository.voiceModel))
          .deleteSync(recursive: true);
      expect(await tts.isAvailable(), isFalse);
      expect(
        (await cache.fileFor('Haus', voice: 'Anna', speed: 1)).existsSync(),
        isFalse,
      );
    });

    test('#430 prepare makes each clip ahead, in order, into the cache, '
        'without playing', () async {
      await install();
      await tts.prepare(<String>['das Haus', 'die Tür'], speed: 1.25);
      expect(model.asked, <(String, String, double)>[
        ('das Haus', 'F1.json', 1.05 * 1.25),
        ('die Tür', 'F1.json', 1.05 * 1.25),
      ]);
      expect(player.played, isEmpty);
      expect(
        (await cache.fileFor(
          'die Tür',
          voice: 'Anna',
          speed: 1.25,
        )).existsSync(),
        isTrue,
      );
      // Its first speak plays from the cache.
      await tts.speak('das Haus', speed: 1.25);
      expect(model.asked, hasLength(2));
      expect(player.played, hasLength(1));
    });

    test('#430 a speak for a clip being made waits for it, rather than '
        'making it twice', () async {
      await install();
      model.gate = Completer<void>();
      final preparing = tts.prepare(<String>['das Haus']);
      await untilAsked(1);
      final speaking = tts.speak('das Haus');
      await pumpEventQueue();
      model.gate!.complete();
      await preparing;
      expect(await speaking, isTrue);
      expect(model.asked, hasLength(1));
      expect(player.played, hasLength(1));
    });

    test('#430 a newer prepare replaces the list; a stop stops only its own '
        'list', () async {
      await install();
      model.gate = Completer<void>();
      final one = <String>['eins', 'zwei', 'drei'];
      final first = tts.prepare(one);
      await untilAsked(1);
      final second = tts.prepare(<String>['vier', 'fünf']);
      // The replaced screen's stop comes after the new list (FR-T3-02).
      await tts.stopPreparing(one);
      model.gate!.complete();
      await Future.wait(<Future<void>>[first, second]);
      expect(model.asked.map((a) => a.$1), <String>['eins', 'vier', 'fünf']);

      model.gate = Completer<void>();
      final two = <String>['sechs', 'sieben'];
      final third = tts.prepare(two);
      await untilAsked(4);
      await tts.stopPreparing(two);
      model.gate!.complete();
      await third;
      expect(model.asked.last.$1, 'sechs');
    });

    test('#430 a list makes its first ${SupertonicTts.prepareLimit} clips, '
        'no more: the cache keeps them all', () async {
      await install();
      await tts.prepare(<String>[for (var i = 0; i < 45; i++) 'Wort $i']);
      expect(model.asked, hasLength(SupertonicTts.prepareLimit));
      expect(model.asked.last.$1, 'Wort ${SupertonicTts.prepareLimit - 1}');
    });

    test(
      "#430 a speak's clip goes first: the list's next clip waits for it",
      () async {
        await install();
        final list = model.gate = Completer<void>();
        final preparing = tts.prepare(<String>['eins', 'zwei']);
        await untilAsked(1);
        final tap = model.gate = Completer<void>();
        final speaking = tts.speak('Haus', speed: 0.75);
        await untilAsked(2);
        list.complete();
        // Until the list's first clip is written, and a moment more: without
        // the wait for the speak, the list would ask for its next clip here.
        final eins = await cache.fileFor('eins', voice: 'Anna', speed: 1);
        await until(eins.existsSync);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(model.asked.map((a) => a.$1), <String>['eins', 'Haus']);

        tap.complete();
        expect(await speaking, isTrue);
        await preparing;
        expect(model.asked.map((a) => a.$1), <String>['eins', 'Haus', 'zwei']);
      },
    );

    for (final (what, act) in <(String, Future<void> Function(SupertonicTts))>[
      ('a reload', (tts) => tts.reload()),
      ('dispose', (tts) => tts.dispose()),
    ]) {
      test(
        "#430 $what stops the list: it doesn't open the sessions again",
        () async {
          await install();
          model.gate = Completer<void>();
          final preparing = tts.prepare(<String>['eins', 'zwei']);
          await untilAsked(1);
          final acting = act(tts);
          model.gate!.complete();
          await Future.wait(<Future<void>>[preparing, acting]);
          expect(model.asked.map((a) => a.$1), <String>['eins']);
          expect(loads, hasLength(1));
        },
      );
    }

    test('#430 a voice chosen while a list is made stops it', () async {
      await install();
      model.gate = Completer<void>();
      final preparing = tts.prepare(<String>['eins', 'zwei']);
      await untilAsked(1);
      await settings.write(SettingKeys.ttsVoice, 'Jonas');
      model.gate!.complete();
      await preparing;
      expect(model.asked.map((a) => a.$1), <String>['eins']);
    });

    test('#430 without the model, nothing is made; a failure stops it '
        'quietly', () async {
      await tts.prepare(<String>['das Haus']);
      expect(loads, isEmpty);

      await install();
      model.fail = true;
      await tts.prepare(<String>['das Haus', 'die Tür']);
      expect(model.asked, hasLength(1), reason: 'stopped at the first');
    });

    test('#486 the first clip a list makes is loaded into the player, once, '
        'while nothing has been said', () async {
      await install();
      await tts.prepare(<String>['das Haus', 'die Tür']);
      final first = await cache.fileFor('das Haus', voice: 'Anna', speed: 1);
      expect(player.loaded.single.path, first.path);
      await tts.prepare(<String>['die Straße']);
      expect(player.loaded, hasLength(1), reason: 'once');
      expect(player.played, isEmpty, reason: 'loaded, not played');
    });

    test('#486 a load that fails, interrupted by a speak, leaves the rest '
        'of the list to be made', () async {
      await install();
      player.failLoad = true;
      await tts.prepare(<String>['das Haus', 'die Tür', 'die Straße']);
      expect(player.loaded, hasLength(1));
      expect(model.asked.map((a) => a.$1), hasLength(3));
    });

    test('#486 after a speak the player is left alone: a load would stop '
        'its sound', () async {
      await install();
      await tts.speak('Haus');
      await tts.prepare(<String>['das Haus']);
      expect(player.loaded, isEmpty);
    });

    test('#638 memory pressure closes the sessions, and the next speak '
        'opens them again', () async {
      await install();
      final observer = VoiceRelease(tts.release);
      WidgetsBinding.instance.addObserver(observer);
      addTearDown(() => WidgetsBinding.instance.removeObserver(observer));
      await tts.speak('Haus');
      expect(loads, hasLength(1));

      WidgetsBinding.instance.handleMemoryPressure();
      await pumpEventQueue();
      expect(model.closed, isTrue);
      expect(
        (await cache.fileFor('Haus', voice: 'Anna', speed: 1)).existsSync(),
        isTrue,
        reason: 'the clips made stay',
      );

      await tts.speak('die Tür');
      expect(loads, hasLength(2));
    });

    test('#638 release stops the list being made: its next clip would open '
        'the sessions again', () async {
      await install();
      final list = tts.prepare(<String>['das Haus', 'die Tür', 'die Straße']);
      await tts.release();
      await list;
      expect(model.asked.length, lessThan(3), reason: 'the list stopped');
      expect(
        loads.isEmpty || model.closed,
        isTrue,
        reason: 'nothing left open',
      );
    });

    test('#906 one set of sessions at a time: a speak during a release waits '
        'for the old set to close before it opens the new', () async {
      await install();
      final closedAtLoad = <bool>[];
      tts = SupertonicTts(
        models: models,
        settings: settings,
        cache: cache,
        load: (dir) async {
          loads.add(dir);
          closedAtLoad.add(model.closed);
          return model;
        },
        player: player,
      );
      model.gate = Completer<void>();
      final first = tts.speak('Haus');
      await until(() => loads.length == 1);
      final released = tts.release();
      final second = tts.speak('die Tür');
      // A wait for something not to happen: the second speak reaching its
      // load while the first set is still open.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(loads, hasLength(1), reason: 'not while the old set is open');

      model.gate!.complete();
      await first;
      await released;
      expect(await second, isTrue);
      expect(closedAtLoad, <bool>[false, true]);
    });

    test('#906 a load that fails after a release leaves the newer load '
        'owned: its sessions still close', () async {
      await install();
      final failing = Completer<SupertonicModel>();
      final newer = _Model();
      var calls = 0;
      tts = SupertonicTts(
        models: models,
        settings: settings,
        cache: cache,
        load: (dir) => ++calls == 1 ? failing.future : Future.value(newer),
        player: player,
      );
      final first = tts.speak('Haus');
      await until(() => calls == 1);
      final released = tts.release();
      final second = tts.speak('die Tür');
      // Time for the second speak to reach its own load before the first
      // fails, the order the bug needs: longer on a busy machine, never red.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      failing.completeError(StateError('not enough memory'));
      await expectLater(first, throwsStateError);
      await released;
      expect(await second, isTrue);

      await tts.release();
      expect(newer.closed, isTrue);
    });

    test('#906 the list a release stopped goes on after the next speak, and '
        'one its screen stopped does not', () async {
      await install();
      final list = <String>['das Haus', 'die Tür', 'die Straße'];
      final files = <File>[
        for (final text in list)
          await cache.fileFor(text, voice: 'Anna', speed: 1),
      ];

      final prepared = tts.prepare(list);
      await tts.release();
      await prepared;
      await tts.speak('das Haus');
      await until(() => files.every((file) => file.existsSync()));

      final other = <String>['der Tisch', 'die Lampe'];
      final again = tts.prepare(other);
      await tts.release();
      await again;
      await tts.stopPreparing(other);
      await tts.speak('der Tisch');
      // A wait for something not to happen: its list would have made it by
      // now, as the one above did.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(model.asked.map((a) => a.$1), isNot(contains('die Lampe')));
    });

    test('#638 with nothing open, release opens nothing', () async {
      await install();
      await tts.release();
      expect(loads, isEmpty);
    });

    test('#152 disposed: the sessions close, and the player goes', () async {
      await install();
      await tts.speak('Haus');
      await tts.dispose();
      expect(model.closed, isTrue);
      expect(player.disposed, isTrue);
    });

    test(
      '#152 stopped while it synthesises: the clip is kept, not played',
      () async {
        await install();
        model.gate = Completer<void>();
        final speaking = tts.speak('Haus');
        await pumpEventQueue();
        await tts.stop();
        model.gate!.complete();
        expect(await speaking, isTrue);
        expect(player.played, isEmpty);
        expect(player.stops, 1);
        expect(
          (await cache.fileFor('Haus', voice: 'Anna', speed: 1)).existsSync(),
          isTrue,
        );
      },
    );

    test('#453 Anna, Jonas and Lena all speak in one engine, through the '
        'ONNX model: each voice after the first, too', () async {
      final onnx = _Onnx();
      addTearDown(onnx.uninstall);
      await install();
      final model = await models.directoryFor(ModelRepository.voiceModel);
      _writeConfig(model);
      File('${model.path}/M1.json').writeAsStringSync(styleOf(2));
      File('${model.path}/F2.json').writeAsStringSync(styleOf(3));
      final engine = SupertonicTts(
        models: models,
        settings: settings,
        cache: cache,
        load: OrtSupertonicModel.load,
        player: player,
      );
      addTearDown(engine.dispose);

      for (final name in <String>['Anna', 'Jonas', 'Lena']) {
        await settings.write(SettingKeys.ttsVoice, name);
        expect(await engine.speak('Hallo'), isTrue, reason: name);
      }
      expect(player.played, hasLength(3));
      expect(onnx.sessions, 4, reason: 'one model, opened once');
      expect(onnx.styles, <List<double>>[
        <double>[1, 1],
        <double>[2, 2],
        <double>[3, 3],
      ], reason: "F1's, M1's and F2's own style, in turn");
    });

    test('#627 a session that fails to open closes the ones opened before '
        'it', () async {
      final onnx = _Onnx()..failOn = 3;
      addTearDown(onnx.uninstall);
      final model = Directory('${support.path}/model')..createSync();
      _writeConfig(model);

      await expectLater(
        OrtSupertonicModel.load(model),
        throwsA(isA<PlatformException>()),
      );
      expect(onnx.closed, <String>[
        'duration_predictor.onnx',
        'text_encoder.onnx',
      ]);
    });

    test('#627 a session that fails to close leaves none of the others '
        'open', () async {
      final onnx = _Onnx()..failClose = 'duration_predictor.onnx';
      addTearDown(onnx.uninstall);
      final model = Directory('${support.path}/model')..createSync();
      _writeConfig(model);

      await (await OrtSupertonicModel.load(model)).close();
      expect(onnx.closed, <String>[
        'text_encoder.onnx',
        'vector_estimator.onnx',
        'vocoder.onnx',
      ]);
    });
  });
}

/// Supertonic 3's `tts.json` and `unicode_indexer.json`, as small as the
/// loader takes them.
void _writeConfig(Directory model) {
  File('${model.path}/tts.json').writeAsStringSync(
    jsonEncode(<String, Object?>{
      'ae': <String, Object?>{'sample_rate': 44100, 'base_chunk_size': 512},
      'ttl': <String, Object?>{'chunk_compress_factor': 6, 'latent_dim': 24},
    }),
  );
  File('${model.path}/unicode_indexer.json')
      .writeAsStringSync(jsonEncode(List<int>.generate(128, (i) => i)));
}

/// `flutter_onnxruntime`'s channel, stubbed: what `OrtSupertonicModel` asks
/// of it, with each session's one output. The duration predictor says 0.1 s,
/// and the others give zeros.
class _Onnx {
  _Onnx() {
    _messenger.setMockMethodCallHandler(_channel, _handle);
  }

  static const MethodChannel _channel = MethodChannel('flutter_onnxruntime');
  static final TestDefaultBinaryMessenger _messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final Map<String, Object?> _values = <String, Object?>{};
  var _ids = 0;

  /// The sessions opened.
  int sessions = 0;

  /// The session (1 is the first) whose open fails, as out of memory would.
  int? failOn;

  /// The sessions closed, by file name.
  final List<String> closed = <String>[];

  /// The session, by file name, whose close fails.
  String? failClose;

  /// The style each clip's duration was predicted in, in order.
  final List<List<double>> styles = <List<double>>[];

  void uninstall() => _messenger.setMockMethodCallHandler(_channel, null);

  String _value(Object? data) {
    final id = 'v${_ids++}';
    _values[id] = data;
    return id;
  }

  List<Object?> _output(Float32List data) => <Object?>[
    _value(data),
    'float32',
    <int>[data.length],
  ];

  Future<Object?> _handle(MethodCall call) async {
    final args = call.arguments as Map<Object?, Object?>?;
    switch (call.method) {
      case 'createSession':
        sessions++;
        if (sessions == failOn) {
          throw PlatformException(code: 'OOM', message: 'out of memory');
        }
        return <String, Object?>{
          'sessionId': (args!['modelPath']! as String).split('/').last,
          'inputNames': <String>[],
          'outputNames': <String>['out'],
        };
      case 'createOrtValue':
        return <String, Object?>{
          'valueId': _value(args!['data']),
          'dataType': args['sourceType'],
          'shape': args['shape'],
        };
      case 'runInference':
        final inputs = args!['inputs']! as Map<Object?, Object?>;
        if (args['sessionId'] != 'duration_predictor.onnx') {
          return <String, Object?>{'out': _output(Float32List(8192))};
        }
        final dp = (inputs['style_dp']! as Map<Object?, Object?>)['valueId'];
        styles.add(List<double>.from(_values[dp]! as List<Object?>));
        return <String, Object?>{
          'out': _output(Float32List.fromList(<double>[0.1])),
        };
      case 'getOrtValueData':
        return <String, Object?>{'data': _values[args!['valueId']]};
      case 'closeSession':
        final id = args!['sessionId']! as String;
        if (id == failClose) throw PlatformException(code: 'CLOSE');
        closed.add(id);
        return null;
      default:
        // releaseOrtValue.
        return null;
    }
  }
}

class _Model implements SupertonicModel {
  final List<(String, String, double)> asked = <(String, String, double)>[];
  bool fail = false;
  bool closed = false;
  Completer<void>? gate;

  @override
  int get sampleRate => 44100;

  @override
  Future<Float32List> synthesize(
    String text, {
    required String style,
    required double speed,
  }) async {
    asked.add((text, style, speed));
    await gate?.future;
    if (fail) throw StateError('synthesis failed');
    return Float32List.fromList(<double>[0, 0.25, -0.25]);
  }

  @override
  Future<void> close() async => closed = true;
}

class _Player implements ClipPlayer {
  final List<File> played = <File>[];

  /// The clips loaded ahead of a play.
  final List<File> loaded = <File>[];
  final List<Completer<void>> _ends = <Completer<void>>[];
  int stops = 0;
  bool fail = false;
  bool disposed = false;

  /// A load that throws, as just_audio's does when a speak interrupts it.
  bool failLoad = false;

  /// The last clip ends.
  void finish() => _ends.last.complete();

  @override
  Future<({Future<void> ended})> play(File clip) async {
    if (fail) throw StateError('cannot play');
    played.add(clip);
    _ends.add(Completer<void>());
    return (ended: _ends.last.future);
  }

  @override
  Future<void> load(File clip) async {
    loaded.add(clip);
    if (failLoad) throw StateError('interrupted');
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async => disposed = true;
}
