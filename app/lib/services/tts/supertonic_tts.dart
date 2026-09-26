import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:deutschplan/data/repositories/model_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/synthesis_cache.dart';
import 'package:deutschplan/services/model_downloads.dart';
import 'package:deutschplan/services/tts/supertonic_text.dart';
import 'package:deutschplan/services/tts/tts_engine.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:just_audio/just_audio.dart';

/// Supertonic 3 on the phone's CPU (`tts.md`, #152): the downloaded model,
/// speaking German in the learner's voice, each clip cached on disk.
///
/// #153's `TtsService` chooses between this and the phone's voice. So a
/// failure throws rather than staying silent: the service falls back and
/// says so once.
class SupertonicTts implements TtsEngine, SpeechPrefetch {
  SupertonicTts({
    required this._models,
    required this._settings,
    required this._cache,
    SupertonicLoader? load,
    ClipPlayer? player,
    Stream<DownloadProgress>? downloads,
  }) : _load = load ?? OrtSupertonicModel.load,
       _player = player ?? JustAudioClipPlayer() {
    // A download of the voice that lands (M4's *Update*, or a new one) is new
    // files: the open sessions and the cached clips are the old model's.
    // A rebuilt engine hears the manager's last word first; a `ready` is a
    // landing only after a download this engine saw under way.
    var underWay = false;
    _landed = downloads?.listen((download) {
      if (download.phase != DownloadPhase.ready) {
        underWay = true;
      } else if (underWay) {
        underWay = false;
        unawaited(reload());
      }
    });
  }

  /// The learner's voices (`tts_voice`), each a voice style of the download:
  /// the owner's choice (#245, #152). Anna, the first, is the default.
  static const Map<String, String> voices = <String, String>{
    'Anna': 'F1.json',
    'Jonas': 'M1.json',
    'Lena': 'F2.json',
  };

  /// The model's speed for the app's 1: the SDK's natural pace.
  static const double normalSpeed = 1.05;

  /// The most clips a [prepare] makes ahead.
  // ponytail: 40, a day's session with its examples (7 new and a dozen
  // revisions is ~40 clips) and well inside the cache's 200, which a longer
  // list would evict its own look-ahead from. A backlog's *Study all* past
  // that makes its later cards on tap; a window re-sent as the session moves
  // is the upgrade.
  static const int prepareLimit = 40;

  final ModelRepository _models;
  final SettingsRepository _settings;
  final SynthesisCache _cache;
  final SupertonicLoader _load;
  final ClipPlayer _player;

  final StreamController<TtsState> _state =
      StreamController<TtsState>.broadcast();

  /// The four sessions, opened on the first clip and kept: they take seconds
  /// to open. A voice is only a style the open model is given.
  Future<SupertonicModel>? _model;

  /// A load that failed, remembered for the app session: a phone that can't
  /// hold the model (low memory, say) shouldn't make every tap wait seconds
  /// to learn it again before the phone's voice speaks.
  bool _broken = false;

  StreamSubscription<DownloadProgress>? _landed;

  /// What [isAvailable] said last, so a model that goes is let go of once.
  bool _wasAvailable = false;

  /// The clips being made, by their cache key: a speak for one that a
  /// [prepare] is making waits for it rather than making it twice.
  final Map<String, Future<File>> _making = <String, Future<File>>{};

  /// Each [prepare] takes a run; an older one stops at its next clip. So
  /// does [stopPreparing], a [reload] and [dispose].
  int _run = 0;

  /// The list [prepare] is making, for [stopPreparing] to know it by.
  List<String>? _list;

  /// The player has had a clip loaded ahead of its first play (#486).
  bool _primed = false;

  /// The clip a speak is making now, which a [prepare] waits for before it
  /// starts its next: the plugin shares one queue between them.
  Future<File>? _tapped;

  /// Each speak and stop takes a turn. A clip that was a turn behind by the
  /// time it was ready doesn't play: the learner has moved on.
  int _turn = 0;

  @override
  String get name => 'supertonic';

  @override
  Stream<TtsState> get state => _state.stream;

  /// Only a verified model speaks. An update waiting still has one. A model
  /// that has gone (deleted, or its files broken) is let go of.
  @override
  Future<bool> isAvailable() async {
    if (_broken) return false;
    final entry = (await _models.manifest()).model(ModelRepository.voiceModel);
    final status = entry == null || entry.variants.isEmpty
        ? ModelStatus.notDownloaded
        : (await _models.stateOf(entry, entry.variants.first)).status;
    final available =
        status == ModelStatus.ready || status == ModelStatus.updateAvailable;
    if (!available && _wasAvailable) {
      // It was here and has gone (M4's *Delete*): its sessions and its clips.
      await _release();
      await _cache.clear();
    }
    _wasAvailable = available;
    return available;
  }

  @override
  Future<bool> speak(String text, {double speed = 1}) async {
    // The turn is taken first, so a stop while the model is asked counts.
    final turn = ++_turn;
    if (!await isAvailable()) return false;
    final voice = _voice();
    try {
      var clip = await _cache.hit(text, voice: voice, speed: speed);
      if (clip == null) {
        _state.add(TtsState.loading);
        clip = await (_tapped = _clip(text, voice: voice, speed: speed));
      }
      if (turn != _turn) return true;
      final Future<void> ended;
      try {
        (:ended) = await _player.play(clip);
      } on Object {
        // A clip that can't be played isn't kept for the next tap.
        if (clip.existsSync()) clip.deleteSync();
        rethrow;
      }
      // Resolved once the sound starts, as the phone's voice is: `idle`
      // follows when the clip ends or is stopped.
      if (turn == _turn) _state.add(TtsState.playing);
      unawaited(
        ended.then((_) {
          if (turn == _turn) _state.add(TtsState.idle);
        }),
      );
    } on Object {
      if (turn == _turn) _state.add(TtsState.idle);
      rethrow;
    }
    return true;
  }

  @override
  Future<void> stop() async {
    _turn++;
    await _player.stop();
    _state.add(TtsState.idle);
  }

  /// Everything it holds: about 400 MB of sessions, the player and [state].
  Future<void> dispose() async {
    _turn++;
    _run++;
    await _landed?.cancel();
    await _release();
    await _player.dispose();
    await _state.close();
  }

  /// #430: [texts]' clips, made ahead into the cache, one at a time, the
  /// first [prepareLimit] of them. A clip a speak is making goes first.
  // ponytail: the plugin runs one call at a time, interleaved, so a speak of
  // another text shares the queue with the one clip in synthesis now, about
  // a second more at most; a priority queue in the plugin is the upgrade.
  @override
  Future<void> prepare(List<String> texts, {double speed = 1}) async {
    final run = ++_run;
    _list = texts;
    if (texts.isEmpty || !await isAvailable()) return;
    final voice = _voice();
    for (final text in texts.take(prepareLimit)) {
      try {
        await _tapped;
      } on Object {
        // Its speak says so.
      }
      // A newer list, a stop, or a voice the learner no longer has chosen.
      if (run != _run || _voice() != voice) return;
      try {
        final clip = await _clip(text, voice: voice, speed: speed);
        // #486: the player's first start (just_audio creating its platform
        // player, ~450 ms on the emulator) paid here, with the first clip,
        // not by card 1's speak. Only while nothing has been said: a load
        // would stop a sound under way.
        if (!_primed && _turn == 0) {
          _primed = true;
          // Not awaited, so the next clip isn't held back, and its own catch:
          // a speak during it interrupts it (just_audio), which mustn't end
          // the list.
          unawaited(() async {
            try {
              await _player.load(clip);
            } on Object {
              // Best effort: card 1 then pays the player's start, as before.
            }
          }());
        }
      } on Object {
        // The model can't make it now; a speak will say so, and fall back.
        return;
      }
    }
  }

  /// #460: the sessions opened at the app's start, so the first card of a
  /// session doesn't wait the ~2.3 s they take. A failure is remembered as a
  /// speak's is, and the next speak falls back at once.
  // ponytail: about 400 MB held from the start on a phone that speaks with
  // Supertonic, as they are from its first clip already; open on the first
  // speaker's screen instead if memory is tight on low-end phones.
  @override
  Future<void> warm() async {
    if (!await isAvailable()) return;
    try {
      await _open();
    } on Object {
      // Remembered in [_broken]; the next speak says so and falls back.
    }
  }

  @override
  Future<void> stopPreparing(List<String> texts) async {
    if (!identical(texts, _list)) return;
    _run++;
    _list = null;
  }

  /// The learner's voice, or Anna when this download hasn't theirs.
  String _voice() {
    final chosen = _settings.read(SettingKeys.ttsVoice);
    return voices.containsKey(chosen) ? chosen! : voices.keys.first;
  }

  /// [text]'s clip in [voice] at [speed]: the cache's, the one being made, or
  /// a new one.
  Future<File> _clip(
    String text, {
    required String voice,
    required double speed,
  }) async {
    final hit = await _cache.hit(text, voice: voice, speed: speed);
    if (hit != null) return hit;
    final key = SynthesisCache.keyFor(text, voice: voice, speed: speed);
    return _making[key] ??= () async {
      try {
        final model = await _open();
        final samples = await model.synthesize(
          text,
          style: voices[voice]!,
          speed: normalSpeed * speed,
        );
        return await _cache.write(
          text,
          voice: voice,
          speed: speed,
          bytes: wavBytes(samples, model.sampleRate),
        );
      } finally {
        unawaited(_making.remove(key));
      }
    }();
  }

  /// A new download of the voice is in place: the sessions open again from
  /// its files on the next clip, a failure to open is forgotten, and the old
  /// model's clips go (#436).
  Future<void> reload() async {
    _broken = false;
    _run++;
    await _release();
    await _cache.clear();
  }

  Future<SupertonicModel> _open() => _model ??= () async {
    try {
      return await _load(
        await _models.directoryFor(ModelRepository.voiceModel),
      );
    } on Object {
      _broken = true;
      _model = null;
      rethrow;
    }
  }();

  Future<void> _release() async {
    final model = _model;
    _model = null;
    if (model == null) return;
    // Sessions closed under a clip being made would fail it; the cache
    // cleared under its write would lose it.
    for (final making in _making.values.toList()) {
      try {
        await making;
      } on Object {
        // Its speak or prepare says so.
      }
    }
    try {
      await (await model).close();
    } on Object {
      // A model that never opened has nothing to close.
    }
  }

  /// [samples] (-1 to 1) as a mono 16-bit PCM WAV, which `just_audio` plays.
  static Uint8List wavBytes(Float32List samples, int sampleRate) {
    final data = samples.length * 2;
    final wav = ByteData(44 + data);
    void ascii(int at, String text) {
      for (var i = 0; i < text.length; i++) {
        wav.setUint8(at + i, text.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    wav.setUint32(4, 36 + data, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    wav
      ..setUint32(16, 16, Endian.little) // the fmt chunk's size
      ..setUint16(20, 1, Endian.little) // PCM
      ..setUint16(22, 1, Endian.little) // mono
      ..setUint32(24, sampleRate, Endian.little)
      ..setUint32(28, sampleRate * 2, Endian.little) // bytes a second
      ..setUint16(32, 2, Endian.little) // bytes a frame
      ..setUint16(34, 16, Endian.little); // bits a sample
    ascii(36, 'data');
    wav.setUint32(40, data, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      wav.setInt16(
        44 + i * 2,
        (samples[i].clamp(-1.0, 1.0) * 32767).round(),
        Endian.little,
      );
    }
    return wav.buffer.asUint8List();
  }
}

/// Supertonic 3, open: German text and a voice style in, samples out.
abstract interface class SupertonicModel {
  int get sampleRate;

  /// [style] is one of the model's voice style files; [speed] is the model's
  /// own, where [SupertonicTts.normalSpeed] is normal.
  Future<Float32List> synthesize(
    String text, {
    required String style,
    required double speed,
  });

  Future<void> close();
}

/// Opens [SupertonicModel] from the model's directory.
typedef SupertonicLoader = Future<SupertonicModel> Function(Directory model);

/// Plays a clip.
abstract interface class ClipPlayer {
  /// Starts [clip], and completes once it is playing, or throws when it can't
  /// be played. [ended] completes when the clip ends, or is stopped.
  Future<({Future<void> ended})> play(File clip);

  /// Makes [clip] ready to play without playing it: the player's own start
  /// is paid here (#486).
  Future<void> load(File clip);

  Future<void> stop();

  Future<void> dispose();
}

class JustAudioClipPlayer implements ClipPlayer {
  final AudioPlayer _player = AudioPlayer();

  @override
  Future<({Future<void> ended})> play(File clip) async {
    // A finished clip leaves `playing` true, and then `play` would return at
    // once, before the next clip is heard.
    await _player.stop();
    await _player.setFilePath(clip.path);
    // `play` completes when the clip ends or is stopped; a failure after the
    // start ends it too.
    return (ended: _player.play().catchError((Object _) {}));
  }

  @override
  Future<void> load(File clip) => _player.setFilePath(clip.path);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

/// Supertonic 3 through `flutter_onnxruntime`: the reference SDK's pipeline
/// (supertonic 1.3.1, `core.py` `Supertonic.__call__`), for one text.
///
/// The duration predictor and the text encoder read the ids, the vector
/// estimator denoises a random latent [steps] times, and the vocoder turns it
/// into samples. The plugin runs every call on one background queue for its
/// channel, so none of this is on the UI isolate, and two clips synthesise
/// one after the other. Dart builds the inputs, and the JSON is decoded in
/// `Isolate.run`.
class OrtSupertonicModel implements SupertonicModel {
  OrtSupertonicModel._(
    this._directory,
    this._text,
    this._config,
    this._duration,
    this._encoder,
    this._estimator,
    this._vocoder,
    this._random,
  );

  /// The denoising steps: the SDK's own default for a call is 5, its CLI's 8.
  // ponytail: 5, the latency the learner waits on (#152 measures it), for a
  // little quality. Raise it if a listening test asks for more.
  static const int steps = 5;

  static Future<SupertonicModel> load(
    Directory model, {
    math.Random? random,
  }) async {
    final config = SupertonicConfig.fromJson(
      await _json('${model.path}/tts.json') as Map<String, Object?>,
    );
    final indexer = (await _json(
      '${model.path}/unicode_indexer.json',
    ) as List<Object?>).cast<int>();

    // ponytail: two threads. On the host, 1 took 95 ms a denoising step, 2
    // and 4 took 59, and 8 took 74; more only fights the UI for cores.
    final options = OrtSessionOptions(intraOpNumThreads: 2);
    final runtime = OnnxRuntime();
    Future<OrtSession> open(String name) =>
        runtime.createSession('${model.path}/$name', options: options);

    return OrtSupertonicModel._(
      model,
      SupertonicText(indexer),
      config,
      await open('duration_predictor.onnx'),
      await open('text_encoder.onnx'),
      await open('vector_estimator.onnx'),
      await open('vocoder.onnx'),
      random ?? math.Random(),
    );
  }

  final Directory _directory;
  final SupertonicText _text;
  final SupertonicConfig _config;
  final OrtSession _duration;
  final OrtSession _encoder;
  final OrtSession _estimator;
  final OrtSession _vocoder;
  final math.Random _random;

  /// Each voice style, as its two tensors, loaded on its first clip and kept.
  final Map<String, Future<({OrtValue dp, OrtValue ttl})>> _styles =
      <String, Future<({OrtValue dp, OrtValue ttl})>>{};

  @override
  int get sampleRate => _config.sampleRate;

  // ponytail: one text, one pass. The SDK splits text over 300 characters
  // into chunks; content.db's longest example sentence is 141.
  @override
  Future<Float32List> synthesize(
    String text, {
    required String style,
    required double speed,
  }) async {
    final (:dp, :ttl) = await _style(style);
    final ids = _text.ids(text);
    final live = <OrtValue>[];
    Future<OrtValue> value(Object data, List<int> shape) async {
      final made = await OrtValue.fromList(data, shape);
      live.add(made);
      return made;
    }

    Future<OrtValue> run(
      OrtSession session,
      Map<String, OrtValue> feeds,
    ) async {
      final out = await session.run(feeds);
      live.addAll(out.values);
      return out[session.outputNames.first]!;
    }

    try {
      final textIds = await value(Int64List.fromList(ids), <int>[
        1,
        ids.length,
      ]);
      final textMask = await value(_ones(ids.length), <int>[1, 1, ids.length]);
      final predicted = await run(_duration, <String, OrtValue>{
        'text_ids': textIds,
        'style_dp': dp,
        'text_mask': textMask,
      });
      final seconds =
          ((await predicted.asFlattenedList()).first as num).toDouble() / speed;
      final embedding = await run(_encoder, <String, OrtValue>{
        'text_ids': textIds,
        'style_ttl': ttl,
        'text_mask': textMask,
      });

      final frames = _config.latentFrames(seconds);
      final shape = <int>[1, _config.latentChannels, frames];
      var latent = await value(
        gaussian(_config.latentChannels * frames, _random),
        shape,
      );
      // One text fills its whole latent, so the mask is all ones.
      final latentMask = await value(_ones(frames), <int>[1, 1, frames]);
      final total = await value(
        Float32List.fromList(<double>[steps + 0.0]),
        <int>[1],
      );
      for (var step = 0; step < steps; step++) {
        latent = await run(_estimator, <String, OrtValue>{
          'noisy_latent': latent,
          'text_emb': embedding,
          'style_ttl': ttl,
          'latent_mask': latentMask,
          'text_mask': textMask,
          'current_step': await value(
            Float32List.fromList(<double>[step + 0.0]),
            <int>[1],
          ),
          'total_step': total,
        });
      }
      final wav = await run(_vocoder, <String, OrtValue>{'latent': latent});
      final samples = await wav.asFlattenedList();
      // The vocoder fills whole latent frames; the speech is the predicted
      // duration of them.
      final keep = math.min(samples.length, (seconds * sampleRate).floor());
      // The plugin hands floats over as a Float32List: a view, not a copy.
      return samples is Float32List
          ? Float32List.sublistView(samples, 0, keep)
          : Float32List.fromList(<double>[
              for (var i = 0; i < keep; i++) (samples[i] as num).toDouble(),
            ]);
    } finally {
      for (final made in live) {
        await made.dispose();
      }
    }
  }

  @override
  Future<void> close() async {
    for (final style in _styles.values) {
      try {
        final (:dp, :ttl) = await style;
        await dp.dispose();
        await ttl.dispose();
      } on Object {
        // A style that never loaded holds nothing.
      }
    }
    _styles.clear();
    for (final session in <OrtSession>[
      _duration,
      _encoder,
      _estimator,
      _vocoder,
    ]) {
      await session.close();
    }
  }

  /// [file]'s two tensors, loaded once. A style that fails to load (a voice
  /// an older download lacks) is asked again next time.
  Future<({OrtValue dp, OrtValue ttl})> _style(String file) =>
      _styles[file] ??= () async {
        try {
          final styles = await _readStyle('${_directory.path}/$file');
          return (
            dp: await OrtValue.fromList(styles.dp.data, styles.dp.dims),
            ttl: await OrtValue.fromList(styles.ttl.data, styles.ttl.dims),
          );
        } on Object {
          _styles.remove(file)?.ignore();
          rethrow;
        }
      }();

  static Future<Object?> _json(String path) => Isolate.run(() => _decode(path));

  /// A voice style's two tensors' data, read off the UI isolate. Static, so
  /// its closure holds [path] alone: one made in [_style] carried this model,
  /// and from the second voice on its [_styles] holds a future, which no
  /// isolate can be sent (#453).
  static Future<({_Tensor dp, _Tensor ttl})> _readStyle(String path) =>
      Isolate.run(() {
        final styles = _decode(path);
        return (
          dp: _flatten(styles, 'style_dp'),
          ttl: _flatten(styles, 'style_ttl'),
        );
      });

  static Object? _decode(String path) =>
      jsonDecode(File(path).readAsStringSync());

  /// A voice style's `{dims, data}`, as the SDK's loader reads it.
  static _Tensor _flatten(Object? styles, String key) {
    final json =
        (styles! as Map<String, Object?>)[key]! as Map<String, Object?>;
    final values = <double>[];
    void flatten(Object? node) {
      if (node is List) {
        node.forEach(flatten);
      } else {
        values.add((node! as num).toDouble());
      }
    }

    flatten(json['data']);
    return (
      data: Float32List.fromList(values),
      dims: (json['dims']! as List<Object?>).cast<int>(),
    );
  }

  static Float32List _ones(int length) =>
      Float32List(length)..fillRange(0, length, 1);

  /// [length] samples of the standard normal, as the SDK's
  /// `np.random.randn`: Box–Muller over [random].
  static Float32List gaussian(int length, math.Random random) {
    final out = Float32List(length);
    for (var i = 0; i < length; i += 2) {
      final radius = math.sqrt(-2 * math.log(1 - random.nextDouble()));
      final angle = 2 * math.pi * random.nextDouble();
      out[i] = radius * math.cos(angle);
      if (i + 1 < length) out[i + 1] = radius * math.sin(angle);
    }
    return out;
  }
}

/// A tensor's data and its shape, before it's an `OrtValue`.
typedef _Tensor = ({Float32List data, List<int> dims});

/// What `tts.json` says the pipeline needs.
class SupertonicConfig {
  const SupertonicConfig({
    required this.sampleRate,
    required this.baseChunkSize,
    required this.chunkCompressFactor,
    required this.latentDim,
  });

  factory SupertonicConfig.fromJson(Map<String, Object?> json) {
    final ae = json['ae']! as Map<String, Object?>;
    final ttl = json['ttl']! as Map<String, Object?>;
    return SupertonicConfig(
      sampleRate: ae['sample_rate']! as int,
      baseChunkSize: ae['base_chunk_size']! as int,
      chunkCompressFactor: ttl['chunk_compress_factor']! as int,
      latentDim: ttl['latent_dim']! as int,
    );
  }

  final int sampleRate;
  final int baseChunkSize;
  final int chunkCompressFactor;
  final int latentDim;

  /// The latent's channels: 24 × 6 = 144 for Supertonic 3.
  int get latentChannels => latentDim * chunkCompressFactor;

  /// The latent frames [seconds] of speech take, as the SDK's
  /// `sample_noisy_latent`: each frame is 512 × 6 samples.
  int latentFrames(double seconds) {
    final chunk = baseChunkSize * chunkCompressFactor;
    return ((seconds * sampleRate + chunk - 1) / chunk).floor();
  }
}
