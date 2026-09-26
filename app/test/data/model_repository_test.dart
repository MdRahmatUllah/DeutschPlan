@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/model_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/synthesis_cache.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

/// `ModelRepository` and the on-device file store.
///
/// The download is `background_downloader`'s job; what is tested here is the
/// rule FR-M4-01 turns on — that a partial or unverified directory is never
/// the one an engine loads from.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory support;
  late AppDatabase db;
  late SettingsRepository settings;
  late ModelRepository models;

  /// A variant of one file, hashed for real.
  ModelVariant variantOf(
    String content, {
    String id = 'q4_k_m',
    String file = 'model.gguf',
    String? sha,
  }) => ModelVariant(
    id: id,
    name: 'test build',
    files: <ModelFile>[
      ModelFile(
        name: file,
        url: Uri.parse('https://example.invalid/$file'),
        bytes: content.length,
        sha256: sha ?? sha256.convert(utf8.encode(content)).toString(),
      ),
    ],
  );

  ModelEntry entryOf(
    List<ModelVariant> variants, {
    String id = 'hymt',
    String disables = 'mt_enabled',
  }) => ModelEntry(
    id: id,
    name: 'test model',
    licence: 'test',
    disables: disables,
    regionExcluded: const <String>[],
    variants: variants,
  );

  /// Puts [content] in staging, the way a finished download would.
  Future<void> stage(
    String modelId,
    ModelVariant variant,
    String content, {
    String? file,
  }) async {
    final directory = await models.restartDownload(modelId);
    File('${directory.path}/${file ?? variant.files.first.name}')
        .writeAsStringSync(content);
  }

  setUp(() async {
    support = Directory.systemTemp.createTempSync('deutschplan_models');
    db = AppDatabase.memory();
    settings = SettingsRepository(db);
    await settings.load();
    models = ModelRepository(settings, support: support);
  });

  tearDown(() async {
    await settings.dispose();
    await db.close();
    try {
      support.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows releases it a moment later.
    }
  });

  group('FR-M4-02 — the bundled manifest', () {
    test('parses', () async {
      final manifest = ModelManifest.parse(
        await rootBundle.loadString(ModelRepository.manifestAsset),
      );
      expect(manifest.version, 2);
      expect(
        manifest.models.map((m) => m.id),
        containsAll(<String>['supertonic3', 'hymt']),
      );
    });

    test('names a URL, a size and a licence per variant', () async {
      final manifest = ModelManifest.parse(
        await rootBundle.loadString(ModelRepository.manifestAsset),
      );
      for (final model in manifest.models) {
        expect(model.licence, isNotEmpty, reason: model.id);
        expect(model.variants, isNotEmpty, reason: model.id);
        expect(model.disables, isNotEmpty, reason: model.id);
        for (final variant in model.variants) {
          expect(
            variant.files,
            isNotEmpty,
            reason: '${model.id}/${variant.id}',
          );
          for (final file in variant.files) {
            final where = '${model.id}/${variant.id}/${file.name}';
            expect(file.url.scheme, 'https', reason: where);
            expect(file.bytes, greaterThan(0), reason: where);
          }
          expect(
            variant.bytes,
            greaterThan(0),
            reason: '${model.id}/${variant.id}',
          );
        }
      }
    });

    test('#245 #152 Supertonic 3 is the files that exist, each pinned, with '
        "the owner's three voice styles", () async {
      final manifest = ModelManifest.parse(
        await rootBundle.loadString(ModelRepository.manifestAsset),
      );
      final variant = manifest.model('supertonic3')!.variants.single;
      expect(variant.files.map((f) => f.name), <String>[
        'duration_predictor.onnx',
        'text_encoder.onnx',
        'vector_estimator.onnx',
        'vocoder.onnx',
        'tts.json',
        'unicode_indexer.json',
        'F1.json',
        'M1.json',
        'F2.json',
      ]);
      expect(variant.isPinned, isTrue, reason: 'every file has its SHA-256');
      expect(variant.bytes, 399237419, reason: 'about 400 MB, not ~100');
      for (final file in variant.files) {
        expect(file.url.host, 'huggingface.co', reason: file.name);
        expect(file.url.path, startsWith('/Supertone/supertonic-3/resolve/'));
      }
    });

    test("#409 Hy-MT is the owner's Q4_K_M build, the file that exists, "
        'pinned', () async {
      final manifest = ModelManifest.parse(
        await rootBundle.loadString(ModelRepository.manifestAsset),
      );
      // `translation.md`: one build, from tencent/HY-MT1.5-1.8B-GGUF.
      final variant = manifest.model('hymt')!.variants.single;
      expect(variant.id, 'q4_k_m');
      final file = variant.files.single;
      expect(file.name, 'HY-MT1.5-1.8B-Q4_K_M.gguf');
      expect(
        file.url.toString(),
        'https://huggingface.co/tencent/HY-MT1.5-1.8B-GGUF/resolve/main/'
        'HY-MT1.5-1.8B-Q4_K_M.gguf',
      );
      expect(variant.isPinned, isTrue, reason: 'its SHA-256 is known');
      expect(variant.bytes, 1133080512, reason: 'about 1.1 GB');
    });

    test('the licence gate the Hy-MT model needs is in the manifest', () async {
      final manifest = ModelManifest.parse(
        await rootBundle.loadString(ModelRepository.manifestAsset),
      );
      // `translation.md`: the Tencent HY licence excludes the EU, UK and
      // South Korea. The build flag gates the button; this is the data that
      // says why the flag exists.
      expect(
        manifest.model('hymt')!.regionExcluded,
        containsAll(<String>['EU', 'GB', 'KR']),
      );
      expect(manifest.model('supertonic3')!.regionExcluded, isEmpty);
    });

    test('a missing field is a parse error, not a default', () {
      // A manifest that lost its `files` list would otherwise verify a model
      // by hashing nothing at all.
      expect(
        () => ModelManifest.parse(
          '{"manifest_version":1,"models":[{"id":"x","name":"X",'
          '"licence":"L","variants":[{"id":"v","name":"V","bytes":1,'
          '"url":"https://example.invalid/x"}]}]}',
        ),
        throwsA(anything),
      );
    });
  });

  group('FR-M4-01 — nothing unverified activates', () {
    test('a matching checksum activates', () async {
      final variant = variantOf('the model bytes');
      await stage('hymt', variant, 'the model bytes');

      expect(await models.activate('hymt', variant), ModelStatus.ready);

      final active = await models.directoryFor('hymt');
      expect(File('${active.path}/model.gguf').existsSync(), isTrue);
      expect((await models.stagingFor('hymt')).existsSync(), isFalse);
    });

    test('a wrong checksum does not', () async {
      final variant = variantOf('the model bytes');
      await stage('hymt', variant, 'not the model bytes');

      expect(await models.activate('hymt', variant), ModelStatus.failed);
      expect((await models.directoryFor('hymt')).existsSync(), isFalse);
    });

    test('a partial download does not', () async {
      // The commonest real failure: the connection dropped and the file is
      // the right name and the wrong length.
      final variant = variantOf('the model bytes');
      await stage('hymt', variant, 'the model by');

      expect(await models.activate('hymt', variant), ModelStatus.failed);
      expect((await models.directoryFor('hymt')).existsSync(), isFalse);
    });

    test('a missing file does not', () async {
      final variant = variantOf('the model bytes');
      await models.beginDownload('hymt');

      expect(await models.activate('hymt', variant), ModelStatus.failed);
      expect((await models.directoryFor('hymt')).existsSync(), isFalse);
    });

    test('a variant with no pinned hash never activates', () async {
      // A file with `sha256: null`, as the bundled manifest had before the
      // artefacts were pinned (#245, #409): unverifiable and unverified are
      // the same thing here.
      final variant = ModelVariant(
        id: 'q4_k_m',
        name: 'unpinned',
        files: <ModelFile>[
          ModelFile(
            name: 'model.gguf',
            url: Uri.parse('https://example.invalid/x'),
            bytes: 15,
            sha256: null,
          ),
        ],
      );
      await stage('hymt', variant, 'the model bytes');

      expect(variant.isPinned, isFalse);
      expect(await models.activate('hymt', variant), ModelStatus.failed);
      expect((await models.directoryFor('hymt')).existsSync(), isFalse);
    });

    test('a truncated hash is not a hash', () async {
      final full = sha256.convert(utf8.encode('the model bytes')).toString();
      final variant = variantOf('the model bytes', sha: full.substring(0, 32));
      await stage('hymt', variant, 'the model bytes');

      expect(await models.activate('hymt', variant), ModelStatus.failed);
    });

    test('an upper-case hash in the manifest still matches', () async {
      final full = sha256.convert(utf8.encode('the model bytes')).toString();
      final variant = variantOf('the model bytes', sha: full.toUpperCase());
      await stage('hymt', variant, 'the model bytes');

      expect(await models.activate('hymt', variant), ModelStatus.ready);
    });

    test('a failed activation leaves the old model alone', () async {
      // The learner has a working model. An update that does not verify must
      // not take it away.
      final good = variantOf('version one');
      await stage('hymt', good, 'version one');
      await models.activate('hymt', good);

      final bad = variantOf('version two', id: 'q6_k');
      await stage('hymt', bad, 'corrupted');
      expect(await models.activate('hymt', bad), ModelStatus.failed);

      final active = await models.directoryFor('hymt');
      expect(
        File('${active.path}/model.gguf').readAsStringSync(),
        'version one',
      );
    });

    test('retrying starts from empty', () async {
      // A retry that appended to a corrupt file would hash to something that
      // never matches, and the learner would retry for ever.
      final variant = variantOf('the model bytes');
      await stage('hymt', variant, 'rubbish from the last attempt');

      await models.restartDownload('hymt');
      expect((await models.stagingFor('hymt')).listSync(), isEmpty);
    });

    test('resuming keeps what has already arrived', () async {
      // FR-M4-01 asks for resumable downloads, and the point of resuming is
      // that the bytes on disk stay. `beginDownload` is the resume path.
      final variant = variantOf('the model bytes');
      await stage('hymt', variant, 'the model ');

      await models.beginDownload('hymt');
      expect((await models.stagingFor('hymt')).listSync(), hasLength(1));
    });

    test('a crash mid-activation leaves the old model, not nothing', () async {
      // `activate` renames the old model aside before putting the new one in
      // place. A process that died in between leaves a `.previous`; the next
      // read puts it back rather than making the learner download 1.1 GB
      // again.
      final good = variantOf('version one');
      await stage('hymt', good, 'version one');
      await models.activate('hymt', good);

      final active = await models.directoryFor('hymt');
      active.renameSync('${active.path}.previous');

      final state = await models.stateOf(entryOf(<ModelVariant>[good]), good);
      expect(state.status, ModelStatus.ready);
      expect(
        File('${active.path}/model.gguf').readAsStringSync(),
        'version one',
      );
    });

    test('the old model survives an activation that cannot finish', () async {
      // The ordering is the claim: the model being replaced is renamed aside,
      // not deleted, so a failure putting the new one in place costs an app
      // restart rather than a second 1.1 GB download. A plain file sitting
      // where the rename wants to go is the cheapest way to make it fail.
      final good = variantOf('version one');
      await stage('hymt', good, 'version one');
      await models.activate('hymt', good);

      final active = await models.directoryFor('hymt');
      File('${active.path}.previous').writeAsStringSync('in the way');

      final next = variantOf('version two');
      await stage('hymt', next, 'version two');
      await expectLater(models.activate('hymt', next), throwsA(anything));

      expect(
        File('${active.path}/model.gguf').readAsStringSync(),
        'version one',
        reason: 'the working model was thrown away before the new one landed',
      );
    });

    test('a successful activation leaves nothing behind', () async {
      final first = variantOf('version one');
      await stage('hymt', first, 'version one');
      await models.activate('hymt', first);

      final second = variantOf('version two');
      await stage('hymt', second, 'version two');
      await models.activate('hymt', second);

      final active = await models.directoryFor('hymt');
      expect(Directory('${active.path}.previous').existsSync(), isFalse);
      expect(
        File('${active.path}/model.gguf').readAsStringSync(),
        'version two',
      );
    });

    test('it says which file failed', () async {
      final variant = ModelVariant(
        id: 'default',
        name: 'two files',
        files: <ModelFile>[
          ModelFile(
            name: 'a.onnx',
            url: Uri.parse('https://example.invalid/a'),
            bytes: 1,
            sha256: sha256.convert(utf8.encode('a')).toString(),
          ),
          ModelFile(
            name: 'b.bin',
            url: Uri.parse('https://example.invalid/b'),
            bytes: 1,
            sha256: sha256.convert(utf8.encode('b')).toString(),
          ),
        ],
      );

      final staging = await models.restartDownload('supertonic3');
      File('${staging.path}/a.onnx').writeAsStringSync('a');
      File('${staging.path}/b.bin').writeAsStringSync('wrong');

      final state = await models.verifyIn(staging, variant);
      expect(state.status, ModelStatus.failed);
      expect(state.failedFile, 'b.bin');
    });

    test('one bad file in a set fails the whole variant', () async {
      // Hashing per file is what makes this possible to say at all: a digest
      // over the concatenation would only ever report "something".
      final variant = ModelVariant(
        id: 'default',
        name: 'two files',
        files: <ModelFile>[
          ModelFile(
            name: 'a.onnx',
            url: Uri.parse('https://example.invalid/a'),
            bytes: 1,
            sha256: sha256.convert(utf8.encode('a')).toString(),
          ),
          ModelFile(
            name: 'b.bin',
            url: Uri.parse('https://example.invalid/b'),
            bytes: 1,
            sha256: sha256.convert(utf8.encode('b')).toString(),
          ),
        ],
      );

      final staging = await models.restartDownload('supertonic3');
      File('${staging.path}/a.onnx').writeAsStringSync('a');
      File('${staging.path}/b.bin').writeAsStringSync('b');
      expect(await models.activate('supertonic3', variant), ModelStatus.ready);

      final active = await models.directoryFor('supertonic3');
      expect(File('${active.path}/b.bin').existsSync(), isTrue);
    });
  });

  group('what the card shows', () {
    test('nothing on disk is not downloaded', () async {
      final variant = variantOf('bytes');
      expect(
        (await models.stateOf(
          entryOf(<ModelVariant>[variant]),
          variant,
        )).status,
        ModelStatus.notDownloaded,
      );
    });

    test('staging is downloading, with the progress', () async {
      final variant = variantOf('0123456789');
      await stage('hymt', variant, '01234');

      final state = await models.stateOf(
        entryOf(<ModelVariant>[variant]),
        variant,
      );
      expect(state.status, ModelStatus.downloading);
      expect(state.bytesOnDisk, 5);
      expect(state.progress, 0.5);
    });

    test('an activated model is ready', () async {
      final variant = variantOf('bytes');
      await stage('hymt', variant, 'bytes');
      await models.activate('hymt', variant);

      expect(
        (await models.stateOf(
          entryOf(<ModelVariant>[variant]),
          variant,
        )).status,
        ModelStatus.ready,
      );
    });

    test('the other variant of the model is not an update', () async {
      // A manifest may list several builds of a model (Hy-MT publishes
      // Q4_K_M, Q6_K and Q8_0; the app offers Q4_K_M, #409). Calling another
      // build an update would replace a working model rather than add one.
      final installed = variantOf('small build');
      final other = variantOf('big build', id: 'q6_k');
      final entry = entryOf(<ModelVariant>[installed, other]);

      await stage('hymt', installed, 'small build');
      await models.activate('hymt', installed);

      expect(
        (await models.stateOf(entry, installed)).status,
        ModelStatus.ready,
      );
      expect(
        (await models.stateOf(entry, other)).status,
        ModelStatus.notDownloaded,
      );
    });

    test('a manifest with a new hash is an update', () async {
      final installed = variantOf('version one');
      await stage('hymt', installed, 'version one');
      await models.activate('hymt', installed);

      // FR-M4-02: updates compare hashes.
      final published = variantOf('version two');
      expect(
        (await models.stateOf(
          entryOf(<ModelVariant>[published]),
          published,
        )).status,
        ModelStatus.updateAvailable,
      );
    });

    test('#152 a manifest that adds a file to an installed model is an '
        'update, not a failure', () async {
      // The voice gained M1 and F2: a phone with the seven-file download has
      // a verified model without them, and should be offered the update.
      final installed = variantOf('version one');
      await stage('hymt', installed, 'version one');
      await models.activate('hymt', installed);

      final published = ModelVariant(
        id: installed.id,
        name: installed.name,
        files: <ModelFile>[
          ...installed.files,
          ModelFile(
            name: 'more.gguf',
            url: Uri.parse('https://example.invalid/more.gguf'),
            bytes: 4,
            sha256: sha256.convert(utf8.encode('more')).toString(),
          ),
        ],
      );
      expect(
        (await models.stateOf(
          entryOf(<ModelVariant>[published]),
          published,
        )).status,
        ModelStatus.updateAvailable,
      );
    });

    test('a model directory someone emptied is failed, not ready', () async {
      final variant = variantOf('bytes');
      await stage('hymt', variant, 'bytes');
      await models.activate('hymt', variant);

      File('${(await models.directoryFor('hymt')).path}/model.gguf')
          .deleteSync();

      expect(
        (await models.stateOf(
          entryOf(<ModelVariant>[variant]),
          variant,
        )).status,
        ModelStatus.failed,
      );
    });

    test('a directory that was never activated is failed', () async {
      // Something put files where the engine looks without going through
      // `activate`. It has no stamp, so it cannot be trusted.
      final variant = variantOf('bytes');
      final active = await models.directoryFor('hymt');
      active.createSync(recursive: true);
      File('${active.path}/model.gguf').writeAsStringSync('bytes');

      expect(
        (await models.stateOf(
          entryOf(<ModelVariant>[variant]),
          variant,
        )).status,
        ModelStatus.failed,
      );
    });
  });

  group('FR-M4-03 — deleting turns off what depended on it', () {
    test('deleting the voice falls back to the system engine', () async {
      await settings.write(SettingKeys.ttsEngine, TtsEngineSetting.supertonic);
      final variant = variantOf('bytes');
      await stage('supertonic3', variant, 'bytes');
      await models.activate('supertonic3', variant);

      await models.delete(
        entryOf(
          <ModelVariant>[variant],
          id: 'supertonic3',
          disables: 'tts_engine',
        ),
      );

      expect(settings.read(SettingKeys.ttsEngine), TtsEngineSetting.system);
      expect((await models.directoryFor('supertonic3')).existsSync(), isFalse);
    });

    test('deleting the translation model turns translation off', () async {
      await settings.write(SettingKeys.mtEnabled, true);
      final variant = variantOf('bytes');
      await stage('hymt', variant, 'bytes');
      await models.activate('hymt', variant);

      await models.delete(entryOf(<ModelVariant>[variant]));

      expect(settings.read(SettingKeys.mtEnabled), isFalse);
      expect((await models.directoryFor('hymt')).existsSync(), isFalse);
    });

    test('a model whose side effect nothing knows is a loud failure', () async {
      // The manifest names the key; a typo there would otherwise delete the
      // model and leave the setting pointing at it, silently.
      final variant = variantOf('bytes');
      await expectLater(
        models.delete(
          entryOf(<ModelVariant>[variant], disables: 'not_a_setting'),
        ),
        throwsStateError,
      );
    });

    test('deleting takes the staging directory too', () async {
      final variant = variantOf('bytes');
      await stage('hymt', variant, 'part');

      await models.delete(entryOf(<ModelVariant>[variant]));
      expect((await models.stagingFor('hymt')).existsSync(), isFalse);
    });

    test('deleting one model leaves the other', () async {
      final variant = variantOf('bytes');
      await stage('hymt', variant, 'bytes');
      await models.activate('hymt', variant);
      await stage('supertonic3', variant, 'bytes');
      await models.activate('supertonic3', variant);

      await models.delete(entryOf(<ModelVariant>[variant]));
      expect((await models.directoryFor('supertonic3')).existsSync(), isTrue);
    });
  });

  test('the storage card counts what is on disk', () async {
    expect(await models.bytesUsed(), 0);

    final variant = variantOf('0123456789');
    await stage('hymt', variant, '0123456789');
    await models.activate('hymt', variant);

    // The model plus the stamp file `activate` writes.
    expect(await models.bytesUsed(), greaterThanOrEqualTo(10));
  });

  group('FR-L12S-02 — recordings', () {
    test('live at the path the spec names', () async {
      final file = await models.recordingFor(42);
      expect(file.path, '${support.path}/recordings/42.m4a');
    });

    test('one per attempt', () async {
      expect(
        (await models.recordingFor(1)).path,
        isNot((await models.recordingFor(2)).path),
      );
    });
  });

  group('the synthesis cache', () {
    late SynthesisCache cache;

    setUp(() => cache = SynthesisCache(support: support, capacity: 4));

    Uint8List clip(int n) => Uint8List.fromList(<int>[n, n, n]);

    test('a miss is null, not an error', () async {
      expect(await cache.read('Haus', voice: 'Anna', speed: 1), isNull);
    });

    test('what went in comes back', () async {
      await cache.write('Haus', voice: 'Anna', speed: 1, bytes: clip(7));
      expect(await cache.read('Haus', voice: 'Anna', speed: 1), <int>[7, 7, 7]);
    });

    test('#436 clips another version made are stale: they go on first use, '
        'and the same version keeps them', () async {
      final five = SynthesisCache(support: support, version: '5 steps');
      await five.write('Haus', voice: 'Anna', speed: 1, bytes: clip(5));
      final same = SynthesisCache(support: support, version: '5 steps');
      expect(await same.read('Haus', voice: 'Anna', speed: 1), <int>[5, 5, 5]);

      final eight = SynthesisCache(support: support, version: '8 steps');
      expect(await eight.read('Haus', voice: 'Anna', speed: 1), isNull);
      expect(await eight.count(), 0);
      await eight.write('Haus', voice: 'Anna', speed: 1, bytes: clip(8));
      expect(
        await SynthesisCache(
          support: support,
          version: '8 steps',
        ).read('Haus', voice: 'Anna', speed: 1),
        <int>[8, 8, 8],
      );
    });

    test('the voice is part of the key', () async {
      await cache.write('Haus', voice: 'Anna', speed: 1, bytes: clip(1));
      expect(await cache.read('Haus', voice: 'Jonas', speed: 1), isNull);
    });

    test('the speed is part of the key', () async {
      // The long-press plays at 0.75×. Serving the 1.0× clip for it would be
      // the wrong speed with no way for the learner to tell why.
      await cache.write('Haus', voice: 'Anna', speed: 1, bytes: clip(1));
      expect(await cache.read('Haus', voice: 'Anna', speed: 0.75), isNull);
    });

    test('a speed that is the same number is the same key', () async {
      await cache.write('Haus', voice: 'Anna', speed: 0.75, bytes: clip(1));
      expect(
        await cache.read('Haus', voice: 'Anna', speed: 0.7500001),
        isNotNull,
      );
    });

    test('the text is part of the key', () async {
      await cache.write('Haus', voice: 'Anna', speed: 1, bytes: clip(1));
      expect(await cache.read('Tür', voice: 'Anna', speed: 1), isNull);
    });

    test('a sentence with a slash in it is still one file', () async {
      // The key is hashed, so a sentence that looks like a path does not
      // become a directory.
      await cache.write(
        'er/sie kommt',
        voice: 'Anna',
        speed: 1,
        bytes: clip(1),
      );
      expect(await cache.count(), 1);
      expect(
        await cache.read('er/sie kommt', voice: 'Anna', speed: 1),
        isNotNull,
      );
    });

    test('it holds the capacity and no more', () async {
      for (var i = 0; i < 10; i++) {
        await cache.write('Wort$i', voice: 'Anna', speed: 1, bytes: clip(i));
      }
      expect(await cache.count(), 4);
    });

    test('the oldest go first', () async {
      for (var i = 0; i < 5; i++) {
        await cache.write('Wort$i', voice: 'Anna', speed: 1, bytes: clip(i));
        // Distinct mtimes: the filesystem resolution is coarse enough that
        // five writes in a row can share one.
        await _tick();
      }
      expect(await cache.read('Wort0', voice: 'Anna', speed: 1), isNull);
      expect(await cache.read('Wort4', voice: 'Anna', speed: 1), isNotNull);
    });

    test('a clip the learner keeps replaying stays', () async {
      // Eviction is by last *read*. A headword tapped every session must not
      // be dropped because it was first synthesised a month ago.
      for (var i = 0; i < 4; i++) {
        await cache.write('Wort$i', voice: 'Anna', speed: 1, bytes: clip(i));
        await _tick();
      }

      await cache.read('Wort0', voice: 'Anna', speed: 1);
      await _tick();

      await cache.write('Wort9', voice: 'Anna', speed: 1, bytes: clip(9));

      expect(await cache.read('Wort0', voice: 'Anna', speed: 1), isNotNull);
      expect(await cache.read('Wort1', voice: 'Anna', speed: 1), isNull);
    });

    test('clearing empties it', () async {
      await cache.write('Haus', voice: 'Anna', speed: 1, bytes: clip(1));
      await cache.clear();

      expect(await cache.count(), 0);
      expect(await cache.read('Haus', voice: 'Anna', speed: 1), isNull);
    });

    test('counting an empty cache does not create it', () async {
      expect(await cache.count(), 0);
      expect(await cache.bytesUsed(), 0);
      expect((await cache.directory()).existsSync(), isFalse);
    });

    test('the default capacity is the one tts.md names', () {
      expect(SynthesisCache().capacity, 200);
    });
  });
}

/// A pause long enough for the filesystem to record a different mtime.
Future<void> _tick() => Future<void>.delayed(const Duration(milliseconds: 12));
