import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/data/repositories/model_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/features/me/model_manager_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/services/device_storage.dart';
import 'package:deutschplan/services/model_downloads.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../core/text_clipping.dart';
import '../services/fake_tts.dart';
import 'model_manager_fixtures.dart';
import 'settings_fixtures.dart';

/// M4 · Model manager — #155.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  Future<void> pump(WidgetTester tester, List<Override> overrides) async {
    tester.view
      ..physicalSize = const Size(390, 1400) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          home: const ModelManagerScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The button whose label is [label].
  DpButton button(WidgetTester tester, String label) => tester.widget<DpButton>(
    find.byWidgetPredicate(
      (widget) => widget is DpButton && widget.label == label,
    ),
  );

  group('FR-M4 the seven states', () {
    test('a download under way is the card\'s state, whatever is on disk', () {
      for (final phase in <DownloadPhase>[
        DownloadPhase.running,
        DownloadPhase.paused,
        DownloadPhase.waitingForWifi,
      ]) {
        expect(
          cardStatusOf(
            cardOf(
              voiceEntry,
              installed: ModelStatus.ready,
              live: (phase: phase, progress: 0.5),
            ),
          ),
          ModelCardStatus.downloading,
          reason: '$phase',
        );
      }
      expect(
        cardStatusOf(
          cardOf(
            voiceEntry,
            live: (phase: DownloadPhase.verifying, progress: 1),
          ),
        ),
        ModelCardStatus.verifying,
      );
      expect(
        cardStatusOf(
          cardOf(voiceEntry, live: (phase: DownloadPhase.failed, progress: 1)),
        ),
        ModelCardStatus.failed,
      );
    });

    test('with none, what is on the phone; and a phone too full for it is '
        'not enough space', () {
      expect(
        cardStatusOf(cardOf(voiceEntry, installed: ModelStatus.ready)),
        ModelCardStatus.ready,
      );
      expect(
        cardStatusOf(
          cardOf(voiceEntry, installed: ModelStatus.updateAvailable),
        ),
        ModelCardStatus.updateAvailable,
      );
      expect(
        cardStatusOf(cardOf(voiceEntry, installed: ModelStatus.failed)),
        ModelCardStatus.failed,
      );
      expect(cardStatusOf(cardOf(voiceEntry)), ModelCardStatus.notDownloaded);
      expect(
        cardStatusOf(cardOf(voiceEntry, shortfall: 1)),
        ModelCardStatus.notEnoughSpace,
      );
      expect(
        cardStatusOf(
          cardOf(
            voiceEntry,
            installed: ModelStatus.ready,
            live: (phase: DownloadPhase.ready, progress: 1),
          ),
        ),
        ModelCardStatus.ready,
        reason: 'a finished download is what it installed',
      );
    });

    test('sizes: whole megabytes, gigabytes to a decimal, in the UI\'s '
        'digits', () async {
      expect(modelSize(l10n, 399237419), '399 MB');
      expect(modelSize(l10n, 1133080512), '1.1 GB');
      expect(modelSize(l10n, 64000000000), '64 GB');
      final bangla = await AppLocalizations.delegate.load(const Locale('bn'));
      expect(modelSize(bangla, 399237419), '৩৯৯ MB');
    });
  });

  testWidgets('FR-M4 the artboard: the phone\'s storage, the voice ready with '
      'its voices, the translation model 42 % in', (tester) async {
    await pump(tester, modelManagerStub());
    expect(
      find.text(l10n.modelsStorageFree('12.4 GB', '64 GB')),
      findsOneWidget,
    );
    // 399 MB of voice and 42 % of 1.1 GB.
    expect(
      find.text(l10n.modelsStorageModels('875 MB', '64 GB')),
      findsOneWidget,
    );

    expect(find.text(l10n.modelsStatusReady), findsOneWidget);
    for (final voice in <String>['Anna', 'Jonas', 'Lena']) {
      expect(find.text(voice), findsOneWidget);
    }
    expect(find.text(l10n.modelsDelete('399 MB')), findsOneWidget);
    expect(find.text(l10n.modelsCheckUpdate), findsOneWidget);

    expect(find.text(l10n.modelsStatusDownloading), findsOneWidget);
    expect(find.text(l10n.modelsProgress(42)), findsOneWidget);
    expect(
      find.text(l10n.modelsProgressBytesWifi('476 MB', '1.1 GB')),
      findsOneWidget,
    );
    expect(find.text(l10n.modelsWifiOnly), findsOneWidget);
    expect(find.text(l10n.modelsPause), findsOneWidget);
    expect(find.text(l10n.modelsFooter), findsOneWidget);
  });

  testWidgets('#314 at 200 % text nothing on M4 is cut', (tester) async {
    textAt(tester, 2);
    await pump(tester, modelManagerStub());
    expectNothingClipped(tester, within: find.byType(ModelManagerScreen));
  });

  group('FR-M4-01 a download, as the learner moves it', () {
    testWidgets('Pause pauses the model\'s own files', (tester) async {
      final downloads = FakeDownloads();
      await pump(tester, modelManagerStub(downloads: downloads));
      await tester.tap(find.text(l10n.modelsPause));
      await tester.pumpAndSettle();
      expect(downloads.calls, <String>['pause hymt']);
    });

    testWidgets('a paused one resumes, and one waiting for Wi-Fi says so', (
      tester,
    ) async {
      final downloads = FakeDownloads();
      await pump(
        tester,
        modelManagerStub(
          downloads: downloads,
          translation: cardOf(
            translationEntry,
            installed: ModelStatus.downloading,
            live: (phase: DownloadPhase.paused, progress: 0.42),
          ),
          voice: cardOf(
            voiceEntry,
            installed: ModelStatus.downloading,
            live: (phase: DownloadPhase.waitingForWifi, progress: 0.1),
          ),
        ),
      );
      expect(find.text(l10n.modelsProgressPaused(42)), findsOneWidget);
      expect(find.text(l10n.modelsProgressWaiting), findsOneWidget);
      expect(find.text(l10n.modelsStatusPaused), findsNWidgets(2));
      await tester.tap(find.text(l10n.modelsResume));
      await tester.pumpAndSettle();
      expect(downloads.calls, <String>['resume hymt']);
    });

    testWidgets('a failed one says why, and Retry fetches it again', (
      tester,
    ) async {
      final downloads = FakeDownloads();
      await pump(
        tester,
        modelManagerStub(
          downloads: downloads,
          voice: cardOf(voiceEntry, installed: ModelStatus.failed),
        ),
      );
      expect(find.text(l10n.modelsStatusFailed), findsOneWidget);
      expect(find.text(l10n.modelsFailedNote), findsOneWidget);
      await tester.tap(find.text(l10n.retry));
      await tester.pumpAndSettle();
      expect(downloads.calls, <String>['retry supertonic3']);
    });

    testWidgets('the Wi-Fi only switch goes through the manager, which keeps '
        'the setting and the downloader\'s rule', (tester) async {
      final downloads = FakeDownloads();
      await pump(tester, modelManagerStub(downloads: downloads));
      await tester.tap(find.bySemanticsLabel(l10n.modelsWifiOnly).last);
      await tester.pumpAndSettle();
      expect(downloads.calls, <String>['wifi false']);
    });

    testWidgets('a download that cannot start says so', (tester) async {
      final downloads = FakeDownloads()..startFails = StateError('no');
      await pump(
        tester,
        modelManagerStub(downloads: downloads, voice: cardOf(voiceEntry)),
      );
      await tester.tap(find.text(l10n.modelsDownload('399 MB')));
      await tester.pump();
      expect(find.text(l10n.modelsStartFailed), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });
  });

  testWidgets('FR-M4-02 an update available offers it, and Update downloads '
      'the new build', (tester) async {
    final downloads = FakeDownloads();
    await pump(
      tester,
      modelManagerStub(
        downloads: downloads,
        voice: cardOf(voiceEntry, installed: ModelStatus.updateAvailable),
      ),
    );
    expect(find.text(l10n.modelsStatusUpdate), findsOneWidget);
    await tester.tap(find.text(l10n.modelsUpdate('399 MB')));
    await tester.pumpAndSettle();
    expect(downloads.calls, <String>['start supertonic3']);
  });

  testWidgets('FR-M4-02 Check for update on a current model says so', (
    tester,
  ) async {
    await pump(tester, modelManagerStub());
    await tester.tap(find.text(l10n.modelsCheckUpdate));
    await tester.pump();
    await tester.pump();
    expect(find.text(l10n.modelsUpToDate), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });

  group('FR-M4-03 Delete', () {
    testWidgets('asks first, and Keep keeps it', (tester) async {
      final models = FakeModels();
      await pump(tester, modelManagerStub(models: models));
      await tester.tap(find.text(l10n.modelsDelete('399 MB')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.modelsDeleteVoiceBody), findsOneWidget);
      await tester.tap(find.text(l10n.modelsDeleteKeep));
      await tester.pumpAndSettle();
      expect(models.deleted, isEmpty);
    });

    testWidgets('then deletes the model, which turns off what used it', (
      tester,
    ) async {
      final models = FakeModels();
      await pump(tester, modelManagerStub(models: models));
      await tester.tap(find.text(l10n.modelsDelete('399 MB')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.modelsDeleteConfirm));
      await tester.pumpAndSettle();
      expect(models.deleted, <String>['supertonic3']);
    });
  });

  group('FR-M4-04 Hy-MT behind its licence', () {
    test("each model's licence is the one M8 bundles for it, by name", () {
      expect(licenceFor(ModelRepository.voiceModel)?.kind, 'OpenRAIL-M');
      expect(
        licenceFor(ModelRepository.translationModel)?.kind,
        'Tencent HY Community License',
      );
      expect(licenceFor('nothing'), isNull);
    });

    testWidgets('without ENABLE_HYMT_DOWNLOAD its download is off, and says '
        'why; the voice\'s is on', (tester) async {
      final downloads = FakeDownloads();
      await pump(
        tester,
        modelManagerStub(
          downloads: downloads,
          voice: cardOf(voiceEntry),
          translation: cardOf(translationEntry),
        ),
      );
      expect(enableHymtDownload, isFalse, reason: 'off by default');
      expect(find.text(l10n.modelsHymtGated), findsOneWidget);
      expect(button(tester, l10n.modelsDownload('1.1 GB')).onPressed, isNull);
      await tester.tap(find.text(l10n.modelsDownload('399 MB')));
      await tester.pumpAndSettle();
      expect(downloads.calls, <String>['start supertonic3']);
    });

    testWidgets('its licence link opens the licence\'s full text', (
      tester,
    ) async {
      await pump(tester, modelManagerStub());
      await tester.tap(
        find.bySemanticsLabel(
          l10n.modelsLicenceRead('Tencent HY Community License'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tencent HY Community License'), findsOneWidget);
    });
  });

  testWidgets('FR-M4 not enough space: the download is disabled, and the note '
      'says by how much', (tester) async {
    await pump(
      tester,
      modelManagerStub(
        translation: cardOf(translationEntry, shortfall: 1400000000),
      ),
    );
    expect(find.text(l10n.modelsStatusNoSpace), findsOneWidget);
    expect(find.text(l10n.modelsNoSpaceNote('1.4 GB')), findsOneWidget);
    expect(button(tester, l10n.modelsDownload('1.1 GB')).onPressed, isNull);
  });

  testWidgets('FR-M4-05 a voice chip chooses the voice, and Supertonic with '
      'it, and plays its sample in it', (tester) async {
    final settings = StubSettings()
      // After a delete (FR-M4-03): the phone's voice.
      ..put(SettingKeys.ttsEngine, TtsEngineSetting.system);
    final voice = FakeTts();
    await pump(tester, modelManagerStub(settings: settings, supertonic: voice));
    await tester.tap(find.text('Jonas'));
    await tester.pumpAndSettle();
    expect(settings.read(SettingKeys.ttsVoice), 'Jonas');
    expect(
      settings.read(SettingKeys.ttsEngine),
      TtsEngineSetting.supertonic,
      reason: "M3 reads 'Supertonic · Jonas' again",
    );
    await tester.tap(find.text('Anna'));
    await tester.pumpAndSettle();
    expect(voice.spoken, <String>[
      'Guten Tag! Ich bin Jonas.',
      'Guten Tag! Ich bin Anna.',
    ]);
    expect(settings.read(SettingKeys.ttsVoice), 'Anna');
  });

  group('the card, from the phone and the download manager', () {
    late FakeDownloads downloads;
    late ProviderContainer container;
    late _Models models;
    StorageSpace? space;

    setUp(() {
      downloads = FakeDownloads();
      models = _Models();
      space = (free: 12400000000, total: 64000000000);
      container = ProviderContainer(
        overrides: <Override>[
          modelRepositoryProvider.overrideWithValue(models),
          modelDownloadsProvider.overrideWithValue(downloads),
          deviceStorageProvider.overrideWithValue(_Storage(() => space)),
        ],
      );
      addTearDown(container.dispose);
    });

    Future<List<ModelCard>> cards(Future<void> Function() moves) async {
      final seen = <ModelCard>[];
      final sub = container.listen(
        modelCardProvider(ModelRepository.voiceModel),
        (_, next) {
          if (next.value case final card?) seen.add(card);
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);
      await pumpEventQueue();
      await moves();
      await pumpEventQueue();
      return seen;
    }

    test(
      'a model not on the phone, and whether the phone has room for it',
      () async {
        var seen = await cards(() async {});
        expect(seen.last.installed.status, ModelStatus.notDownloaded);
        expect(seen.last.shortfall, 0);

        space = (free: 100000000, total: 64000000000);
        container.invalidate(modelCardProvider(ModelRepository.voiceModel));
        seen = await cards(() async {});
        expect(seen.last.shortfall, 399237419 - 100000000);
      },
    );

    test(
      'its download as it moves, and once done, what it installed',
      () async {
        final seen = await cards(() async {
          downloads.live[ModelRepository.voiceModel]!.add((
            phase: DownloadPhase.running,
            progress: 0.3,
          ));
          await pumpEventQueue();
          models.status = ModelStatus.ready;
          downloads.live[ModelRepository.voiceModel]!.add((
            phase: DownloadPhase.ready,
            progress: 1,
          ));
        });
        expect(
          seen.map((card) => (card.live?.phase, card.installed.status)),
          <(DownloadPhase?, ModelStatus)>[
            (null, ModelStatus.notDownloaded),
            (DownloadPhase.running, ModelStatus.notDownloaded),
            (null, ModelStatus.ready),
          ],
        );
      },
    );
  });
}

/// The model files: the manifest's voice, in whatever [status] the test sets.
class _Models extends FakeModels {
  ModelStatus status = ModelStatus.notDownloaded;

  @override
  Future<ModelManifest> manifest() async =>
      ModelManifest(version: 1, models: <ModelEntry>[voiceEntry]);

  @override
  Future<ModelState> stateOf(ModelEntry entry, ModelVariant variant) async =>
      ModelState(entry: entry, variant: variant, status: status);
}

class _Storage extends Fake implements DeviceStorage {
  _Storage(this._space);

  final StorageSpace? Function() _space;

  @override
  Future<StorageSpace?> space() async => _space();
}
