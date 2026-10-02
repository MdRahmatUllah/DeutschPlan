import 'dart:async';

import 'package:llamadart/llamadart.dart';
import 'package:sogda/data/repositories/model_repository.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/services/model_downloads.dart';
import 'package:sogda/services/translation/translator.dart';

/// The model behind [HyMtTranslator]: a prompt in, its completion out.
/// llamadart in the app ([LlamaRunner]); a fake in the tests, which read the
/// exact prompt each direction sends.
abstract interface class TranslationRunner {
  /// [prompt] as the one user message, through the model's own chat
  /// template, sampled as the model card asks (`translation.md`). Loads the
  /// model at [modelPath] first, unless it is the one already loaded.
  Future<String> complete(String modelPath, String prompt);

  /// Stops the [complete] under way, if one is: it returns at once, with
  /// what it had.
  void cancel();

  /// Lets go of the model: the next [complete] loads it again.
  Future<void> release();
}

/// On-device translation with Hy-MT2-1.8B, Q4_K_M (`translation.md`, ADR 30,
/// #154). Answers null, as [UnavailableTranslator] does, while `mt_enabled`
/// is off or the model isn't on the phone, so `translation_cache` keeps
/// nothing of it then.
class HyMtTranslator implements Translator {
  HyMtTranslator({
    required this._models,
    required this._settings,
    TranslationRunner? runner,
    Stream<DownloadProgress>? downloads,
    this.limit = const Duration(seconds: 60),
  }) : _runner = runner ?? LlamaRunner() {
    // A new download of the model landed: the next translation loads it.
    _landed = downloads?.listen((progress) {
      if (progress.phase == DownloadPhase.ready) unawaited(release());
    });
  }

  final ModelRepository _models;
  final SettingsRepository _settings;
  final TranslationRunner _runner;
  StreamSubscription<DownloadProgress>? _landed;

  /// The languages it is asked for, named as the card's prompt names them:
  /// German and each meaning language the app offers.
  static const Map<String, String> languageNames = <String, String>{
    'de': 'German',
    'en': 'English',
    'bn': 'Bengali',
    'ru': 'Russian',
    'pl': 'Polish',
  };

  /// The model card's prompt for every pair that isn't Chinese, with no
  /// system prompt (`translation.md`).
  static String promptFor(String text, {required String to}) =>
      'Translate the following text into ${languageNames[to]}. Note that '
      'you should only output the translated result without any additional '
      'explanation:\n\n$text';

  @override
  String get model => 'hymt2-1.8b-q4km';

  /// The least memory Hy-MT2 is offered with (#154, the lead's call): a
  /// "4 GB" phone, which reports 3.6 to 3.8 GiB, the kernel and the modem
  /// keeping the rest. On a 2 GB phone a translation took minutes.
  static const int memoryFloor = 3584 * 1024 * 1024;

  /// Whether a phone with [totalMemory] bytes runs it. One that won't say is
  /// offered, as the space check lets a phone that won't say download.
  static bool fitsIn(int? totalMemory) =>
      totalMemory == null || totalMemory >= memoryFloor;

  /// How long one translation may run: past it, it's stopped and answers
  /// null, so no screen waits forever (#154).
  final Duration limit;

  /// One at a time: a second request, or a release, waits for the first.
  Future<void> _turn = Future<void>.value();

  /// Raised by every [release]: a request from before it is dropped.
  int _epoch = 0;

  /// The request running now, if any: what [release] stops.
  Object? _running;

  Future<T> _inTurn<T>(Future<T> Function() work) {
    final done = _turn.then((_) => work());
    _turn = done.then<void>((_) {}, onError: (Object _) {});
    return done;
  }

  @override
  Future<String?> translate(
    String text, {
    required String from,
    required String to,
    Future<void>? abandoned,
  }) {
    if (!languageNames.containsKey(from) || !languageNames.containsKey(to)) {
      throw ArgumentError(
        'Hy-MT2 is asked for $from → $to only among '
        '${languageNames.keys.join(', ')}',
      );
    }
    // #154: on a phone where one takes minutes, a sheet closed or a screen
    // left must not hold the next translation behind its own.
    final epoch = _epoch;
    final request = Object();
    final answer = Completer<String?>();
    var gone = false;
    void stop() {
      if (identical(_running, request)) _runner.cancel();
    }

    void say(String? line) {
      if (!answer.isCompleted) answer.complete(line);
    }

    unawaited(
      abandoned?.then((_) {
        gone = true;
        stop();
      }),
    );
    bool dropped() => gone || epoch != _epoch;
    unawaited(
      _inTurn(() async {
        Timer? late;
        try {
          if (dropped() || !_settings.read(SettingKeys.mtEnabled)) {
            return say(null);
          }
          final path = await _modelPath();
          if (path == null || dropped()) return say(null);
          _running = request;
          // Past the limit the screen hears null at once; the turn still
          // waits for the stop, so the next one never runs beside it.
          late = Timer(limit, () {
            gone = true;
            stop();
            say(null);
          });
          final out = (await _runner.complete(
            path,
            promptFor(text, to: to),
          )).trim();
          // Stopped part-way: half a translation is none, and isn't cached.
          say(dropped() || out.isEmpty ? null : out);
        } on Object {
          // A load that failed, memory gone, a broken file: no answer, and
          // the engine let go, rather than an error W1's unawaited call
          // would never catch.
          say(null);
          try {
            await _runner.release();
          } on Object {
            // ponytail: a release that fails leaves nothing to undo; the
            // next translation loads again.
          }
        } finally {
          late?.cancel();
          _running = null;
        }
      }),
    );
    return answer.future;
  }

  /// The model's file, while it is on the phone and whole; otherwise null,
  /// and the engine let go of (a delete, or a model that broke).
  Future<String?> _modelPath() async {
    final entry = (await _models.manifest()).model(
      ModelRepository.translationModel,
    );
    if (entry == null || entry.variants.isEmpty) return null;
    final variant = entry.variants.first;
    // Unsized, as the voice asks on every clip (#712): the stamp, not a walk.
    final state = await _models.stateOf(entry, variant, sized: false);
    if (!state.isReady) {
      await _runner.release();
      return null;
    }
    final directory = await _models.directoryFor(entry.id);
    return '${directory.path}/${variant.files.single.name}';
  }

  /// Lets go of the model (~1.1 GB mapped): under memory pressure, in the
  /// background, and before a delete. The next translation loads it again.
  /// What runs is stopped and what waits is dropped, both answering null: a
  /// phone short of memory can't wait minutes for a translation to end.
  Future<void> release() {
    _epoch++;
    if (_running != null) _runner.cancel();
    return _inTurn(_runner.release);
  }

  Future<void> dispose() async {
    await _landed?.cancel();
    await release();
  }
}

/// llamadart's llama.cpp, which runs the model in its own worker isolate, so
/// no translation blocks the UI (`translation.md`).
class LlamaRunner implements TranslationRunner {
  LlamaEngine? _engine;
  String? _loaded;

  /// Set by [cancel]: also a cancel that came while the model loaded, which
  /// llamadart would not see, as no generation was listened to yet.
  bool _cancelled = false;

  @override
  Future<String> complete(String modelPath, String prompt) async {
    _cancelled = false;
    final engine = await _open(modelPath);
    final out = StringBuffer();
    if (_cancelled) return '';
    await for (final chunk in engine.create(
      <LlamaChatMessage>[
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: prompt),
      ],
      // The model card's sampling; 256 new tokens at most.
      params: const GenerationParams(
        maxTokens: 256,
        temp: 0.7,
        topP: 0.6,
        topK: 20,
        penalty: 1.05,
      ),
      enableThinking: false,
    )) {
      // Leaving the loop cancels the subscription, which stops the backend.
      if (_cancelled) break;
      if (chunk.choices.isEmpty) continue;
      final text = chunk.choices.first.delta.content;
      if (text != null) out.write(text);
    }
    return out.toString();
  }

  @override
  void cancel() {
    _cancelled = true;
    _engine?.cancelGeneration();
  }

  Future<LlamaEngine> _open(String modelPath) async {
    if (_engine case final engine? when _loaded == modelPath) return engine;
    await release();
    final engine = LlamaEngine(LlamaBackend());
    await engine.loadModel(
      modelPath,
      // A sentence and its translation fit in 1024; the default 4096 would
      // hold four times the cache. The file is mapped, not copied.
      modelParams: const ModelParams(
        contextSize: 1024,
        preferredBackend: GpuBackend.cpu,
      ),
    );
    _engine = engine;
    _loaded = modelPath;
    return engine;
  }

  @override
  Future<void> release() async {
    final engine = _engine;
    _engine = null;
    _loaded = null;
    await engine?.dispose();
  }
}
