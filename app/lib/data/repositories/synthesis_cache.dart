import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// The last 200 synthesised strings, on disk. `tts.md`.
///
/// Keyed by (text, voice, speed): the same sentence at 0.75× is a different
/// recording, and the long-press speed is exactly the case that would
/// otherwise play back at the wrong rate from the cache.
///
/// On disk rather than in memory because synthesis costs about as much as a
/// short download and a learner replays the same headword across sessions —
/// and because holding two hundred WAVs in memory is the kind of thing that
/// gets an app killed in the background.
///
/// Eviction is by last read, not last write: a word the learner keeps tapping
/// stays, however long ago it was first synthesised.
///
/// A tenth goes at a time (#712): past [capacity], the oldest go down to
/// nine tenths of it, so the folder is listed and each clip's age read once
/// in twenty new clips, not on every one.
class SynthesisCache {
  SynthesisCache({this.support, this.capacity = 200, this.version = ''});

  /// `tts.md`: the last 200 synthesised strings.
  final int capacity;

  /// The app-support directory, as in `ModelRepository`.
  final Directory? support;

  /// What made the clips: Supertonic and its denoising steps. Clips kept
  /// under another version are stale, and go on the first use (#436).
  final String version;

  Future<Directory>? _directory;

  /// The clips on disk, as [write] last counted them: listed on the first
  /// write, then kept (#712). Null again after a [clear].
  int? _held;

  /// The clips' folder, emptied first if it holds another [version]'s.
  Future<Directory> directory() => _directory ??= () async {
    final root = support ?? await getApplicationSupportDirectory();
    final directory = Directory('${root.path}/tts-cache');
    final stamp = File('${directory.path}/$_stamp');
    // Awaited, not synchronous: up to 200 clips on the first word after an
    // update stay off the UI isolate.
    if (await directory.exists() &&
        (!await stamp.exists() || await stamp.readAsString() != version)) {
      await directory.delete(recursive: true);
    }
    return directory;
  }();

  /// The file that says which [version] made the clips beside it.
  static const String _stamp = 'version';

  /// The file a clip would live in, whether or not it is there.
  ///
  /// Hashed rather than named after the text: a sentence is longer than a file
  /// name may be, and it can contain a slash.
  Future<File> fileFor(
    String text, {
    required String voice,
    required double speed,
  }) async => File(
    '${(await directory()).path}/${keyFor(text, voice: voice, speed: speed)}.wav',
  );

  /// The cache key. Public because a test that cannot see the key cannot show
  /// that speed is part of it.
  static String keyFor(
    String text, {
    required String voice,
    required double speed,
  }) {
    // The speed is formatted rather than interpolated raw, so 0.75 and
    // 0.7500000001 do not become two entries for the same clip.
    final speedKey = speed.toStringAsFixed(2);
    return sha256
        .convert(utf8.encode('$voice\u0000$speedKey\u0000$text'))
        .toString()
        .substring(0, 32);
  }

  /// The clip, or null. Reading also marks it as recently used.
  Future<Uint8List?> read(
    String text, {
    required String voice,
    required double speed,
  }) async => (await hit(text, voice: voice, speed: speed))?.readAsBytes();

  /// The clip's file, or null: what a player needs, without reading the clip.
  /// It too marks the clip as recently used.
  Future<File?> hit(
    String text, {
    required String voice,
    required double speed,
  }) async {
    final file = await fileFor(text, voice: voice, speed: speed);
    if (!file.existsSync()) return null;
    // The eviction order is the file's modified time, so a use has to touch
    // it — otherwise the clip the learner uses most is the first one dropped.
    file.setLastModifiedSync(DateTime.now());
    return file;
  }

  /// Stores a clip and evicts down to [capacity].
  Future<File> write(
    String text, {
    required String voice,
    required double speed,
    required Uint8List bytes,
  }) async {
    final file = await fileFor(text, voice: voice, speed: speed);
    if (_held == null) {
      file.parent.createSync(recursive: true);
      File('${file.parent.path}/$_stamp').writeAsStringSync(version);
    }
    await file.writeAsBytes(bytes, flush: true);
    // A write follows a miss, so it is one more; a count that is off (a clip
    // deleted as unplayable) is set right by the next eviction's listing.
    final held = _held = _held == null ? await count() : _held! + 1;
    if (held > capacity) await _evict();
    return file;
  }

  /// How many clips are held. The Settings storage line reads this.
  Future<int> count() async => (await _clips()).length;

  Future<int> bytesUsed() async {
    var bytes = 0;
    for (final file in await _clips()) {
      bytes += file.lengthSync();
    }
    return bytes;
  }

  /// *Clear cache* in Settings, and what a voice change does — a clip made
  /// with the old voice is not the voice the learner just chose.
  Future<void> clear() async {
    final directory = await this.directory();
    _held = null;
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }

  Future<List<File>> _clips() async {
    final directory = await this.directory();
    if (!await directory.exists()) return const <File>[];
    return <File>[
      await for (final entity in directory.list())
        if (entity is File && entity.path.endsWith('.wav')) entity,
    ];
  }

  /// The oldest read go, down to nine tenths of [capacity]. Asynchronous
  /// (#712): the ages of 200 clips are read off the UI isolate.
  Future<void> _evict() async {
    final clips = await _clips();
    if (clips.length <= capacity) {
      _held = clips.length;
      return;
    }
    final keep = _held = capacity - math.max(1, capacity ~/ 10);

    // Each clip's age read once, not twice for each comparison of the sort.
    final aged = await Future.wait(<Future<(File, DateTime)>>[
      for (final clip in clips)
        clip.stat().then((stat) => (clip, stat.modified)),
    ]);
    aged.sort((a, b) => a.$2.compareTo(b.$2));
    for (final (clip, _) in aged.take(clips.length - keep)) {
      try {
        await clip.delete();
      } on FileSystemException {
        // Gone already: a clip that couldn't be played is deleted by its speak.
      }
    }
  }
}
