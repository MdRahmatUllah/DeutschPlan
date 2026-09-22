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
  Future<ModelVariant> variantOf(
    String content, {
    String id = 'q1_25',
    String file = 'model.gguf',
    String? sha,
  }) async => ModelVariant(
    id: id,
    name: 'test build',
    bytes: content.length,
    url: Uri.parse('https://example.invalid/$file'),
    sha256: sha ?? sha256.convert(utf8.encode(content)).toString(),
    files: <String>[file],
  );

  ModelEntry entryOf(ModelVariant variant, {String id = 'hymt'}) => ModelEntry(
    id: id,
    name: 'test model',
    licence: 'test',
    regionExcluded: const <String>[],
    variants: <ModelVariant>[variant],
  );

  /// Puts [content] in staging, the way a finished download would.
  Future<void> stage(
    String modelId,
    ModelVariant variant,
    String content,
  ) async {
    final directory = await models.beginDownload(modelId);
    File('${directory.path}/${variant.files.single}')
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
      expect(manifest.version, 1);
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
        for (final variant in model.variants) {
          expect(
            variant.url.scheme,
            'https',
            reason: '${model.id}/${variant.id}',
          );
          expect(
            variant.bytes,
            greaterThan(0),
            reason: '${model.id}/${variant.id}',
          );
          expect(
            variant.files,
            isNotEmpty,
            reason: '${model.id}/${variant.id}',
          );
        }
      }
    });

    test('carries the variants the docs name', () async {
      final manifest = ModelManifest.parse(
        await rootBundle.loadString(ModelRepository.manifestAsset),
      );
      // `translation.md`: q1_25 (~440 MB, default) and q2 (~575 MB).
      expect(manifest.model('hymt')!.variants.map((v) => v.id), <String>[
        'q1_25',
        'q2',
      ]);
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
      final variant = await variantOf('the model bytes');
      await stage('hymt', variant, 'the model bytes');

      expect(await models.activate('hymt', variant), ModelStatus.ready);

      final active = await models.directoryFor('hymt');
      expect(File('${active.path}/model.gguf').existsSync(), isTrue);
      expect((await models.stagingFor('hymt')).existsSync(), isFalse);
    });

    test('a wrong checksum does not', () async {
      final variant = await variantOf('the model bytes');
      await stage('hymt', variant, 'not the model bytes');

      expect(await models.activate('hymt', variant), ModelStatus.failed);
      expect((await models.directoryFor('hymt')).existsSync(), isFalse);
    });

    test('a partial download does not', () async {
      // The commonest real failure: the connection dropped and the file is
      // the right name and the wrong length.
      final variant = await variantOf('the model bytes');
      await stage('hymt', variant, 'the model by');

      expect(await models.activate('hymt', variant), ModelStatus.failed);
      expect((await models.directoryFor('hymt')).existsSync(), isFalse);
    });

    test('a missing file does not', () async {
      final variant = await variantOf('the model bytes');
      await models.beginDownload('hymt');

      expect(await models.activate('hymt', variant), ModelStatus.failed);
      expect((await models.directoryFor('hymt')).existsSync(), isFalse);
    });

    test('a variant with no pinned hash never activates', () async {
      // The bundled manifest ships with `sha256: null` until the artefacts
      // are pinned. Unverifiable and unverified are the same thing here.
      final variant = ModelVariant(
        id: 'q1_25',
        name: 'unpinned',
        bytes: 15,
        url: Uri.parse('https://example.invalid/x'),
        sha256: null,
        files: const <String>['model.gguf'],
      );
      await stage('hymt', variant, 'the model bytes');

      expect(variant.isPinned, isFalse);
      expect(await models.activate('hymt', variant), ModelStatus.failed);
      expect((await models.directoryFor('hymt')).existsSync(), isFalse);
    });

    test('a truncated hash is not a hash', () async {
      final full = sha256.convert(utf8.encode('the model bytes')).toString();
      final variant = await variantOf(
        'the model bytes',
        sha: full.substring(0, 32),
      );
      await stage('hymt', variant, 'the model bytes');

      expect(await models.activate('hymt', variant), ModelStatus.failed);
    });

    test('an upper-case hash in the manifest still matches', () async {
      final full = sha256.convert(utf8.encode('the model bytes')).toString();
      final variant = await variantOf(
        'the model bytes',
        sha: full.toUpperCase(),
      );
      await stage('hymt', variant, 'the model bytes');

      expect(await models.activate('hymt', variant), ModelStatus.ready);
    });

    test('a failed activation leaves the old model alone', () async {
      // The learner has a working model. An update that does not verify must
      // not take it away.
      final good = await variantOf('version one');
      await stage('hymt', good, 'version one');
      await models.activate('hymt', good);

      final bad = await variantOf('version two', id: 'q2');
      await stage('hymt', bad, 'corrupted');
      expect(await models.activate('hymt', bad), ModelStatus.failed);

      final active = await models.directoryFor('hymt');
      expect(
        File('${active.path}/model.gguf').readAsStringSync(),
        'version one',
      );
    });

    test('retrying starts from empty', () async {
      // A resumed download that appended to a half file would hash to
      // something that never matches, and the learner would retry forever.
      final variant = await variantOf('the model bytes');
      await stage('hymt', variant, 'rubbish from the last attempt');

      await models.beginDownload('hymt');
      final staging = await models.stagingFor('hymt');
      expect(staging.listSync(), isEmpty);
    });
  });

  group('what the card shows', () {
    test('nothing on disk is not downloaded', () async {
      final variant = await variantOf('bytes');
      expect(
        (await models.stateOf(entryOf(variant), variant)).status,
        ModelStatus.notDownloaded,
      );
    });

    test('staging is downloading, with the progress', () async {
      final variant = await variantOf('0123456789');
      await stage('hymt', variant, '01234');

      final state = await models.stateOf(entryOf(variant), variant);
      expect(state.status, ModelStatus.downloading);
      expect(state.bytesOnDisk, 5);
      expect(state.progress, 0.5);
    });

    test('an activated model is ready', () async {
      final variant = await variantOf('bytes');
      await stage('hymt', variant, 'bytes');
      await models.activate('hymt', variant);

      expect(
        (await models.stateOf(entryOf(variant), variant)).status,
        ModelStatus.ready,
      );
    });

    test('a manifest with a new hash is an update', () async {
      final installed = await variantOf('version one');
      await stage('hymt', installed, 'version one');
      await models.activate('hymt', installed);

      // FR-M4-02: updates compare hashes.
      final published = await variantOf('version two');
      expect(
        (await models.stateOf(entryOf(published), published)).status,
        ModelStatus.updateAvailable,
      );
    });

    test('a model directory someone emptied is failed, not ready', () async {
      final variant = await variantOf('bytes');
      await stage('hymt', variant, 'bytes');
      await models.activate('hymt', variant);

      File('${(await models.directoryFor('hymt')).path}/model.gguf')
          .deleteSync();

      expect(
        (await models.stateOf(entryOf(variant), variant)).status,
        ModelStatus.failed,
      );
    });

    test('a directory that was never activated is failed', () async {
      // Something put files where the engine looks without going through
      // `activate`. It has no stamp, so it cannot be trusted.
      final variant = await variantOf('bytes');
      final active = await models.directoryFor('hymt');
      active.createSync(recursive: true);
      File('${active.path}/model.gguf').writeAsStringSync('bytes');

      expect(
        (await models.stateOf(entryOf(variant), variant)).status,
        ModelStatus.failed,
      );
    });
  });

  group('FR-M4-03 — deleting turns off what depended on it', () {
    test('deleting the voice falls back to the system engine', () async {
      await settings.write(SettingKeys.ttsEngine, TtsEngine.supertonic);
      final variant = await variantOf('bytes');
      await stage('supertonic3', variant, 'bytes');
      await models.activate('supertonic3', variant);

      await models.delete('supertonic3');

      expect(settings.read(SettingKeys.ttsEngine), TtsEngine.system);
      expect((await models.directoryFor('supertonic3')).existsSync(), isFalse);
    });

    test('deleting the translation model turns translation off', () async {
      await settings.write(SettingKeys.mtEnabled, true);
      final variant = await variantOf('bytes');
      await stage('hymt', variant, 'bytes');
      await models.activate('hymt', variant);

      await models.delete('hymt');

      expect(settings.read(SettingKeys.mtEnabled), isFalse);
      expect((await models.directoryFor('hymt')).existsSync(), isFalse);
    });

    test('deleting takes the staging directory too', () async {
      final variant = await variantOf('bytes');
      await stage('hymt', variant, 'part');

      await models.delete('hymt');
      expect((await models.stagingFor('hymt')).existsSync(), isFalse);
    });

    test('deleting one model leaves the other', () async {
      final variant = await variantOf('bytes');
      await stage('hymt', variant, 'bytes');
      await models.activate('hymt', variant);
      await stage('supertonic3', variant, 'bytes');
      await models.activate('supertonic3', variant);

      await models.delete('hymt');
      expect((await models.directoryFor('supertonic3')).existsSync(), isTrue);
    });
  });

  test('the storage card counts what is on disk', () async {
    expect(await models.bytesUsed(), 0);

    final variant = await variantOf('0123456789');
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
