import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/repositories/model_repository.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/features/today/today_providers.dart';
import 'package:sogda/services/model_downloads.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../db/content_fixture.dart' show tempDir;

/// #473 · FR-T1-06: Today's voice card reads the installed voice the way M4
/// does, over a real [ModelRepository]: a voice downloaded, checked and
/// activated is installed, though its staging folder is gone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory support;
  late AppDatabase db;
  late SettingsRepository settings;
  late ModelRepository models;
  late ProviderContainer container;

  const content = 'a voice';
  final variant = ModelVariant(
    id: 'v1',
    name: 'test voice',
    files: <ModelFile>[
      ModelFile(
        name: 'voice.onnx',
        url: Uri.parse('https://example.invalid/voice.onnx'),
        bytes: content.length,
        sha256: sha256.convert(utf8.encode(content)).toString(),
      ),
    ],
  );

  setUp(() async {
    support = tempDir('sogda_voice');
    db = AppDatabase.memory();
    settings = SettingsRepository(db);
    await settings.load();
    models = ModelRepository(settings, support: support)
      ..useManifest(
        ModelManifest(
          version: 1,
          models: <ModelEntry>[
            ModelEntry(
              id: ModelRepository.voiceModel,
              name: 'test voice',
              licence: 'test',
              disables: 'tts_engine',
              regionExcluded: const <String>[],
              variants: <ModelVariant>[variant],
            ),
          ],
        ),
      );
    container = ProviderContainer(
      overrides: <Override>[modelRepositoryProvider.overrideWithValue(models)],
    );
  });

  tearDown(() async {
    container.dispose();
    await settings.dispose();
    await db.close();
  });

  test('#473 FR-T1-06 no voice on the phone: not installed', () async {
    expect(await container.read(voiceInstalledProvider.future), isFalse);
  });

  test('#473 FR-T1-06 a voice activated is installed, its staging folder '
      'renamed away', () async {
    final staging = await models.restartDownload(ModelRepository.voiceModel);
    File('${staging.path}/voice.onnx').writeAsStringSync(content);
    expect(
      await models.activate(ModelRepository.voiceModel, variant),
      ModelStatus.ready,
    );
    expect(staging.existsSync(), isFalse, reason: 'activate renames it');

    expect(await container.read(voiceInstalledProvider.future), isTrue);
  });

  test('#473 FR-T1-06 FR-M4-02 a voice with an update on offer is still '
      'installed', () async {
    final staging = await models.restartDownload(ModelRepository.voiceModel);
    File('${staging.path}/voice.onnx').writeAsStringSync(content);
    await models.activate(ModelRepository.voiceModel, variant);
    // The manifest moves on: the same build, new hashes.
    final updated = ModelVariant(
      id: variant.id,
      name: variant.name,
      files: <ModelFile>[
        ModelFile(
          name: 'voice.onnx',
          url: Uri.parse('https://example.invalid/voice.onnx'),
          bytes: 9,
          sha256: sha256.convert(utf8.encode('a voice 2')).toString(),
        ),
      ],
    );
    final entry = (await models.manifest()).model(ModelRepository.voiceModel)!;
    models.useManifest(
      ModelManifest(
        version: 2,
        models: <ModelEntry>[
          ModelEntry(
            id: entry.id,
            name: entry.name,
            licence: entry.licence,
            disables: entry.disables,
            regionExcluded: entry.regionExcluded,
            variants: <ModelVariant>[updated],
          ),
        ],
      ),
    );
    expect(
      (await models.stateOf(
        (await models.manifest()).model(ModelRepository.voiceModel)!,
        updated,
      )).status,
      ModelStatus.updateAvailable,
    );

    expect(await container.read(voiceInstalledProvider.future), isTrue);
  });

  test(
    '#663 #757 FR-T1-06 a download that lands is read again, with no '
    "restart: Today stops offering the voice, and M3's row names it",
    () async {
      final downloads = StreamController<DownloadProgress>.broadcast();
      addTearDown(downloads.close);
      final live = ProviderContainer(
        overrides: <Override>[
          modelRepositoryProvider.overrideWithValue(models),
          voiceDownloadProvider.overrideWith((ref) => downloads.stream),
        ],
      );
      addTearDown(live.dispose);
      // Held, as Today holds it for the app's life.
      final held = live.listen(voiceInstalledProvider, (_, _) {});
      addTearDown(held.close);
      expect(await live.read(voiceInstalledProvider.future), isFalse);

      downloads.add((phase: DownloadPhase.running, progress: 0.5));
      final staging = await models.restartDownload(ModelRepository.voiceModel);
      File('${staging.path}/voice.onnx').writeAsStringSync(content);
      await models.activate(ModelRepository.voiceModel, variant);
      downloads.add((phase: DownloadPhase.ready, progress: 1));
      await pumpEventQueue();

      expect(await live.read(voiceInstalledProvider.future), isTrue);
    },
  );
}
