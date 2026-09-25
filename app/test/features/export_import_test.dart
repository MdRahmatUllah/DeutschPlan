import 'dart:convert';
import 'dart:io';

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/backup_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/features/me/export_import_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/services/backup_files.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../core/text_clipping.dart';
import '../db/content_fixture.dart';

/// The share sheet and the file picker without a phone.
class FakeBackupFiles implements BackupFiles {
  /// What the picker hands back; null is backing out of it.
  PickedBackup? picked;

  /// A file that isn't text.
  bool unreadable = false;

  /// Whether the share sheet was used rather than dismissed.
  bool shares = true;

  final List<PickedBackup> shared = <PickedBackup>[];

  @override
  Future<PickedBackup?> pick() async {
    if (unreadable) throw const FormatException('not UTF-8');
    return picked;
  }

  @override
  Future<bool> share(String name, String json) async {
    shared.add((name: name, json: json));
    return shares;
  }
}

/// M6 · Export / import — #148.
void main() {
  late AppLocalizations l10n;
  late Directory directory;
  late File content;
  late AppDatabase db;
  late SettingsRepository settings;
  late FakeBackupFiles files;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
    directory = Directory.systemTemp.createTempSync('deutschplan_m6');
    content = ContentFixture.write('${directory.path}/content.db').file;
  });

  tearDownAll(() => directory.deleteSync(recursive: true));

  Future<AppDatabase> open() async {
    final opened = AppDatabase.memory();
    await opened.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
    );
    return opened;
  }

  Future<int> count(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM "$table"').getSingle())
          .read<int>('n');

  /// Another phone's export: two words, a review on 20 September, in A1.1,
  /// and the learner's name.
  Future<String> otherPhone({String name = 'Rahim'}) async {
    final other = await open();
    addTearDown(other.close);
    await other.customStatement(
      "INSERT INTO settings VALUES ('learner_name', '$name')",
    );
    await other.customStatement(
      'INSERT INTO enrollments (sublevel_code, started_on, daily_new, '
      "study_days_mask) VALUES ('A1.1', '2026-09-01', 7, 127)",
    );
    await other.customStatement(
      'INSERT INTO word_state (word_uid, status, stability, last_review) '
      "VALUES ('${ContentFixture.haus}', 'learning', 3.5, "
      "'2026-09-20T09:00:00Z'), ('${ContentFixture.tuer}', 'learning', 2, "
      "'2026-09-19T09:00:00Z')",
    );
    await other.customStatement(
      'INSERT INTO review_log (word_uid, reviewed_at, rating, source) '
      "VALUES ('${ContentFixture.haus}', '2026-09-20T09:00:00Z', 3, 'daily')",
    );
    return BackupRepository(other).exportJson();
  }

  setUp(() async {
    db = await open();
    settings = SettingsRepository(db);
    await settings.load();
    // This phone's own word, which a merge keeps and a replace doesn't.
    await db.customStatement(
      'INSERT INTO word_state (word_uid, status, stability, last_review) '
      "VALUES ('${ContentFixture.strasse}', 'learning', 1, "
      "'2026-09-18T09:00:00Z')",
    );
    files = FakeBackupFiles();
  });

  tearDown(() async {
    await settings.dispose();
    await db.close();
  });

  Future<void> pump(
    WidgetTester tester, {
    AdaptiveChrome chrome = AdaptiveChrome.material,
  }) async {
    tester.view
      ..physicalSize = const Size(1200, 2600)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWithValue(settings),
          clockProvider.overrideWithValue(() => DateTime(2026, 9, 21, 8)),
          backupFilesProvider.overrideWithValue(files),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          builder: (context, child) =>
              AdaptiveChromeScope(chrome: chrome, child: child!),
          home: const ExportImportScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String json) async {
    files.picked = (name: 'deutschplan-2026-09-20.json', json: json);
    await tester.tap(find.text(l10n.exportImportChoose));
    await tester.pumpAndSettle();
  }

  group('FR-M6-01 export', () {
    testWidgets('the button says how big the file is; never exported yet', (
      tester,
    ) async {
      await pump(tester);
      expect(
        find.textContaining(RegExp(r'^Export progress · \d+ KB$')),
        findsOneWidget,
      );
      expect(find.text(l10n.exportImportLastNever), findsOneWidget);
      expect(find.text(l10n.exportImportRecordings), findsOneWidget);
    });

    testWidgets('one dated JSON file to the share sheet, and the day kept', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.textContaining('Export progress'));
      await tester.pumpAndSettle();

      final file = files.shared.single;
      expect(file.name, 'deutschplan-2026-09-21.json');
      final backup = jsonDecode(file.json) as Map<String, Object?>;
      expect(backup['content_version'], ContentFixture.version);
      final tables = backup['tables']! as Map<String, Object?>;
      expect(tables['word_state'], hasLength(1));
      expect(settings.read(SettingKeys.lastExport), DateTime(2026, 9, 21));
      expect(find.text(l10n.exportImportLast('21 Sep')), findsOneWidget);
    });

    testWidgets('a dismissed share sheet is not an export', (tester) async {
      files.shares = false;
      await pump(tester);
      await tester.tap(find.textContaining('Export progress'));
      await tester.pumpAndSettle();

      expect(files.shared, hasLength(1));
      expect(settings.read(SettingKeys.lastExport), isNull);
      expect(find.text(l10n.exportImportLastNever), findsOneWidget);
    });
  });

  group('FR-M6-02 the preview', () {
    testWidgets('the chosen file is previewed, and nothing is written', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text(l10n.exportImportMerge), findsNothing);

      await choose(tester, await otherPhone());

      expect(find.text('deutschplan-2026-09-20.json'), findsOneWidget);
      expect(
        find.text('2 word states · last active 20 Sep · A1.1'),
        findsOneWidget,
      );
      expect(find.text(l10n.exportImportChooseOther), findsOneWidget);
      expect(await count('word_state'), 1);
      expect(await count('review_log'), 0);
    });

    testWidgets('a file from a newer build is refused', (tester) async {
      await pump(tester);
      final newer = jsonDecode(await otherPhone()) as Map<String, Object?>;
      newer['schema_version'] = AppDatabase.latestSchemaVersion + 1;
      await choose(tester, jsonEncode(newer));

      expect(find.text(l10n.exportImportNewer), findsOneWidget);
      expect(find.text(l10n.exportImportDoMerge), findsNothing);
    });

    testWidgets('a file that is not a backup says so', (tester) async {
      await pump(tester);
      await choose(tester, '{"hello": 1}');
      expect(find.text(l10n.exportImportNotABackup), findsOneWidget);
      expect(find.text(l10n.exportImportDoMerge), findsNothing);
    });

    testWidgets('nor does a file that is not text', (tester) async {
      await pump(tester);
      files.unreadable = true;
      await tester.tap(find.text(l10n.exportImportChoose));
      await tester.pumpAndSettle();
      expect(find.text(l10n.exportImportNotABackup), findsOneWidget);
    });

    testWidgets('backing out of the picker keeps the file chosen', (
      tester,
    ) async {
      await pump(tester);
      await choose(tester, await otherPhone());
      files.picked = null;
      await tester.tap(find.text(l10n.exportImportChooseOther));
      await tester.pumpAndSettle();
      expect(find.text('deutschplan-2026-09-20.json'), findsOneWidget);
    });
  });

  testWidgets('FR-M6-03 merge is the default, and keeps this phone’s words', (
    tester,
  ) async {
    await pump(tester);
    await choose(tester, await otherPhone());

    await tester.tap(find.text(l10n.exportImportDoMerge));
    await tester.pumpAndSettle();

    expect(await count('word_state'), 3);
    expect(await count('review_log'), 1);
    expect(find.text(l10n.exportImportDone), findsOneWidget);
    expect(find.text(l10n.exportImportChoose), findsOneWidget);
  });

  group('FR-M6-04 replace', () {
    testWidgets('asks first; keeping my data writes nothing', (tester) async {
      await pump(tester);
      await choose(tester, await otherPhone());

      await tester.tap(find.text(l10n.exportImportReplace));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.exportImportDoReplace));
      await tester.pumpAndSettle();
      expect(find.text(l10n.exportImportReplaceTitle), findsOneWidget);

      await tester.tap(find.text(l10n.exportImportReplaceCancel));
      await tester.pumpAndSettle();
      expect(await count('word_state'), 1);
    });

    testWidgets('confirmed, the file is all there is', (tester) async {
      await pump(tester);
      await choose(tester, await otherPhone());
      await tester.tap(find.text(l10n.exportImportReplace));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.exportImportDoReplace));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.exportImportReplaceConfirm));
      await tester.pumpAndSettle();

      final words = await db
          .customSelect('SELECT word_uid FROM word_state ORDER BY word_uid')
          .get();
      expect(
        <String>[for (final row in words) row.read<String>('word_uid')],
        <String>[ContentFixture.haus, ContentFixture.tuer],
      );
      expect(find.text(l10n.exportImportDone), findsOneWidget);
    });

    testWidgets('the settings the file brings are read at once', (
      tester,
    ) async {
      await pump(tester);
      final heard = <SettingKey<Object?>>[];
      final listening = settings.changes.listen(heard.add);
      addTearDown(listening.cancel);

      await choose(tester, await otherPhone(name: 'Nadia'));
      await tester.tap(find.text(l10n.exportImportReplace));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.exportImportDoReplace));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.exportImportReplaceConfirm));
      await tester.pumpAndSettle();

      expect(settings.read(SettingKeys.learnerName), 'Nadia');
      expect(heard, contains(SettingKeys.learnerName));
    });

    testWidgets('a failed import says nothing changed, and nothing did', (
      tester,
    ) async {
      await pump(tester);
      final broken = jsonDecode(await otherPhone()) as Map<String, Object?>;
      // A rating of 9 fails review_log's CHECK, after the wipe has run.
      ((broken['tables']! as Map<String, Object?>)['review_log']!
              as List<Object?>)
          .add(<String, Object?>{
            'word_uid': ContentFixture.haus,
            'reviewed_at': '2026-09-20T10:00:00Z',
            'rating': 9,
            'source': 'daily',
          });
      await choose(tester, jsonEncode(broken));
      await tester.tap(find.text(l10n.exportImportReplace));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.exportImportDoReplace));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.exportImportReplaceConfirm));
      await tester.pumpAndSettle();

      expect(find.text(l10n.exportImportFailed), findsOneWidget);
      expect(find.text(l10n.exportImportDone), findsNothing);
      expect(await count('word_state'), 1);
    });
  });

  testWidgets('a screen reader hears Merge and Replace as one set of radios', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    await choose(tester, await otherPhone());

    expect(
      tester.getSemantics(find.bySemanticsLabel(l10n.exportImportMerge)),
      isSemantics(
        isInMutuallyExclusiveGroup: true,
        hasCheckedState: true,
        isChecked: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel(l10n.exportImportReplace)),
      isSemantics(
        isInMutuallyExclusiveGroup: true,
        hasCheckedState: true,
        isChecked: false,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('a screen reader reaches each button on its own', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    final export = find.bySemanticsLabel(RegExp(r'^Export progress'));
    expect(export, findsOneWidget);
    expect(
      tester.getSemantics(export),
      isSemantics(isButton: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel(l10n.exportImportChoose)),
      isSemantics(isButton: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(
        find.bySemanticsLabel(l10n.exportImportExportHeading.toUpperCase()),
      ),
      isSemantics(isHeader: true),
    );
    semantics.dispose();
  });

  testWidgets('#314 at 200 % text nothing on M6 is cut', (tester) async {
    textAt(tester, 2);
    await pump(tester);
    await choose(tester, await otherPhone());
    expectNothingClipped(tester, within: find.byType(ExportImportScreen));
  });

  testWidgets('iOS: "Settings" beside the back chevron', (tester) async {
    await pump(tester, chrome: AdaptiveChrome.cupertino);
    expect(find.text(l10n.settingsTitle), findsOneWidget);
  });
}
