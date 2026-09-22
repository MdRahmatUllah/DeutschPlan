import 'dart:convert';
import 'dart:io';

import 'package:convert/convert.dart' show AccumulatorSink;
import 'package:crypto/crypto.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// The states `model-manager.md` lists, in the order a model moves through
/// them.
enum ModelStatus {
  /// Nothing on disk, or nothing that verified.
  notDownloaded,

  /// Bytes are arriving into the staging directory.
  downloading,

  /// All the bytes are there and the checksum is being read.
  verifying,

  /// Verified and in place. The only state anything is allowed to load from.
  ready,

  /// Ready, but the manifest now names a different checksum.
  updateAvailable,

  /// The checksum did not match, or a file is missing. *Retry* from here.
  failed,
}

/// One downloadable build of a model.
@immutable
class ModelVariant {
  const ModelVariant({
    required this.id,
    required this.name,
    required this.bytes,
    required this.url,
    required this.sha256,
    required this.files,
  });

  factory ModelVariant.fromJson(Map<String, Object?> json) => ModelVariant(
    id: json['id']! as String,
    name: json['name']! as String,
    bytes: json['bytes']! as int,
    url: Uri.parse(json['url']! as String),
    sha256: json['sha256'] as String?,
    files: <String>[
      for (final file in json['files']! as List<Object?>) file! as String,
    ],
  );

  final String id;
  final String name;

  /// What the Model manager prints, and what the space check is against.
  final int bytes;

  final Uri url;

  /// SHA-256 of the downloaded artefact, lower-case hex.
  ///
  /// **Nullable on purpose.** A variant whose artefact has not been pinned yet
  /// has no hash, and [ModelRepository.verify] refuses it — FR-M4-01 says a
  /// partial or unverified file never activates, and "we have not got round to
  /// the hash" is the same thing as unverified from the learner's side.
  final String? sha256;

  /// The files that make up the download, relative to the model directory.
  final List<String> files;

  bool get isPinned => sha256 != null && sha256!.length == 64;
}

/// One model, with the variants it can be downloaded as.
@immutable
class ModelEntry {
  const ModelEntry({
    required this.id,
    required this.name,
    required this.licence,
    required this.variants,
    required this.regionExcluded,
  });

  factory ModelEntry.fromJson(Map<String, Object?> json) => ModelEntry(
    id: json['id']! as String,
    name: json['name']! as String,
    licence: json['licence']! as String,
    regionExcluded: <String>[
      for (final region
          in (json['region_excluded'] ?? <Object?>[]) as List<Object?>)
        region! as String,
    ],
    variants: <ModelVariant>[
      for (final variant in json['variants']! as List<Object?>)
        ModelVariant.fromJson(variant! as Map<String, Object?>),
    ],
  );

  final String id;
  final String name;

  /// The licence name the Model manager shows beside the size.
  final String licence;

  /// Where the licence forbids distribution (`translation.md`: the Tencent HY
  /// licence excludes the EU, UK and South Korea). The download button is
  /// additionally gated on a build flag; this is what that flag is *for*.
  final List<String> regionExcluded;

  final List<ModelVariant> variants;

  ModelVariant? variant(String id) {
    for (final variant in variants) {
      if (variant.id == id) return variant;
    }
    return null;
  }
}

/// `assets/models/manifest.json`, parsed. FR-M4-02.
@immutable
class ModelManifest {
  const ModelManifest({required this.version, required this.models});

  factory ModelManifest.parse(String source) {
    final json = jsonDecode(source) as Map<String, Object?>;
    return ModelManifest(
      version: json['manifest_version']! as int,
      models: <ModelEntry>[
        for (final model in json['models']! as List<Object?>)
          ModelEntry.fromJson(model! as Map<String, Object?>),
      ],
    );
  }

  final int version;
  final List<ModelEntry> models;

  ModelEntry? model(String id) {
    for (final model in models) {
      if (model.id == id) return model;
    }
    return null;
  }
}

/// What a model is doing, for one card in the Model manager.
@immutable
class ModelState {
  const ModelState({
    required this.entry,
    required this.variant,
    required this.status,
    this.bytesOnDisk = 0,
  });

  final ModelEntry entry;
  final ModelVariant variant;
  final ModelStatus status;

  /// How much has arrived. The progress line is this over [ModelVariant.bytes].
  final int bytesOnDisk;

  bool get isReady => status == ModelStatus.ready;

  double get progress =>
      variant.bytes == 0 ? 0 : (bytesOnDisk / variant.bytes).clamp(0, 1);
}

/// Where models live on disk, and what makes one usable.
///
/// The download itself is `background_downloader`'s job (FR-M4-01) and the
/// engines that load these files are M4's; this owns the directory layout, the
/// manifest, the checksum and the rule that decides when a directory counts as
/// a model.
///
/// The layout is two directories per model:
///
/// ```
/// <appSupport>/models/<id>/          the active model, only ever complete
/// <appSupport>/models/<id>.staging/  where a download lands
/// ```
///
/// Nothing reads from the staging directory and nothing writes to the active
/// one. A partial download cannot activate because activation is a directory
/// rename that only happens after [verify] passes — there is no state in which
/// half a file is sitting where the engine looks.
class ModelRepository {
  ModelRepository(this._settings, {this.support});

  /// Where the manifest is bundled. FR-M4-02.
  static const String manifestAsset = 'assets/models/manifest.json';

  static const String _stagingSuffix = '.staging';

  final SettingsRepository _settings;

  /// The app-support directory. `bootstrap()` resolves it once and passes it
  /// in; left null it is looked up on each call, which is what a test that
  /// points it at a temporary directory relies on.
  final Directory? support;

  ModelManifest? _manifest;

  Future<Directory> _root() async {
    final root = support ?? await getApplicationSupportDirectory();
    return Directory('${root.path}/models');
  }

  /// Reads and caches the bundled manifest.
  Future<ModelManifest> manifest() async => _manifest ??= ModelManifest.parse(
    await rootBundle.loadString(manifestAsset),
  );

  /// Only for tests and for a manifest update (FR-M4-02 compares hashes).
  void useManifest(ModelManifest manifest) => _manifest = manifest;

  Future<Directory> directoryFor(String modelId) async =>
      Directory('${(await _root()).path}/$modelId');

  Future<Directory> stagingFor(String modelId) async =>
      Directory('${(await _root()).path}/$modelId$_stagingSuffix');

  /// Where the recorded answer for one exam attempt lives.
  ///
  /// `exam-writing-speaking.md` FR-L12S-02 names this path exactly, and
  /// FR-L12W-04 is why it is under app support rather than documents: it never
  /// leaves the device, and nothing browses it.
  Future<File> recordingFor(int attemptId) async {
    final root = support ?? await getApplicationSupportDirectory();
    return File('${root.path}/recordings/$attemptId.m4a');
  }

  /// Makes the staging directory, empty, and returns it. A retry starts clean
  /// rather than resuming into whatever the failed attempt left.
  Future<Directory> beginDownload(String modelId) async {
    final staging = await stagingFor(modelId);
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    staging.createSync(recursive: true);
    return staging;
  }

  /// Hashes what is in staging and compares it with the manifest.
  ///
  /// Returns [ModelStatus.ready] only when every file is there and the digest
  /// matches. A variant with no pinned hash can never reach it.
  Future<ModelStatus> verify(String modelId, ModelVariant variant) async {
    final staging = await stagingFor(modelId);
    if (!staging.existsSync()) return ModelStatus.notDownloaded;
    if (!variant.isPinned) return ModelStatus.failed;

    for (final name in variant.files) {
      if (!File('${staging.path}/$name').existsSync()) {
        return ModelStatus.failed;
      }
    }

    final digest = await _digestOf(staging, variant);
    return digest == variant.sha256!.toLowerCase()
        ? ModelStatus.ready
        : ModelStatus.failed;
  }

  /// Verifies and, only then, moves staging into place. FR-M4-01.
  ///
  /// The old directory is deleted first, so a failure between the two leaves
  /// no model rather than a mixture of two — the next launch reports
  /// `notDownloaded` and the learner downloads again, which is recoverable.
  /// A half-merged directory is not.
  Future<ModelStatus> activate(String modelId, ModelVariant variant) async {
    final status = await verify(modelId, variant);
    if (status != ModelStatus.ready) return status;

    final active = await directoryFor(modelId);
    final staging = await stagingFor(modelId);
    if (active.existsSync()) active.deleteSync(recursive: true);
    staging.renameSync(active.path);
    await _writeStamp(modelId, variant);
    return ModelStatus.ready;
  }

  /// What the card shows for [variant] right now.
  Future<ModelState> stateOf(ModelEntry entry, ModelVariant variant) async {
    final active = await directoryFor(entry.id);
    final staging = await stagingFor(entry.id);

    if (active.existsSync()) {
      final stamped = await _readStamp(entry.id);
      if (stamped == null || !_hasAll(active, variant)) {
        return ModelState(
          entry: entry,
          variant: variant,
          status: ModelStatus.failed,
          bytesOnDisk: _sizeOf(active),
        );
      }
      // FR-M4-02: an update is a manifest whose hash differs from the one this
      // directory was activated with. Comparing stamps rather than re-hashing
      // the file, because re-hashing half a gigabyte on every launch is not
      // something to do to find out nothing changed.
      return ModelState(
        entry: entry,
        variant: variant,
        status: stamped == variant.sha256
            ? ModelStatus.ready
            : ModelStatus.updateAvailable,
        bytesOnDisk: _sizeOf(active),
      );
    }

    if (staging.existsSync()) {
      return ModelState(
        entry: entry,
        variant: variant,
        status: ModelStatus.downloading,
        bytesOnDisk: _sizeOf(staging),
      );
    }

    return ModelState(
      entry: entry,
      variant: variant,
      status: ModelStatus.notDownloaded,
    );
  }

  /// FR-M4-03: deleting a model turns off what depended on it.
  ///
  /// The setting is written after the files are gone, so a failure to delete
  /// leaves the model both present and enabled rather than enabled and
  /// missing.
  Future<void> delete(String modelId) async {
    for (final directory in <Directory>[
      await directoryFor(modelId),
      await stagingFor(modelId),
    ]) {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    }

    switch (modelId) {
      case 'supertonic3':
        await _settings.write(SettingKeys.ttsEngine, TtsEngine.system);
      case 'hymt':
        await _settings.write(SettingKeys.mtEnabled, false);
    }
  }

  /// Total bytes the models take, for the storage card.
  Future<int> bytesUsed() async {
    final root = await _root();
    return root.existsSync() ? _sizeOf(root) : 0;
  }

  /// The hash this directory was activated with, so an update can be spotted
  /// without re-reading the model.
  Future<File> _stampFile(String modelId) async =>
      File('${(await directoryFor(modelId)).path}/.installed');

  Future<void> _writeStamp(String modelId, ModelVariant variant) async =>
      (await _stampFile(modelId))
          .writeAsString('${variant.id}\n${variant.sha256}\n');

  Future<String?> _readStamp(String modelId) async {
    final file = await _stampFile(modelId);
    if (!file.existsSync()) return null;
    final lines = (await file.readAsString()).split('\n');
    return lines.length < 2 || lines[1].isEmpty ? null : lines[1];
  }

  /// One digest over every file of the variant, in the order the manifest
  /// lists them — so a model that is several files has one hash to pin, and
  /// reordering the list is a different hash rather than the same one.
  Future<String> _digestOf(Directory directory, ModelVariant variant) async {
    final output = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(output);
    for (final name in variant.files) {
      await for (final chunk in File('${directory.path}/$name').openRead()) {
        input.add(chunk);
      }
    }
    input.close();
    return output.events.single.toString();
  }

  static bool _hasAll(Directory directory, ModelVariant variant) => variant
      .files
      .every((name) => File('${directory.path}/$name').existsSync());

  static int _sizeOf(Directory directory) {
    var bytes = 0;
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is File) bytes += entity.lengthSync();
    }
    return bytes;
  }
}
