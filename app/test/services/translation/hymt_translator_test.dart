import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/repositories/model_repository.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/data/repositories/translation_repository.dart';
import 'package:sogda/services/model_downloads.dart';
import 'package:sogda/services/translation/hymt_translator.dart';

import '../../db/content_fixture.dart' show tempDir;

/// The model, faked: what it was asked, and what it answers.
class _Runner implements TranslationRunner {
  final List<(String, String)> asked = <(String, String)>[];
  int releases = 0;
  String answer = 'translated';

  /// Holds [complete] until completed: a translation still running.
  Completer<void>? gate;
  int cancels = 0;
  bool _stopped = false;

  @override
  Future<String> complete(String modelPath, String prompt) async {
    asked.add((modelPath, prompt));
    _stopped = false;
    await gate?.future;
    return _stopped ? 'half a transl' : answer;
  }

  /// As llamadart's: what runs returns at once, with what it had.
  @override
  void cancel() {
    cancels++;
    _stopped = true;
    if (gate case final gate? when !gate.isCompleted) gate.complete();
  }

  @override
  Future<void> release() async => releases++;
}

/// The repository, faked: each request's [abandoned], and no answer yet.
class _Asked extends Fake implements TranslationRepository {
  final List<Future<void>?> abandoned = <Future<void>?>[];

  @override
  Future<String?> translate(
    String text, {
    required String from,
    required String to,
    Future<void>? abandoned,
  }) {
    this.abandoned.add(abandoned);
    return Completer<String?>().future;
  }
}

void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  late ModelRepository models;
  late _Runner runner;
  late HyMtTranslator translator;
  late StreamController<DownloadProgress> downloads;

  const content = 'gguf';
  final variant = ModelVariant(
    id: 'q4_k_m',
    name: '4-bit build',
    files: <ModelFile>[
      ModelFile(
        name: 'Hy-MT2-1.8B-Q4_K_M.gguf',
        url: Uri.parse('https://example.invalid/model.gguf'),
        bytes: content.length,
        sha256: sha256.convert(utf8.encode(content)).toString(),
      ),
    ],
  );

  /// The model on the phone, whole.
  Future<void> install() async {
    final staging = await models.restartDownload(
      ModelRepository.translationModel,
    );
    File('${staging.path}/${variant.files.single.name}')
        .writeAsStringSync(content);
    await models.activate(ModelRepository.translationModel, variant);
  }

  setUp(() async {
    db = AppDatabase.memory();
    addTearDown(db.close);
    settings = SettingsRepository(db);
    await settings.load();
    addTearDown(settings.dispose);
    await settings.write(SettingKeys.mtEnabled, true);
    models = ModelRepository(settings, support: tempDir('sg_hymt'))
      ..useManifest(
        ModelManifest(
          version: 1,
          models: <ModelEntry>[
            ModelEntry(
              id: ModelRepository.translationModel,
              name: 'Hy-MT2 translation',
              licence: 'Apache-2.0',
              disables: 'mt_enabled',
              variants: <ModelVariant>[variant],
            ),
          ],
        ),
      );
    runner = _Runner();
    downloads = StreamController<DownloadProgress>.broadcast();
    addTearDown(downloads.close);
    translator = HyMtTranslator(
      models: models,
      settings: settings,
      runner: runner,
      downloads: downloads.stream,
    );
    addTearDown(translator.dispose);
  });

  test(
    '#154 the model card\'s prompt, word for word, with no system prompt',
    () async {
      await install();
      final result = await translator.translate(
        'Danke für Ihre Hilfe.',
        from: 'de',
        to: 'bn',
      );
      expect(result, 'translated');
      final (path, prompt) = runner.asked.single;
      expect(path, endsWith('/hymt/Hy-MT2-1.8B-Q4_K_M.gguf'));
      expect(
        prompt,
        'Translate the following text into Bengali. Note that you should only '
        'output the translated result without any additional explanation:\n\n'
        'Danke für Ihre Hilfe.',
      );
    },
  );

  test('#154 the eight directions: German into each meaning language and '
      'back, each named in English', () async {
    await install();
    const directions = <(String, String, String)>[
      ('de', 'en', 'English'),
      ('de', 'bn', 'Bengali'),
      ('de', 'ru', 'Russian'),
      ('de', 'pl', 'Polish'),
      ('en', 'de', 'German'),
      ('bn', 'de', 'German'),
      ('ru', 'de', 'German'),
      ('pl', 'de', 'German'),
    ];
    for (final (from, to, _) in directions) {
      await translator.translate('Text', from: from, to: to);
    }
    expect(
      <String>[for (final (_, prompt) in runner.asked) prompt],
      <String>[
        for (final (_, _, name) in directions)
          'Translate the following text into $name. Note that you should only '
              'output the translated result without any additional '
              'explanation:\n\nText',
      ],
    );
  });

  test('#154 a language it is not asked for is a mistake, not a prompt', () {
    expect(
      () => translator.translate('Text', from: 'de', to: 'fr'),
      throwsArgumentError,
    );
  });

  test('#154 the answer is trimmed, and an empty one is no answer', () async {
    await install();
    runner.answer = '  Thank you for your help.\n';
    expect(
      await translator.translate('Danke für Ihre Hilfe.', from: 'de', to: 'en'),
      'Thank you for your help.',
    );
    runner.answer = ' \n';
    expect(await translator.translate('Danke.', from: 'de', to: 'en'), isNull);
  });

  test('#154 with translation off, nothing is asked', () async {
    await install();
    await settings.write(SettingKeys.mtEnabled, false);
    expect(await translator.translate('Danke.', from: 'de', to: 'en'), isNull);
    expect(runner.asked, isEmpty);
  });

  test('#154 with no model on the phone, nothing is asked, and whatever was '
      'loaded goes', () async {
    expect(await translator.translate('Danke.', from: 'de', to: 'en'), isNull);
    expect(runner.asked, isEmpty);
    expect(runner.releases, 1);
  });

  test(
    '#154 one at a time: a second translation waits for the first',
    () async {
      await install();
      runner.gate = Completer<void>();
      final first = translator.translate('eins', from: 'de', to: 'en');
      final second = translator.translate('zwei', from: 'de', to: 'en');
      await pumpEventQueue();
      expect(runner.asked, hasLength(1), reason: 'the second waits');
      runner.gate!.complete();
      await Future.wait(<Future<String?>>[first, second]);
      expect(runner.asked, hasLength(2));
    },
  );

  test('#154 a release stops the translation under way and drops those '
      'waiting: a phone short of memory cannot wait minutes', () async {
    await install();
    runner.gate = Completer<void>();
    final running = translator.translate('eins', from: 'de', to: 'en');
    final waiting = translator.translate('zwei', from: 'de', to: 'en');
    await pumpEventQueue();

    final released = translator.release();
    const soon = Duration(seconds: 5);
    expect(await running.timeout(soon), isNull, reason: 'half is none');
    expect(await waiting.timeout(soon), isNull);
    await released.timeout(soon);
    expect(runner.cancels, 1);
    expect(runner.asked, hasLength(1), reason: 'the waiting one never ran');
    expect(runner.releases, 1);

    runner.gate = null;
    expect(
      await translator.translate('drei', from: 'de', to: 'en'),
      'translated',
      reason: 'the next one loads it again',
    );
  });

  test('#154 a translation nobody waits for: dropped while it waits, '
      'stopped while it runs, and neither cached', () async {
    await install();
    final repository = TranslationRepository(db, translator, DateTime.now);
    runner.gate = Completer<void>();
    final firstGone = Completer<void>();
    final secondGone = Completer<void>();
    final first = repository.translate(
      'eins',
      from: 'de',
      to: 'en',
      abandoned: firstGone.future,
    );
    final second = repository.translate(
      'zwei',
      from: 'de',
      to: 'en',
      abandoned: secondGone.future,
    );
    await pumpEventQueue();

    secondGone.complete();
    await pumpEventQueue();
    expect(runner.cancels, 0, reason: 'a waiting one only drops');
    firstGone.complete();
    const soon = Duration(seconds: 5);
    expect(await first.timeout(soon), isNull);
    expect(await second.timeout(soon), isNull);
    expect(runner.asked, hasLength(1));
    expect(runner.cancels, 1);

    runner.gate = null;
    expect(
      await repository.translate('eins', from: 'de', to: 'en'),
      'translated',
      reason: 'nothing half-done was cached',
    );
    expect(runner.asked, hasLength(2));
  });

  test("#154 R1's and T5's line off the screen abandons its translation", () {
    final asked = _Asked();
    final container = ProviderContainer(
      overrides: <Override>[
        translationRepositoryProvider.overrideWithValue(asked),
      ],
    );
    addTearDown(container.dispose);
    final line = container.listen(
      translationOfProvider('Danke.', 'de', 'en'),
      (_, _) {},
    );
    var gone = false;
    unawaited(asked.abandoned.single!.then((_) => gone = true));
    line.close();
    return pumpEventQueue().then((_) => expect(gone, isTrue));
  });

  test(
    '#154 a new download of the model that lands lets the loaded one go',
    () async {
      downloads.add((phase: DownloadPhase.running, progress: 0.5));
      await pumpEventQueue();
      expect(runner.releases, 0);
      downloads.add((phase: DownloadPhase.ready, progress: 1));
      await pumpEventQueue();
      expect(runner.releases, 1);
    },
  );

  test('#154 FR-W1-05 cached in translation_cache: a second ask doesn\'t run '
      'the model', () async {
    await install();
    final repository = TranslationRepository(db, translator, DateTime.now);
    expect(
      await repository.translate('Danke.', from: 'de', to: 'bn'),
      'translated',
    );
    expect(
      await repository.translate('Danke.', from: 'de', to: 'bn'),
      'translated',
    );
    expect(runner.asked, hasLength(1));
  });
}
