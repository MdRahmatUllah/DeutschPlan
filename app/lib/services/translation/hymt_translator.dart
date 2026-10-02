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

  /// One at a time: a second request, or a release, waits for the first.
  Future<void> _turn = Future<void>.value();

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
  }) {
    if (!languageNames.containsKey(from) || !languageNames.containsKey(to)) {
      throw ArgumentError(
        'Hy-MT2 is asked for $from → $to only among '
        '${languageNames.keys.join(', ')}',
      );
    }
    return _inTurn(() async {
      if (!_settings.read(SettingKeys.mtEnabled)) return null;
      final path = await _modelPath();
      if (path == null) return null;
      final out = (await _runner.complete(
        path,
        promptFor(text, to: to),
      )).trim();
      return out.isEmpty ? null : out;
    });
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
  Future<void> release() => _inTurn(_runner.release);

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

  @override
  Future<String> complete(String modelPath, String prompt) async {
    final engine = await _open(modelPath);
    final out = StringBuffer();
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
      if (chunk.choices.isEmpty) continue;
      final text = chunk.choices.first.delta.content;
      if (text != null) out.write(text);
    }
    return out.toString();
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
