import 'dart:io';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

part 'content_dao.g.dart';

/// Where the course is read from.
///
/// `docs/02-data/content-database.md`: content.db is bundled as an asset,
/// copied to app-support storage on first run or when `meta.content_version`
/// differs, then **attached** to the user database as schema `c` and opened
/// read-only. The app never writes to it.
///
/// Every query is hand-written SQL in `content.drift`, because drift generates
/// nothing for an attached database. It type-checks them against
/// `content_schema.drift`, which mirrors the pipeline's DDL.
@DriftAccessor(include: <String>{'content.drift'})
class ContentDao extends DatabaseAccessor<AppDatabase> with _$ContentDaoMixin {
  ContentDao(super.db);

  /// The schema name the doc uses. Queries do not write it — see the note at
  /// the top of `content.drift` — but `ATTACH` does, and so does anything that
  /// needs to be explicit.
  static const String schema = 'c';

  /// The bundled asset.
  static const String asset = 'assets/db/content.db';

  /// The installed copy's file name, under app support.
  static const String fileName = 'content.db';

  /// Attaches the installed copy, copying it from the asset first if needed.
  ///
  /// Returns the version now attached.
  ///
  /// The attach is by plain path, not by a `file:…?mode=ro` URI. SQLite only
  /// parses a URI filename when the *main* connection was opened with
  /// `SQLITE_OPEN_URI`, and the one `drift_flutter` opens is not — so the URI
  /// is taken as a literal file name and the attach fails.
  ///
  /// Read-only is kept by construction instead, which is stronger than a flag
  /// nobody re-checks: `content.drift` holds only SELECTs, the manager API
  /// that would generate writers is off, and `architecture_test.dart` fails
  /// the build if anything under `lib/` writes to a content table. ADR 26.
  Future<String> attach() async {
    final file = await installedFile();
    if (!file.existsSync()) {
      await _copyAsset(file);
    }

    await customStatement("ATTACH DATABASE '${attachPath(file)}' AS $schema");
    return version();
  }

  Future<void> detach() => customStatement('DETACH DATABASE $schema');

  /// `meta.content_version` of the attached copy.
  Future<String> version() async {
    final row = await contentMeta('content_version').getSingleOrNull();
    if (row == null) {
      throw StateError(
        'the attached content.db has no content_version. It was not written '
        'by the pipeline, or it is truncated.',
      );
    }
    return row;
  }

  /// `meta.content_version` of the **bundled** asset, without installing it.
  ///
  /// This is the probe `content-database.md` step 1 describes: the app has to
  /// know whether the asset is newer than the installed copy before deciding
  /// to replace it, and reading the asset means writing it somewhere first,
  /// because SQLite cannot open a Flutter asset in place.
  Future<String> bundledVersion() async {
    final probe = File(
      '${(await getTemporaryDirectory()).path}/content_probe.db',
    );
    try {
      await _copyAsset(probe);
      await customStatement("ATTACH DATABASE '${attachPath(probe)}' AS probe");
      final row = await customSelect(
        "SELECT value FROM probe.meta WHERE key = 'content_version'",
      ).getSingleOrNull();
      return row?.read<String>('value') ?? '';
    } finally {
      // Detached here, not after the SELECT: a truncated asset throws between
      // the two, and a probe left attached makes every later call fail with
      // "database probe is already in use". The app would then stop noticing
      // content updates for the rest of the session, with nothing on screen
      // to say why.
      try {
        await customStatement('DETACH DATABASE probe');
      } on Object {
        // It was never attached, which is the only way this throws here.
      }
      if (probe.existsSync()) probe.deleteSync();
    }
  }

  /// The installed copy, in app-support storage beside user.db.
  Future<File> installedFile() async =>
      File('${(await getApplicationSupportDirectory()).path}/$fileName');

  /// Replaces the installed copy with the bundled asset.
  ///
  /// The new copy is written beside the old one and only swapped in once it is
  /// on disk. Detaching first and then copying would leave the connection with
  /// no `c` schema at all if the copy failed — a full disk, a revoked
  /// permission — and every screen that reads the course would error until the
  /// app was restarted. Stale content is the better failure.
  ///
  /// The detach still has to happen before the rename: overwriting a file
  /// SQLite has open is how a database becomes unreadable rather than merely
  /// out of date.
  Future<void> replaceWithBundled() async {
    final installed = await installedFile();
    final incoming = File('${installed.path}.new');

    await _copyAsset(incoming);
    await detach();
    try {
      incoming.renameSync(installed.path);
    } finally {
      // Whatever happened, the course has to come back.
      await attach();
    }
  }

  Future<void> _copyAsset(File target) async {
    final bytes = await rootBundle.load(asset);
    target.parent.createSync(recursive: true);
    // flush: the next line opens this file with SQLite, and a buffered write
    // would give it a truncated header.
    target.writeAsBytesSync(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      flush: true,
    );
  }

  /// The path as it goes inside a quoted `ATTACH DATABASE '…'`.
  ///
  /// Only the quote is escaped. A Windows path keeps its backslashes, because
  /// SQLite treats the string as a file name rather than as an escape
  /// sequence — and rewriting it to forward slashes is what turned it into a
  /// URI that would not open.
  static String attachPath(File file) =>
      file.absolute.path.replaceAll("'", "''");
}
