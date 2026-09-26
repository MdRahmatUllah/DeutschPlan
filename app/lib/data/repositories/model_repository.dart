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

  /// All the bytes are there and the checksums are being read.
  verifying,

  /// Verified and in place. The only state anything is allowed to load from.
  ready,

  /// Ready, but the manifest now names a different checksum.
  updateAvailable,

  /// A checksum did not match, or a file is missing. *Retry* from here.
  failed,
}

/// One file of a download.
///
/// The file is the unit, not the variant: a host publishes a SHA-256 per file,
/// so hashing several together would give a number nobody upstream can
/// confirm. It also means a multi-file model can say *which* file failed.
@immutable
class ModelFile {
  const ModelFile({
    required this.name,
    required this.url,
    required this.bytes,
    required this.sha256,
  });

  factory ModelFile.fromJson(Map<String, Object?> json) => ModelFile(
    name: json['name']! as String,
    url: Uri.parse(json['url']! as String),
    bytes: json['bytes']! as int,
    sha256: json['sha256'] as String?,
  );

  /// The name on disk, relative to the model directory.
  final String name;

  final Uri url;
  final int bytes;

  /// SHA-256 as the host publishes it, lower-case hex.
  ///
  /// **Nullable on purpose.** A file whose artefact has not been pinned yet
  /// has no hash, and [ModelRepository.verify] refuses it — FR-M4-01 says a
  /// partial or unverified file never activates, and "we have not got round to
  /// the hash" is the same thing as unverified from the learner's side.
  final String? sha256;

  bool get isPinned => sha256 != null && sha256!.length == 64;
}

/// One downloadable build of a model.
@immutable
class ModelVariant {
  const ModelVariant({
    required this.id,
    required this.name,
    required this.files,
  });

  factory ModelVariant.fromJson(Map<String, Object?> json) => ModelVariant(
    id: json['id']! as String,
    name: json['name']! as String,
    files: <ModelFile>[
      for (final file in json['files']! as List<Object?>)
        ModelFile.fromJson(file! as Map<String, Object?>),
    ],
  );

  final String id;
  final String name;
  final List<ModelFile> files;

  /// What the Model manager prints, and what the space check is against.
  /// Summed rather than stated, so it cannot disagree with the files.
  int get bytes => files.fold(0, (total, file) => total + file.bytes);

  bool get isPinned => files.isNotEmpty && files.every((file) => file.isPinned);

  /// Identifies this exact build: the variant and every hash in it. What
  /// `activate` stamps, and what an update is compared against.
  String get fingerprint =>
      '$id:${files.map((file) => file.sha256 ?? '-').join(',')}';
}

/// One model, with the variants it can be downloaded as.
@immutable
class ModelEntry {
  const ModelEntry({
    required this.id,
    required this.name,
    required this.licence,
    required this.disables,
    required this.variants,
    required this.regionExcluded,
  });

  factory ModelEntry.fromJson(Map<String, Object?> json) => ModelEntry(
    id: json['id']! as String,
    name: json['name']! as String,
    licence: json['licence']! as String,
    disables: json['disables']! as String,
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

  /// The settings key deleting this model turns off (FR-M4-03).
  ///
  /// In the manifest rather than a `switch` on the model id, so renaming a
  /// model cannot quietly leave `tts_engine` pointing at an engine that is
  /// gone.
  final String disables;

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
    required this.variant,
    required this.status,
    this.entry,
    this.bytesOnDisk = 0,
    this.failedFile,
  });

  /// Null when the answer is about a variant rather than a card — see
  /// [ModelRepository.verifyIn].
  final ModelEntry? entry;

  final ModelVariant variant;
  final ModelStatus status;

  /// How much has arrived. The progress line is this over [ModelVariant.bytes].
  final int bytesOnDisk;

  /// Which file did not verify, when one did not. *Retry* does not need it;
  /// a bug report does.
  final String? failedFile;

  bool get isReady => status == ModelStatus.ready;

  double get progress =>
      variant.bytes == 0 ? 0 : (bytesOnDisk / variant.bytes).clamp(0, 1);
}

/// FR-M4-04: Hy-MT's download is offered only in a build made with
/// `--dart-define=ENABLE_HYMT_DOWNLOAD=true`. Off by default: the Tencent HY
/// licence excludes the EU, the UK and South Korea, and every v1.0 build
/// keeps it off (ADR 9, `translation.md`). M4 offers the download, and M3
/// shows its Translation group, by it (#513).
const bool enableHymtDownload = bool.fromEnvironment('ENABLE_HYMT_DOWNLOAD');

/// Where models live on disk, and what makes one usable.
///
/// The download itself is `background_downloader`'s job (FR-M4-01) and the
/// engines that load these files are M4's; this owns the directory layout, the
/// manifest, the checksums and the rule that decides when a directory counts
/// as a model.
///
/// The layout is two directories per model:
///
/// ```
/// <appSupport>/models/<id>/          the active model, only ever complete
/// <appSupport>/models/<id>.staging/  where a download lands
/// ```
///
/// Nothing reads from the staging directory and nothing writes to the active
/// one. A partial download cannot activate because activation happens only
/// after every checksum passes — there is no state in which half a file is
/// sitting where the engine looks.
class ModelRepository {
  ModelRepository(this._settings, {this.support});

  /// Where the manifest is bundled. FR-M4-02.
  static const String manifestAsset = 'assets/models/manifest.json';

  /// The model id the manifest gives the on-device voice.
  static const String voiceModel = 'supertonic3';

  /// The model id the manifest gives on-device translation.
  static const String translationModel = 'hymt';

  static const String _stagingSuffix = '.staging';

  /// Where the model being replaced waits while the new one is put in place.
  /// A directory left at this name is a crash during [activate].
  static const String _previousSuffix = '.previous';

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

  Future<Directory> stagingFor(String modelId) async {
    final root = support ?? await getApplicationSupportDirectory();
    return Directory('${root.path}/${stagingPath(modelId)}');
  }

  /// [stagingFor], relative to the app-support directory — the form the
  /// platform downloader takes, so the bytes land where [verify] looks.
  static String stagingPath(String modelId) => 'models/$modelId$_stagingSuffix';

  /// Where the recorded answer for one exam attempt lives.
  ///
  /// `exam-writing-speaking.md` FR-L12S-02 names this path exactly, and
  /// FR-L12W-04 is why it is under app support rather than documents: it never
  /// leaves the device, and nothing browses it.
  Future<File> recordingFor(int attemptId) async {
    final root = support ?? await getApplicationSupportDirectory();
    return File('${root.path}/recordings/$attemptId.m4a');
  }

  /// M7 (#149): the recordings of [attempts], or every one when it is null.
  /// The models beside them stay.
  Future<void> deleteRecordings([Iterable<int>? attempts]) async {
    if (attempts == null) {
      final root = support ?? await getApplicationSupportDirectory();
      final folder = Directory('${root.path}/recordings');
      if (await folder.exists()) await folder.delete(recursive: true);
      return;
    }
    for (final attempt in attempts) {
      final file = await recordingFor(attempt);
      if (await file.exists()) await file.delete();
    }
  }

  /// The staging directory to download into, keeping whatever is already
  /// there.
  ///
  /// FR-M4-01 asks for resumable downloads, and the point of resuming is that
  /// the bytes already on disk stay. [restartDownload] is what a checksum
  /// failure calls — a paused download and a corrupt one need opposite things.
  Future<Directory> beginDownload(String modelId) async {
    final staging = await stagingFor(modelId);
    staging.createSync(recursive: true);
    return staging;
  }

  /// What *Retry* calls. Throws away what the failed attempt left.
  ///
  /// Resuming into a corrupt file would append to it, hash to something that
  /// never matches, and leave the learner retrying for ever.
  Future<Directory> restartDownload(String modelId) async {
    final staging = await stagingFor(modelId);
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    return beginDownload(modelId);
  }

  /// Hashes what is in staging, file by file, against the manifest.
  ///
  /// [ModelStatus.ready] only when every file is there and every digest
  /// matches. A variant with an unpinned hash can never reach it.
  Future<ModelStatus> verify(String modelId, ModelVariant variant) async =>
      (await verifyIn(await stagingFor(modelId), variant)).status;

  /// [verify] against any directory, saying which file failed.
  Future<ModelState> verifyIn(Directory directory, ModelVariant variant) async {
    ModelState state(ModelStatus status, [String? failed]) =>
        ModelState(variant: variant, status: status, failedFile: failed);

    if (!directory.existsSync()) return state(ModelStatus.notDownloaded);
    if (variant.files.isEmpty) return state(ModelStatus.failed);

    for (final file in variant.files) {
      final onDisk = File('${directory.path}/${file.name}');
      if (!onDisk.existsSync()) return state(ModelStatus.failed, file.name);
      if (!file.isPinned) return state(ModelStatus.failed, file.name);
      if (await _digestOf(onDisk) != file.sha256!.toLowerCase()) {
        return state(ModelStatus.failed, file.name);
      }
    }

    return state(ModelStatus.ready);
  }

  /// Verifies and, only then, puts staging in place. FR-M4-01.
  ///
  /// The model being replaced is renamed aside rather than deleted, and only
  /// removed once the new one has landed. Every point in between is
  /// recoverable: a crash leaves either the old model or the new one, never a
  /// mixture and never nothing — which on a 1.1 GB download is the difference
  /// between an app restart and a second download over mobile data.
  Future<ModelStatus> activate(String modelId, ModelVariant variant) async {
    final status = await verify(modelId, variant);
    if (status != ModelStatus.ready) return status;

    final active = await directoryFor(modelId);
    final staging = await stagingFor(modelId);
    final previous = Directory('${active.path}$_previousSuffix');

    if (previous.existsSync()) previous.deleteSync(recursive: true);
    if (active.existsSync()) active.renameSync(previous.path);
    staging.renameSync(active.path);
    await _writeStamp(modelId, variant);
    if (previous.existsSync()) previous.deleteSync(recursive: true);

    return ModelStatus.ready;
  }

  /// What the card shows for [variant] right now.
  Future<ModelState> stateOf(ModelEntry entry, ModelVariant variant) async {
    final active = await directoryFor(entry.id);
    final staging = await stagingFor(entry.id);
    final previous = Directory('${active.path}$_previousSuffix');

    // A crash during `activate`, after the old model was renamed aside and
    // before the new one landed. The old one is intact, so put it back rather
    // than making the learner download again.
    if (!active.existsSync() && previous.existsSync()) {
      previous.renameSync(active.path);
    }

    if (active.existsSync()) {
      final stamped = await _readStamp(entry.id);

      ModelState state(ModelStatus status) => ModelState(
        entry: entry,
        variant: variant,
        status: status,
        bytesOnDisk: status == ModelStatus.notDownloaded ? 0 : _sizeOf(active),
      );

      // A directory nothing activated.
      if (stamped == null) return state(ModelStatus.failed);

      // The *other* variant of the same model is not an update — it is a
      // different download. Offering *Update* for it would replace a working
      // model rather than add the one the learner picked.
      if (!stamped.startsWith('${variant.id}:')) {
        return state(ModelStatus.notDownloaded);
      }

      // FR-M4-02: an update is a manifest whose hashes differ from the ones
      // this directory was activated with. Comparing stamps rather than
      // re-hashing, because re-reading half a gigabyte on every launch is not
      // something to do to find out nothing changed. It comes before the
      // files are counted: a manifest that adds a file (#152's two voices)
      // finds the model it verified without that file, and that is an
      // update, not a failure.
      if (stamped != variant.fingerprint) {
        return state(ModelStatus.updateAvailable);
      }

      // One a file has gone missing from.
      if (!_hasAll(active, variant)) return state(ModelStatus.failed);
      return state(ModelStatus.ready);
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
  /// missing. Which setting comes from [ModelEntry.disables].
  Future<void> delete(ModelEntry entry) async {
    final active = await directoryFor(entry.id);
    for (final directory in <Directory>[
      active,
      await stagingFor(entry.id),
      Directory('${active.path}$_previousSuffix'),
    ]) {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    }

    switch (entry.disables) {
      case 'tts_engine':
        await _settings.write(SettingKeys.ttsEngine, TtsEngineSetting.system);
      case 'mt_enabled':
        await _settings.write(SettingKeys.mtEnabled, false);
      default:
        // Loud, because the failure it guards against is silent: a model
        // deleted and a setting still pointing at it.
        throw StateError(
          'The manifest says deleting ${entry.id} disables '
          '"${entry.disables}", which nothing here knows how to turn off.',
        );
    }
  }

  /// Total bytes the models take, for the storage card.
  Future<int> bytesUsed() async {
    final root = await _root();
    return root.existsSync() ? _sizeOf(root) : 0;
  }

  /// The fingerprint this directory was activated with, so an update can be
  /// spotted without re-reading the model.
  Future<File> _stampFile(String modelId) async =>
      File('${(await directoryFor(modelId)).path}/.installed');

  Future<void> _writeStamp(String modelId, ModelVariant variant) async =>
      (await _stampFile(modelId)).writeAsString(variant.fingerprint);

  Future<String?> _readStamp(String modelId) async {
    final file = await _stampFile(modelId);
    if (!file.existsSync()) return null;
    final stamp = (await file.readAsString()).trim();
    return stamp.isEmpty ? null : stamp;
  }

  /// Streamed rather than read whole: the biggest of these is 1.1 GB.
  Future<String> _digestOf(File file) async {
    final output = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(output);
    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
    input.close();
    return output.events.single.toString();
  }

  static bool _hasAll(Directory directory, ModelVariant variant) => variant
      .files
      .every((file) => File('${directory.path}/${file.name}').existsSync());

  static int _sizeOf(Directory directory) {
    var bytes = 0;
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is File) bytes += entity.lengthSync();
    }
    return bytes;
  }
}
