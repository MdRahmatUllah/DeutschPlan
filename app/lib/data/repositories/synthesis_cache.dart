import 'dart:convert';
import 'dart:io';
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
    file.parent.createSync(recursive: true);
    File('${file.parent.path}/$_stamp').writeAsStringSync(version);
    await file.writeAsBytes(bytes, flush: true);
    await _evict();
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
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }

  Future<List<File>> _clips() async {
    final directory = await this.directory();
    if (!directory.existsSync()) return const <File>[];
    return <File>[
      for (final entity in directory.listSync())
        if (entity is File && entity.path.endsWith('.wav')) entity,
    ];
  }

  Future<void> _evict() async {
    final clips = await _clips();
    if (clips.length <= capacity) return;

    // Each clip's age read once, not twice for each comparison of the sort.
    final aged = <(File, DateTime)>[
      for (final clip in clips) (clip, clip.statSync().modified),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    for (final (clip, _) in aged.take(clips.length - capacity)) {
      if (clip.existsSync()) clip.deleteSync();
    }
  }
}
