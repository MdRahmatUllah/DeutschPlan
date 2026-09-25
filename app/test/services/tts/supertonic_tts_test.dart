import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/model_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/synthesis_cache.dart';
import 'package:deutschplan/services/tts/supertonic_tts.dart';
import 'package:deutschplan/services/tts/tts_engine.dart';
import 'package:flutter_test/flutter_test.dart';

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

    const style = '{"style_ttl": {}, "style_dp": {}}';

    setUp(() async {
      support = Directory.systemTemp.createTempSync('dp_supertonic');
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
                regionExcluded: const <String>[],
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

    tearDown(() {
      try {
        support.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows lets go a moment later.
      }
    });

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
  });
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
  final List<Completer<void>> _ends = <Completer<void>>[];
  int stops = 0;
  bool fail = false;
  bool disposed = false;

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
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async => disposed = true;
}
