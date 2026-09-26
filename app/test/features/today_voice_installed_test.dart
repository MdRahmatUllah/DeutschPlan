import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/model_repository.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/features/today/today_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

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
    support = Directory.systemTemp.createTempSync('deutschplan_voice');
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
    try {
      support.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows releases it a moment later.
    }
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
}
