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
import 'package:deutschplan/services/model_downloads.dart';
import 'package:deutschplan/services/tts/supertonic_tts.dart';
import 'package:deutschplan/services/tts/tts_engine.dart';
import 'package:flutter/services.dart';
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
      for (var i = 0; i < 500 && model.asked.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
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
      File('${model.path}/tts.json').writeAsStringSync(
        jsonEncode(<String, Object?>{
          'ae': <String, Object?>{'sample_rate': 44100, 'base_chunk_size': 512},
          'ttl': <String, Object?>{
            'chunk_compress_factor': 6,
            'latent_dim': 24,
          },
        }),
      );
      File('${model.path}/unicode_indexer.json')
          .writeAsStringSync(jsonEncode(List<int>.generate(128, (i) => i)));
      File('${model.path}/M1.json').writeAsStringSync(styleOf(2));
      File('${model.path}/F2.json').writeAsStringSync(styleOf(3));
      final tts = SupertonicTts(
        models: models,
        settings: settings,
        cache: cache,
        load: OrtSupertonicModel.load,
        player: player,
      );

      for (final name in <String>['Anna', 'Jonas', 'Lena']) {
        await settings.write(SettingKeys.ttsVoice, name);
        expect(await tts.speak('Hallo'), isTrue, reason: name);
      }
      expect(player.played, hasLength(3));
      expect(onnx.sessions, 4, reason: 'one model, opened once');
      expect(onnx.styles, <List<double>>[
        <double>[1, 1],
        <double>[2, 2],
        <double>[3, 3],
      ], reason: "F1's, M1's and F2's own style, in turn");
    });
  });
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
      default:
        // releaseOrtValue, closeSession.
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
