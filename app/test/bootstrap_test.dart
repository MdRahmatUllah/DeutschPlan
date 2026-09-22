@TestOn('vm')
library;

import 'dart:io';

import 'dart:convert';

import 'package:deutschplan/data/repositories/backup_repository.dart';
import 'package:deutschplan/bootstrap.dart';
import 'package:share_plus/share_plus.dart' show XFile;
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/features/bootstrap/bootstrap_error_screen.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/theme/glass_capability.dart';
import 'package:deutschplan/core/theme/theme_mode.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/db/content_update.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/main.dart';
import 'package:deutschplan/router/app_router.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart'
    show Brightness, MaterialApp, Text;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqlite3/sqlite3.dart';

import 'db/content_fixture.dart';

/// `bootstrap()` — FR-S1-01…04.
///
/// The bundled `assets/db/content.db` is produced by `make content` from four
/// workbooks that are not in this repository, so the asset bundle is faked
/// with a database built from the pipeline's own DDL. What is real here is
/// every step bootstrap takes: the file is written, opened, attached and read
/// back through SQLite exactly as it would be on a phone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory support;
  late Directory temp;
  late Uint8List contentAsset;
  late String manifestAsset;

  setUpAll(() {
    final staging = Directory.systemTemp.createTempSync('deutschplan_asset');
    final file = ContentFixture.write('${staging.path}/content.db').file;
    contentAsset = file.readAsBytesSync();
    manifestAsset =
        '{"content_version":"${ContentFixture.version}","words":{}}';
    staging.deleteSync(recursive: true);
  });

  setUp(() {
    support = Directory.systemTemp.createTempSync('deutschplan_support');
    temp = Directory.systemTemp.createTempSync('deutschplan_temp');
    PathProviderPlatform.instance = _FakePathProvider(support, temp);
    _serveAssets(<String, Uint8List>{
      ContentDao.asset: contentAsset,
      ContentUpdater.manifestAsset: Uint8List.fromList(manifestAsset.codeUnits),
    });
  });

  tearDown(() {
    _serveAssets(const <String, Uint8List>{});
    for (final directory in <Directory>[support, temp]) {
      try {
        directory.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows releases it a moment later.
      }
    }
  });

  /// A database whose file lives in the fake app-support directory, so the
  /// attach and the copy go through the same paths they would on a phone.
  AppDatabase openReal() => AppDatabase(
    DatabaseConnection(
      NativeDatabase(
        File('${support.path}/user.db'),
        setup: configureConnection,
      ),
    ),
  );

  Future<Bootstrap> run({
    AppDatabase Function()? open,
    Brightness brightness = Brightness.light,
  }) async {
    final result = await bootstrap(
      openDatabase: open ?? openReal,
      platformBrightness: brightness,
      glass: GlassCapability(),
    );
    expect(
      result,
      isA<BootstrapReady>(),
      reason: result is BootstrapFailed
          ? '${result.failure.step}: ${result.failure.error}'
          : null,
    );
    return (result as BootstrapReady).bootstrap;
  }

  group('FR-S1-01 — what bootstrap has to do', () {
    test('creates the schema when user.db is absent', () async {
      expect(File('${support.path}/user.db').existsSync(), isFalse);

      final ready = await run();
      addTearDown(ready.dispose);

      expect(
        await ready.db.fileSchemaVersion(),
        AppDatabase.latestSchemaVersion,
      );
      expect(File('${support.path}/user.db').existsSync(), isTrue);
    });

    test('installs and attaches the course', () async {
      final ready = await run();
      addTearDown(ready.dispose);

      expect(File('${support.path}/content.db').existsSync(), isTrue);
      expect(ready.contentVersion, ContentFixture.version);

      // Attached means readable, not merely present.
      final row = await ready.db
          .customSelect('SELECT COUNT(*) AS n FROM c.words')
          .getSingle();
      expect(row.read<int>('n'), 3);
    });

    test('loads the settings into memory', () async {
      final ready = await run();
      addTearDown(ready.dispose);

      // `read` throws until `load` has run, so this is the assertion.
      expect(ready.settings.read(SettingKeys.dailyNew), 7);
    });

    test('resolves the theme against the platform', () async {
      final light = await run();
      expect(light.themeMode, DpMode.light);
      await light.dispose();

      final dark = await run(brightness: Brightness.dark);
      addTearDown(dark.dispose);
      expect(dark.themeMode, DpMode.dark);
    });

    test('following the system is not the same as pinning it', () async {
      // `theme_mode` defaults to system, which resolves to a fixed light or
      // dark for the first frame — but the app has to keep following the
      // platform afterwards, or turning the phone to dark would leave
      // DeutschPlan light until it was killed.
      final ready = await run(brightness: Brightness.dark);
      addTearDown(ready.dispose);

      expect(ready.themeMode, DpMode.dark);
      expect(ready.themeSetting, ThemeModeSetting.system);
      expect(ready.themeSetting.followsPlatform, isTrue);
    });

    test('the learner"s own choice beats the platform', () async {
      final first = await run();
      await first.settings.write(SettingKeys.themeMode, ThemeModeSetting.light);
      await first.dispose();

      final second = await run(brightness: Brightness.dark);
      addTearDown(second.dispose);
      expect(second.themeMode, DpMode.light);
    });

    test('a learner who has not enrolled opens on onboarding', () async {
      // `splash.md`: S1 "leads to S2 (no enrollment) · T1". The route guards
      // only send an *enrolled* learner away from onboarding — nothing sent a
      // new one to it, so a fresh install opened on an empty Today and setup
      // was never seen. Caught on the device, not by a test.
      final ready = await run();
      addTearDown(ready.dispose);

      expect(
        ready.router.routeInformationProvider.value.uri.path,
        '/onboarding/1',
      );
    });

    test('and one who has enrolled opens on Today', () async {
      final first = await run();
      await first.db.customStatement(
        "INSERT INTO enrollments (sublevel_code, started_on, daily_new, "
        "study_days_mask) VALUES ('A1.1', '2026-03-02', 7, 127)",
      );
      await first.dispose();

      final second = await run();
      addTearDown(second.dispose);

      expect(second.router.routeInformationProvider.value.uri.path, '/today');
    });

    test('it knows a first run from a later one', () async {
      final first = await run();
      expect(first.isFirstRun, isTrue);
      await first.dispose();

      final second = await run();
      addTearDown(second.dispose);
      expect(second.isFirstRun, isFalse);
    });

    test('an update that changed no words is still not a first run', () async {
      // The case the change cannot answer: a version bump with an identical
      // word list reports an empty change, exactly as a first install does.
      // Splash's "first start only" caption is what would be wrong.
      final first = await run();
      await first.dispose();

      final staging = Directory.systemTemp.createTempSync('deutschplan_same');
      final next = ContentFixture.write('${staging.path}/content.db').file;
      final db = sqlite3.open(next.path);
      db.execute(
        "UPDATE meta SET value = '202603031200' WHERE key = 'content_version'",
      );
      db.close();
      _serveAssets(<String, Uint8List>{
        ContentDao.asset: next.readAsBytesSync(),
        ContentUpdater.manifestAsset: Uint8List.fromList(
          '{"content_version":"202603031200","words":{}}'.codeUnits,
        ),
      });
      addTearDown(() => staging.deleteSync(recursive: true));

      final second = await run();
      addTearDown(second.dispose);

      expect(second.contentChange, isNotNull);
      expect(second.contentChange!.isEmpty, isTrue);
      expect(second.isFirstRun, isFalse);
    });

    test('a second launch does not reinstall the course', () async {
      final first = await run();
      await first.dispose();

      // A marker inside the installed file. If it survives, the file was not
      // replaced — which is what "copy when the version differs" means.
      final installed = sqlite3.open('${support.path}/content.db');
      installed.execute(
        "INSERT INTO meta (\"key\", value) VALUES ('marker', 'kept')",
      );
      installed.close();

      final second = await run();
      addTearDown(second.dispose);

      final row = await second.db
          .customSelect("SELECT value FROM c.meta WHERE key = 'marker'")
          .getSingleOrNull();
      expect(row?.read<String>('value'), 'kept');
      expect(second.contentChange, isNull);
    });

    test('a newer bundled course replaces the installed one', () async {
      final first = await run();
      await first.dispose();

      // The pipeline's next build: same rows, later version.
      final staging = Directory.systemTemp.createTempSync('deutschplan_next');
      final next = ContentFixture.write('${staging.path}/content.db').file;
      final db = sqlite3.open(next.path);
      db.execute(
        "UPDATE meta SET value = '202602021200' WHERE key = 'content_version'",
      );
      db.close();
      _serveAssets(<String, Uint8List>{
        ContentDao.asset: next.readAsBytesSync(),
        ContentUpdater.manifestAsset: Uint8List.fromList(
          '{"content_version":"202602021200","words":{}}'.codeUnits,
        ),
      });
      addTearDown(() => staging.deleteSync(recursive: true));

      final second = await run();
      addTearDown(second.dispose);

      expect(second.contentVersion, '202602021200');
      expect(second.contentChange, isNotNull);
    });
  });

  group('FR-S1-03 — a failure is recoverable', () {
    test('a database that will not open reports the step', () async {
      // A directory where the file should be. drift creates missing parent
      // directories, so a bad path alone is not enough to make the open fail.
      Directory('${support.path}/not-a-file').createSync();

      final result = await bootstrap(
        openDatabase: () => AppDatabase(
          DatabaseConnection(
            NativeDatabase(File('${support.path}/not-a-file')),
          ),
        ),
        glass: GlassCapability(),
      );

      expect(result, isA<BootstrapFailed>());
      final failure = (result as BootstrapFailed).failure;
      expect(failure.step, BootstrapStep.database);
      expect(failure.canExport, isFalse, reason: 'there is nothing to export');
    });

    test('a course that will not install keeps the learner"s data', () async {
      // The one that matters. Every review they have ever done is in user.db,
      // and the error screen offers *Export progress* — so the database has to
      // survive the failure rather than be closed on the way out.
      _serveAssets(<String, Uint8List>{
        ContentDao.asset: Uint8List.fromList(<int>[0, 1, 2, 3]),
      });

      final result = await bootstrap(
        openDatabase: openReal,
        glass: GlassCapability(),
      );

      expect(result, isA<BootstrapFailed>());
      final failure = (result as BootstrapFailed).failure;
      addTearDown(failure.dispose);

      expect(failure.step, BootstrapStep.content);
      expect(failure.canExport, isTrue);
      expect(
        await failure.db!.customSelect('SELECT 1 AS n').getSingle(),
        isNotNull,
        reason: 'the database was closed on the way out',
      );
    });

    test('it never throws', () async {
      // The whole contract: `main` has no try/catch, and a bootstrap that
      // threw would be a blank screen — the one thing FR-S1-03 forbids.
      _serveAssets(const <String, Uint8List>{});

      await expectLater(
        bootstrap(openDatabase: openReal, glass: GlassCapability()),
        completion(isA<BootstrapFailed>()),
      );
    });

    test('retrying after a bad copy starts clean', () async {
      _serveAssets(<String, Uint8List>{
        ContentDao.asset: Uint8List.fromList(<int>[0, 1, 2, 3]),
      });
      final failed = await bootstrap(
        openDatabase: openReal,
        glass: GlassCapability(),
      );
      await (failed as BootstrapFailed).failure.dispose();
      expect(File('${support.path}/content.db').existsSync(), isTrue);

      await resetInstalledContent(support: support);
      expect(File('${support.path}/content.db').existsSync(), isFalse);

      _serveAssets(<String, Uint8List>{
        ContentDao.asset: contentAsset,
        ContentUpdater.manifestAsset: Uint8List.fromList(
          manifestAsset.codeUnits,
        ),
      });
      final ready = await run();
      addTearDown(ready.dispose);
      expect(ready.contentVersion, ContentFixture.version);
    });
  });

  group('FR-S1-02 — the launch budget', () {
    test('a warm start is under 500 ms', () async {
      final first = await run();
      await first.dispose();

      final warm = await run();
      addTearDown(warm.dispose);

      expect(
        warm.elapsed.inMilliseconds,
        lessThan(500),
        reason: 'warm start took ${warm.elapsed.inMilliseconds} ms',
      );
    });

    test('a first run is under 2 s', () async {
      final first = await run();
      addTearDown(first.dispose);

      expect(
        first.elapsed.inMilliseconds,
        lessThan(2000),
        reason: 'first run took ${first.elapsed.inMilliseconds} ms',
      );
    });
  });

  group('FR-S1-03 — the error screen', () {
    BootstrapFailure failureOf(BootstrapStep step, {AppDatabase? db}) =>
        BootstrapFailure(
          step: step,
          error: StateError('nope'),
          stackTrace: StackTrace.current,
          db: db,
        );

    testWidgets('says which step failed', (tester) async {
      await tester.pumpWidget(
        BootstrapErrorApp(failure: failureOf(BootstrapStep.content)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('DeutschPlan could not install the course.'),
        findsOneWidget,
      );
    });

    testWidgets('offers Retry', (tester) async {
      var retried = 0;
      await tester.pumpWidget(
        BootstrapErrorApp(
          failure: failureOf(BootstrapStep.database),
          onRetry: () => retried++,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_retryButton);
      expect(retried, 1);
    });

    testWidgets('offers Export progress only when there is data', (
      tester,
    ) async {
      await tester.pumpWidget(
        BootstrapErrorApp(failure: failureOf(BootstrapStep.database)),
      );
      await tester.pumpAndSettle();
      expect(_exportButton, findsNothing);

      final db = AppDatabase.memory();
      addTearDown(db.close);
      await tester.pumpWidget(
        BootstrapErrorApp(
          failure: failureOf(BootstrapStep.content, db: db),
          onExport: () {},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Export progress'), findsOneWidget);
    });

    testWidgets('Retry is live, not a greyed-out button', (tester) async {
      // The gate is what makes it live. An error screen built without
      // callbacks renders both buttons disabled, which is a dead end rather
      // than the recoverable screen FR-S1-03 asks for.
      var attempts = 0;
      await tester.pumpWidget(
        BootstrapGate(
          failure: failureOf(BootstrapStep.database),
          onRetry: () async {
            attempts++;
            return BootstrapFailed(failureOf(BootstrapStep.database));
          },
        ),
      );
      await tester.pumpAndSettle();

      final retry = tester.widget<DpButton>(_retryButton);
      expect(retry.onPressed, isNotNull, reason: 'Retry is disabled');

      await tester.tap(_retryButton);
      await tester.pumpAndSettle();
      expect(attempts, 1);
    });

    testWidgets('a retry that works replaces the error screen', (tester) async {
      // Built by hand rather than through `run()`: `testWidgets` runs in a
      // fake-async zone, and a future waiting on the real disk never
      // completes inside one.
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final settings = SettingsRepository(db);
      await settings.load();
      final ready = Bootstrap(
        db: db,
        content: ContentDao(db),
        settings: settings,
        glass: GlassCapability(),
        router: buildRouter(),
        contentVersion: ContentFixture.version,
        contentChange: null,
        themeMode: DpMode.light,
        themeSetting: ThemeModeSetting.light,
        isFirstRun: false,
        elapsed: Duration.zero,
      );

      // A `ProviderScope`, because the app the gate swaps in watches the
      // theme provider. `main` builds the real one from bootstrap's
      // overrides; this is the same shape.
      await tester.pumpWidget(
        ProviderScope(
          overrides: ready.overrides,
          child: BootstrapGate(
            failure: failureOf(BootstrapStep.database),
            onRetry: () async => BootstrapReady(ready),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('DeutschPlan could not open your data.'),
        findsOneWidget,
      );

      await tester.tap(_retryButton);
      await tester.pumpAndSettle();

      expect(find.byType(BootstrapErrorApp), findsNothing);
      expect(find.byType(DeutschPlanApp), findsOneWidget);
    });

    testWidgets('a retry that fails again says so', (tester) async {
      await tester.pumpWidget(
        BootstrapGate(
          failure: failureOf(BootstrapStep.database),
          onRetry: () async =>
              BootstrapFailed(failureOf(BootstrapStep.content)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_retryButton);
      await tester.pumpAndSettle();

      expect(
        find.text('DeutschPlan could not install the course.'),
        findsOneWidget,
      );
    });

    testWidgets('is never a blank screen', (tester) async {
      for (final step in BootstrapStep.values) {
        await tester.pumpWidget(BootstrapErrorApp(failure: failureOf(step)));
        await tester.pumpAndSettle();
        expect(find.byType(Text), findsWidgets, reason: '$step');
      }
    });
  });

  group('FR-S1-03 — export from the error screen', () {
    testWidgets('tapping it hands a real file to the platform', (tester) async {
      // The test that actually catches the no-op. An assertion on the file
      // *format* could not: reverting the button to `() {}` left it green,
      // because nothing drove the button.
      //
      // `runAsync` because the tap does real disk work — reading the database
      // and writing the backup — and a `testWidgets` body is FakeAsync, where
      // those futures never complete and the share is never reached.
      final db = AppDatabase.memory();
      addTearDown(db.close);

      XFile? shared;
      await tester.pumpWidget(
        MaterialApp(
          home: BootstrapGate(
            failure: BootstrapFailure(
              step: BootstrapStep.content,
              error: 'no content',
              stackTrace: StackTrace.empty,
              db: db,
            ),
            onShare: (file) async => shared = file,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(_exportButton);

        // `onPressed` is a `VoidCallback`, so the export is fire-and-forget:
        // the tap returns long before the database has been read and the file
        // written. Bounded rather than a fixed delay — a sleep long enough to
        // be safe on a slow machine is a second wasted on every run, and one
        // short enough to be quick is a flake.
        for (var i = 0; i < 100 && shared == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });

      expect(shared, isNotNull, reason: 'the button did nothing');
      expect(shared!.path, endsWith(exportFileName));
      expect(File(shared!.path).existsSync(), isTrue);
    });

    // Plain `test`, not `testWidgets`: this pumps no widgets, and a
    // `testWidgets` body runs under FakeAsync where a real database future
    // never completes — the test hangs rather than failing.
    test('writes a real backup file, not a no-op', () async {
      // The button was wired to `() {}` and shipped, with a widget test that
      // only proved a counter incremented. That is the shape of the failure:
      // a test handed a fake callback cannot tell a real one from an empty
      // one, so this asserts the artefact instead.
      final db = AppDatabase.memory();
      addTearDown(db.close);

      final json = await BackupRepository(db).exportJson();
      final file = File('${temp.path}/$exportFileName');
      await file.writeAsString(json, flush: true);

      expect(file.existsSync(), isTrue);

      final decoded =
          jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      expect(decoded['tables'], isA<Map<String, Object?>>());
      expect(
        decoded['schema_version'],
        AppDatabase.latestSchemaVersion,
        reason: 'the import side reads this to know what it is looking at',
      );
    });

    test('and the name is the one import will look for', () {
      expect(exportFileName, endsWith('.json'));
      expect(exportFileName, 'deutschplan-backup.json');
    });
  });
}

/// Serves [assets] to `rootBundle`, replacing whatever was there.
/// The error screen's two actions, found by what they are rather than by the
/// Material type they used to be: #86 rebuilt them as `DpButton`, and a finder
/// on `FilledButton` was really asserting which framework widget was inside.
final Finder _retryButton = find.widgetWithText(DpButton, 'Retry');
final Finder _exportButton = find.widgetWithText(DpButton, 'Export progress');

void _serveAssets(Map<String, Uint8List> assets) {
  TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (ByteData? message) async {
        final key = const StringCodec().decodeMessage(message);
        final bytes = assets[key];
        if (bytes == null) return null;
        return ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
      });

  // `rootBundle` caches by key, and serving a different course here is
  // pretending a new *app version* shipped — which on a device means a new
  // process with an empty cache. Without this the second serve hands back the
  // first manifest, and the version disagrees with the database in a way that
  // cannot happen outside a test.
  for (final key in <String>[ContentDao.asset, ContentUpdater.manifestAsset]) {
    rootBundle.evict(key);
  }
}

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.support, this.temp);

  final Directory support;
  final Directory temp;

  @override
  Future<String?> getApplicationSupportPath() async => support.path;

  @override
  Future<String?> getTemporaryPath() async => temp.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => support.path;
}
