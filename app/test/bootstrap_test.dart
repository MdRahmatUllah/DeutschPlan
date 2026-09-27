@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'dart:convert';

import 'package:sogda/data/repositories/backup_repository.dart';
import 'package:sogda/bootstrap.dart';
import 'package:share_plus/share_plus.dart' show XFile;
import 'package:sogda/core/components/sg_button.dart';
import 'package:sogda/features/bootstrap/bootstrap_error_screen.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/theme/glass_capability.dart';
import 'package:sogda/core/theme/theme_mode.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/data/db/content_update.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/main.dart';
import 'package:sogda/router/app_router.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart'
    show Brightness, MaterialApp, Text;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqlite3/sqlite3.dart';

import 'db/content_fixture.dart';
import 'timing.dart';

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
    final staging = Directory.systemTemp.createTempSync('sogda_asset');
    final file = ContentFixture.write('${staging.path}/content.db').file;
    contentAsset = file.readAsBytesSync();
    manifestAsset =
        '{"content_version":"${ContentFixture.version}","words":{}}';
    staging.deleteSync(recursive: true);
  });

  setUp(() {
    support = Directory.systemTemp.createTempSync('sogda_support');
    temp = Directory.systemTemp.createTempSync('sogda_temp');
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
    void Function(UiLanguage)? onUiLanguage,
  }) async {
    final result = await bootstrap(
      openDatabase: open ?? openReal,
      platformBrightness: brightness,
      glass: GlassCapability(),
      onUiLanguage: onUiLanguage,
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
      expect(light.themeMode, SgMode.light);
      await light.dispose();

      final dark = await run(brightness: Brightness.dark);
      addTearDown(dark.dispose);
      expect(dark.themeMode, SgMode.dark);
    });

    test('following the system is not the same as pinning it', () async {
      // `theme_mode` defaults to system, which resolves to a fixed light or
      // dark for the first frame — but the app has to keep following the
      // platform afterwards, or turning the phone to dark would leave
      // Sogda light until it was killed.
      final ready = await run(brightness: Brightness.dark);
      addTearDown(ready.dispose);

      expect(ready.themeMode, SgMode.dark);
      expect(ready.themeSetting, ThemeModeSetting.system);
      expect(ready.themeSetting.followsPlatform, isTrue);
    });

    test('the learner"s own choice beats the platform', () async {
      final first = await run();
      await first.settings.write(SettingKeys.themeMode, ThemeModeSetting.light);
      await first.dispose();

      final second = await run(brightness: Brightness.dark);
      addTearDown(second.dispose);
      expect(second.themeMode, SgMode.light);
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

      final staging = Directory.systemTemp.createTempSync('sogda_same');
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
      final staging = Directory.systemTemp.createTempSync('sogda_next');
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

  group('the splash hears the app language early', () {
    // The splash renders before settings load, so without this it speaks the
    // phone's language and the app then switches to the learner's — on every
    // launch, for anyone whose two differ.
    test('before the course is installed, on a first run', () async {
      // On a first run the content install is most of the wait. Hearing the
      // language after it would leave the splash in the wrong one throughout.
      bool? contentThere;
      UiLanguage? heard;

      final ready = await run(
        onUiLanguage: (ui) {
          heard = ui;
          contentThere = File('${support.path}/content.db').existsSync();
        },
      );
      addTearDown(ready.dispose);

      expect(heard, UiLanguage.english, reason: 'the documented default');
      expect(contentThere, isFalse);
    });

    test('and it is the one the learner chose', () async {
      final first = await run();
      await first.settings.write(SettingKeys.uiLanguage, UiLanguage.bangla);
      await first.dispose();

      UiLanguage? heard;
      final ready = await run(onUiLanguage: (ui) => heard = ui);
      addTearDown(ready.dispose);

      expect(heard, UiLanguage.bangla);
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

    group('#619 a user.db that will not open offers the file itself', () {
      File userDb() => File('${support.path}/${AppDatabase.fileName}');
      late _Closes closes;
      setUp(() => closes = _Closes());
      AppDatabase openUserDb() => AppDatabase(
        DatabaseConnection(
          NativeDatabase(
            userDb(),
            setup: configureConnection,
          ).interceptWith(closes),
        ),
      );

      test('one from a newer build says to update', () async {
        final raw = sqlite3.open(userDb().path)
          ..execute('CREATE TABLE later (x INTEGER)')
          ..userVersion = AppDatabase.latestSchemaVersion + 1;
        raw.close();

        final result = await bootstrap(
          openDatabase: openUserDb,
          glass: GlassCapability(),
        );

        final failure = (result as BootstrapFailed).failure;
        expect(failure.step, BootstrapStep.database);
        expect(failure.canExport, isFalse);
        expect(failure.file?.path, userDb().path);
        expect(failure.newer, isTrue);
        expect(
          closes.count,
          1,
          reason:
              'closed before its file is offered, so no connection of '
              'ours checkpoints it mid-share',
        );
      });

      test('a corrupt one is offered too, and is not called newer', () async {
        userDb().writeAsBytesSync(List<int>.filled(4096, 7));

        final result = await bootstrap(
          openDatabase: openUserDb,
          glass: GlassCapability(),
        );

        final failure = (result as BootstrapFailed).failure;
        expect(failure.step, BootstrapStep.database);
        expect(failure.file?.path, userDb().path);
        expect(failure.newer, isFalse);
      });
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

    test('#617 FR-S1-03 an update whose copy fails starts on the old course, '
        'and the next launch installs it', () async {
      final first = await run();
      await first.dispose();

      // A newer course ships and its copy fails, as on a full disk: the
      // manifest says so, the database never lands.
      const newer = '202701010000';
      final newerManifest = Uint8List.fromList(
        '{"content_version":"$newer","words":{}}'.codeUnits,
      );
      _serveAssets(<String, Uint8List>{
        ContentUpdater.manifestAsset: newerManifest,
      });
      final second = await run();
      expect(second.contentVersion, ContentFixture.version);
      expect(
        support.listSync().where((file) => file.path.endsWith('.new')),
        isEmpty,
      );
      await second.dispose();

      // The next launch, with the space back: the newer course installs.
      final staging = File('${temp.path}/newer.db')
        ..writeAsBytesSync(contentAsset);
      sqlite3.open(staging.path)
        ..execute(
          "UPDATE meta SET value = '$newer' WHERE key = 'content_version'",
        )
        ..close();
      _serveAssets(<String, Uint8List>{
        ContentDao.asset: staging.readAsBytesSync(),
        ContentUpdater.manifestAsset: newerManifest,
      });
      final third = await run();
      addTearDown(third.dispose);
      expect(third.contentVersion, newer);
    });

    test('#617 FR-S1-03 Retry never deletes a course that reads', () async {
      final ready = await run();
      await ready.dispose();

      await resetInstalledContent(support: support);
      expect(
        File('${support.path}/${ContentDao.fileName}').existsSync(),
        isTrue,
      );
      expect(
        File('${support.path}/${ContentUpdater.manifestFile}').existsSync(),
        isTrue,
      );
    });
  });

  group('FR-S1-02 — the launch budget', () {
    // The fastest of three each, so a busy machine isn't what's measured
    // (#683). The phone's own launch time is perf.py's.
    test('a warm start is under 500 ms', () async {
      final first = await run();
      await first.dispose();

      var fastest = const Duration(days: 1);
      for (var i = 0; i < 3; i++) {
        final warm = await run();
        await warm.dispose();
        if (warm.elapsed < fastest) fastest = warm.elapsed;
      }

      expect(
        fastest.inMilliseconds,
        lessThan(500),
        reason: 'the fastest warm start took ${fastest.inMilliseconds} ms',
      );
    });

    test('a first run is under 2 s', () async {
      var fastest = const Duration(days: 1);
      for (var i = 0; i < 3; i++) {
        if (i > 0) {
          // A first run again: an empty app-support folder.
          final used = support;
          support = Directory.systemTemp.createTempSync('sogda_support');
          PathProviderPlatform.instance = _FakePathProvider(support, temp);
          try {
            used.deleteSync(recursive: true);
          } on FileSystemException {
            // Windows releases it a moment later.
          }
        }
        final first = await run();
        await first.dispose();
        if (first.elapsed < fastest) fastest = first.elapsed;
      }

      expect(
        fastest.inMilliseconds,
        lessThan(2000),
        reason: 'the fastest first run took ${fastest.inMilliseconds} ms',
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

      expect(find.text('Sogda could not install the course.'), findsOneWidget);
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
          onExport: () async => true,
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
          onReady: (_) {},
          onRetry: () async {
            attempts++;
            return BootstrapFailed(failureOf(BootstrapStep.database));
          },
        ),
      );
      await tester.pumpAndSettle();

      final retry = tester.widget<SgButton>(_retryButton);
      expect(retry.onPressed, isNotNull, reason: 'Retry is disabled');

      await tester.tap(_retryButton);
      await tester.pumpAndSettle();
      expect(attempts, 1);
    });

    testWidgets('FR-S1-03 #643 a retry that works opens the app in a '
        'container of its own, wired as a first start', (tester) async {
      // Through the host, as `main` runs it. The gate used to build the app
      // itself, under the failed start's container, which carries no
      // overrides: the app's first frame threw (settingsProvider is
      // unimplemented there), and nothing it needs had been started. A gate
      // wrapped in the ready overrides by hand, as this test once was, could
      // not see either.
      //
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
        themeMode: SgMode.light,
        themeSetting: ThemeModeSetting.light,
        isFirstRun: false,
        elapsed: Duration.zero,
      );

      var runs = 0;
      final wired = <Bootstrap>[];
      await tester.pumpWidget(
        BootstrapHost(
          run:
              ({
                Brightness platformBrightness = Brightness.light,
                void Function(UiLanguage)? onUiLanguage,
              }) async => runs++ == 0
              ? BootstrapFailed(failureOf(BootstrapStep.database))
              : BootstrapReady(ready),
          // The plugins behind the real wiring have no platform side here.
          wire: (container, bootstrap) => wired.add(bootstrap),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sogda could not open your data.'), findsOneWidget);
      expect(wired, isEmpty, reason: 'a failed start wires nothing');

      await tester.tap(_retryButton);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(BootstrapErrorApp), findsNothing);
      expect(find.byType(SogdaApp), findsOneWidget);
      expect(runs, 2);
      expect(wired, <Bootstrap>[ready], reason: 'the retry was not wired');
    });

    testWidgets('FR-S1-03 #652 a Retry that throws leaves Retry live', (
      tester,
    ) async {
      // It used to stay disabled for good: `_retrying` was set and never
      // cleared when a step threw.
      var attempts = 0;
      await tester.pumpWidget(
        BootstrapGate(
          failure: failureOf(BootstrapStep.database),
          onReady: (_) {},
          onRetry: () async {
            attempts++;
            throw StateError('disk full');
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_retryButton);
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(find.text('Sogda could not open your data.'), findsOneWidget);
      expect(
        tester.widget<SgButton>(_retryButton).onPressed,
        isNotNull,
        reason: 'Retry stayed dead',
      );

      await tester.tap(_retryButton);
      await tester.pumpAndSettle();
      expect(attempts, 2);
    });

    testWidgets('FR-S1-03 #652 a Retry that throws after closing the '
        'database leaves Export off, not offered on a closed file', (
      tester,
    ) async {
      // The retry closed the failure's database before it threw, so the
      // failure left on screen has nothing to export from: the export could
      // only ever say it failed.
      final db = AppDatabase.memory();
      addTearDown(db.close);
      await tester.pumpWidget(
        BootstrapGate(
          failure: failureOf(BootstrapStep.database, db: db),
          onReady: (_) {},
          onRetry: () async => throw StateError('disk full'),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<SgButton>(_exportButton).onPressed, isNotNull);

      await tester.tap(_retryButton);
      await tester.pumpAndSettle();
      expect(tester.widget<SgButton>(_exportButton).onPressed, isNull);
      expect(
        tester.widget<SgButton>(_retryButton).onPressed,
        isNotNull,
        reason: 'Retry is the way on',
      );
    });

    testWidgets('FR-S1-03 #652 a ready retry whose app fails to start leaves '
        'Retry live, and closes that database', (tester) async {
      final db = AppDatabase.memory();
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
        themeMode: SgMode.light,
        themeSetting: ThemeModeSetting.light,
        isFirstRun: false,
        elapsed: Duration.zero,
      );
      await tester.pumpWidget(
        BootstrapGate(
          failure: failureOf(BootstrapStep.database),
          onReady: (_) => throw StateError('the wiring threw'),
          onRetry: () async => BootstrapReady(ready),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_retryButton);
      await tester.pumpAndSettle();
      expect(
        tester.widget<SgButton>(_retryButton).onPressed,
        isNotNull,
        reason: 'Retry stayed dead',
      );
      await tester.runAsync(() async {
        await expectLater(
          db.customSelect('SELECT 1').get(),
          throwsA(anything),
          reason: 'the retry left user.db open behind it',
        );
      });
    });

    testWidgets('a retry that fails again says so', (tester) async {
      await tester.pumpWidget(
        BootstrapGate(
          failure: failureOf(BootstrapStep.database),
          onReady: (_) {},
          onRetry: () async =>
              BootstrapFailed(failureOf(BootstrapStep.content)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_retryButton);
      await tester.pumpAndSettle();

      expect(find.text('Sogda could not install the course.'), findsOneWidget);
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
            onReady: (_) {},
            onShare: (files) async => shared = files.single,
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
        await until(() => shared != null);
      });

      expect(shared, isNotNull, reason: 'the button did nothing');
      expect(shared!.path, endsWith(exportFileName));
      expect(File(shared!.path).existsSync(), isTrue);
    });

    testWidgets('#619 a user.db that would not open shares the file and its '
        'log', (tester) async {
      final raw = File('${support.path}/${AppDatabase.fileName}')
        ..writeAsStringSync('not a database');
      File('${raw.path}-wal').writeAsStringSync('frames');

      List<XFile>? shared;
      await tester.pumpWidget(
        BootstrapGate(
          failure: BootstrapFailure(
            step: BootstrapStep.database,
            error: 'file is not a database',
            stackTrace: StackTrace.empty,
            db: null,
            file: raw,
          ),
          onReady: (_) {},
          onShare: (files) async => shared = files,
        ),
      );
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(SgButton, 'Share your data file'));
        await until(() => shared != null);
      });

      expect(shared?.map((file) => file.path), <String>[
        raw.path,
        '${raw.path}-wal',
      ]);
    });

    testWidgets('#652 an export that fails says so, and can be tried again', (
      tester,
    ) async {
      // A throw used to vanish: no word, most likely in the corrupt-database
      // case the button exists for.
      final db = AppDatabase.memory();
      addTearDown(db.close);
      var tries = 0;
      await tester.pumpWidget(
        BootstrapGate(
          failure: BootstrapFailure(
            step: BootstrapStep.content,
            error: 'no content',
            stackTrace: StackTrace.empty,
            db: db,
          ),
          onReady: (_) {},
          onShare: (_) async {
            tries++;
            throw StateError('no share sheet');
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(_exportButton);
        await until(() => tries > 0);
        await pumpEventQueue();
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tries, 1);
      expect(find.text("The export didn't finish. Try again."), findsOneWidget);
      expect(tester.widget<SgButton>(_exportButton).onPressed, isNotNull);
    });

    testWidgets('#652 while it exports, Retry and Export are off, and a '
        'second tap exports once', (tester) async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final open = Completer<void>();
      var shares = 0;
      await tester.pumpWidget(
        BootstrapGate(
          failure: BootstrapFailure(
            step: BootstrapStep.content,
            error: 'no content',
            stackTrace: StackTrace.empty,
            db: db,
          ),
          onReady: (_) {},
          onShare: (_) async {
            shares++;
            await open.future;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(_exportButton);
        await until(() => shares > 0);
      });
      await tester.pump();
      expect(tester.widget<SgButton>(_exportButton).onPressed, isNull);
      expect(
        tester.widget<SgButton>(_retryButton).onPressed,
        isNull,
        reason: 'Retry would close the database being exported',
      );

      await tester.tap(_exportButton, warnIfMissed: false);
      await tester.runAsync(() async {
        open.complete();
        await pumpEventQueue();
      });
      await tester.pump();
      expect(shares, 1);
      expect(tester.widget<SgButton>(_exportButton).onPressed, isNotNull);
      expect(tester.widget<SgButton>(_retryButton).onPressed, isNotNull);
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
      expect(exportFileName, 'sogda-backup.json');
    });
  });
}

/// Serves [assets] to `rootBundle`, replacing whatever was there.
/// The error screen's two actions, found by what they are rather than by the
/// Material type they used to be: #86 rebuilt them as `SgButton`, and a finder
/// on `FilledButton` was really asserting which framework widget was inside.
final Finder _retryButton = find.widgetWithText(SgButton, 'Retry');
final Finder _exportButton = find.widgetWithText(SgButton, 'Export progress');

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

/// Counts the closes of the connection it wraps (#619).
class _Closes extends QueryInterceptor {
  int count = 0;

  @override
  Future<void> close(QueryExecutor inner) {
    count++;
    return inner.close();
  }
}
