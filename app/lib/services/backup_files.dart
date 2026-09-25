import 'dart:convert';
import 'dart:io';

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
  /// Throws [FormatException] for a file that isn't UTF-8 text, which the
  /// screen shows as "not a DeutschPlan export".
  Future<PickedBackup?> pick();

  /// Writes [json] to a temporary file called [name] and opens the share
  /// sheet. False when the learner dismissed it.
  Future<bool> share(String name, String json);
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
    return (name: file.name, json: utf8.decode(await file.readAsBytes()));
  }

  @override
  Future<bool> share(String name, String json) async {
    // Temporary storage: a copy handed to another app, not state, as the
    // bootstrap error screen's export is.
    final file = File('${(await getTemporaryDirectory()).path}/$name');
    await file.writeAsString(json, flush: true);
    final result = await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(file.path, mimeType: 'application/json')],
      ),
    );
    return result.status != ShareResultStatus.dismissed;
  }
}
