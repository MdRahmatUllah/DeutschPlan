import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// A file the learner picked for M6's import: its name and what it holds.
typedef PickedBackup = ({String name, String json});

/// M6's two trips out of the app (#148): the share sheet and the file
/// picker. An interface so the screen can be tested without either, as
/// `ReminderNotifications` is.
abstract interface class BackupFiles {
  /// The system file picker; null when the learner backs out.
  ///
  /// Throws [FormatException] for a file that isn't UTF-8 text, or is bigger
  /// than [maxBytes], which the screen shows as "not a Sogda export".
  Future<PickedBackup?> pick();

  /// Writes [json] to a temporary file called [name] and opens the share
  /// sheet. False when the learner dismissed it.
  Future<bool> share(String name, String json);
}

/// The most a backup can be (#657). Ten years of daily study is some 35 MB
/// of JSON; a bigger file is not one, and reading it whole would freeze the
/// app, or run it out of memory, for nothing.
const int maxBytes = 64 * 1024 * 1024;

/// [bytes] as UTF-8 text, stopping with a [FormatException] once they pass
/// [cap], before the rest is read.
Future<String> readCapped(Stream<List<int>> bytes, {int cap = maxBytes}) async {
  final read = BytesBuilder(copy: false);
  await for (final chunk in bytes) {
    read.add(chunk);
    if (read.length > cap) {
      throw FormatException('over ${cap ~/ (1024 * 1024)} MB: not a backup');
    }
  }
  return utf8.decode(read.takeBytes());
}

/// [json] as [name] in [temporary]'s `exports` folder, emptied first: an
/// export's copy is handed to the share sheet (which keeps its own), and the
/// one before it is gone once there is a new one, rather than piling up in
/// the cache for good (#704).
Future<File> exportCopy(Directory temporary, String name, String json) async {
  final folder = Directory('${temporary.path}/exports');
  if (folder.existsSync()) folder.deleteSync(recursive: true);
  folder.createSync(recursive: true);
  final file = File('${folder.path}/$name');
  await file.writeAsString(json, flush: true);
  return file;
}

/// [BackupFiles] on `file_picker` and `share_plus`. Nothing here makes a
/// request: the learner picks where the file goes (BR-PRIV-01, -02).
class PlatformBackupFiles implements BackupFiles {
  const PlatformBackupFiles();

  @override
  Future<PickedBackup?> pick() async {
    // Any type: an export saved from a mail or a chat often loses the JSON
    // MIME type, and the preview refuses what isn't a backup anyway.
    final file = await FilePicker.pickFile();
    if (file == null) return null;
    return (name: file.name, json: await readCapped(file.readAsByteStream()));
  }

  @override
  Future<bool> share(String name, String json) async {
    // Temporary storage: a copy handed to another app, not state, as the
    // bootstrap error screen's export is.
    final file = await exportCopy(await getTemporaryDirectory(), name, json);
    final result = await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(file.path, mimeType: 'application/json')],
      ),
    );
    return result.status != ShareResultStatus.dismissed;
  }
}
