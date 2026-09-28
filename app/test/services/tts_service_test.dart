import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/main.dart' show watchVoiceMemory;
import 'package:sogda/services/tts/tts_engine.dart';
import 'package:sogda/services/tts/tts_service.dart';

import 'fake_tts.dart';

/// `tts.md`'s TtsService (V03, #153): the engine from `tts_engine`, the
/// fallback to the phone's voice with its one-time notice, one player, the
/// state the speakers draw from, and the speed.
///
/// testWidgets for its fake clock: the 150 ms before the loading indicator.
void main() {
  late SettingsRepository settings;
  late FakeTts phone;
  late FakeTts supertonic;
  late List<TtsPlayback> seen;

  setUp(() async {
    final db = AppDatabase.memory();
    settings = SettingsRepository(db);
    await settings.load();
    addTearDown(() async {
      await settings.dispose();
      await db.close();
    });
    phone = FakeTts(holds: true);
    supertonic = FakeTts(holds: true);
  });

  TtsService service({bool installed = true}) {
    final tts = TtsService(
      phone,
      settings,
      supertonic: installed ? supertonic : null,
    );
    seen = <TtsPlayback>[];
    tts.playback.listen(seen.add);
    addTearDown(tts.dispose);
    return tts;
  }

  Future<void> choose(WidgetTester tester, TtsEngineSetting engine) =>
      tester.runAsync(() => settings.write(SettingKeys.ttsEngine, engine));

  List<(String, TtsState)> states() => <(String, TtsState)>[
    for (final playback in seen) (playback.text, playback.state),
  ];

  group('V03 the engine from tts_engine', () {
    testWidgets('supertonic, installed: it speaks, and the phone does not', (
      tester,
    ) async {
      final tts = service();
      expect(await tts.speak('Hallo'), TtsOutcome.spoke);
      expect(supertonic.spoken, <String>['Hallo']);
      expect(phone.spoken, isEmpty);
    });

    testWidgets('system: the phone speaks, Supertonic is not asked, and '
        'there is nothing to tell', (tester) async {
      await choose(tester, TtsEngineSetting.system);
      final tts = service();
      expect(await tts.speak('Hallo'), TtsOutcome.spoke);
      expect(phone.spoken, <String>['Hallo']);
      expect(supertonic.spoken, isEmpty);
    });
  });

  group('#430 clips made ahead', () {
    testWidgets('Supertonic chosen: the service hands it the texts, at '
        'tts_speed', (tester) async {
      final prefetch = FakePrefetchTts();
      await tester.runAsync(() => settings.write(SettingKeys.ttsSpeed, 1.25));
      final tts = TtsService(phone, settings, supertonic: prefetch);
      addTearDown(tts.dispose);
      await tts.prepare(<String>['das Haus', 'die Tür']);
      expect(prefetch.prepared, <List<String>>[
        <String>['das Haus', 'die Tür'],
      ]);
      expect(prefetch.speeds, <double>[1.25]);
    });

    testWidgets("the phone's voice chosen: nothing is made, and a list's "
        'stop still reaches Supertonic', (tester) async {
      await choose(tester, TtsEngineSetting.system);
      final prefetch = FakePrefetchTts();
      final tts = TtsService(phone, settings, supertonic: prefetch);
      addTearDown(tts.dispose);
      await tts.prepare(<String>['das Haus']);
      expect(prefetch.prepared, isEmpty);
      final list = <String>['die Tür'];
      await tts.stopPreparing(list);
      expect(prefetch.stopped.single, same(list));
    });

    testWidgets('#638 release reaches Supertonic whichever voice is chosen '
        'now', (tester) async {
      final prefetch = FakePrefetchTts();
      final tts = TtsService(phone, settings, supertonic: prefetch);
      addTearDown(tts.dispose);
      await tts.release();
      expect(prefetch.releases, 1);

      await choose(tester, TtsEngineSetting.system);
      await tts.release();
      expect(prefetch.releases, 2, reason: 'what it opened is still open');
    });

    testWidgets('#638 VoiceRelease: memory pressure and the background let go '
        'of the sessions, a pause on the way there does not', (tester) async {
      final prefetch = FakePrefetchTts();
      final tts = TtsService(phone, settings, supertonic: prefetch);
      addTearDown(tts.dispose);
      final observer = VoiceRelease(tts.release);
      tester.binding.addObserver(observer);
      addTearDown(() => tester.binding.removeObserver(observer));

      tester.binding.handleMemoryPressure();
      await tester.pump();
      expect(prefetch.releases, 1);

      for (final state in <AppLifecycleState>[
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
      ]) {
        observer.didChangeAppLifecycleState(state);
      }
      await tester.pump();
      expect(prefetch.releases, 1);

      observer.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump();
      expect(prefetch.releases, 2);
    });

    testWidgets('#906 watchVoiceMemory: a voice no screen has built is not '
        'built to release nothing; a built one is released', (tester) async {
      final prefetch = FakePrefetchTts();
      final container = ProviderContainer(
        overrides: <Override>[
          settingsProvider.overrideWithValue(settings),
          fakeVoice(prefetch),
        ],
      );
      addTearDown(container.dispose);
      final observer = watchVoiceMemory(container);
      addTearDown(() => tester.binding.removeObserver(observer));

      tester.binding.handleMemoryPressure();
      await tester.pump();
      expect(container.exists(ttsProvider), isFalse);

      container.read(ttsProvider);
      tester.binding.handleMemoryPressure();
      await tester.pump();
      expect(prefetch.releases, 1);
    });

    testWidgets('#1035 watchVoiceMemory: a voice only M4 played, through the '
        'engine itself, is released in the background and under memory '
        'pressure too', (tester) async {
      final prefetch = FakePrefetchTts();
      final container = ProviderContainer(
        overrides: <Override>[
          settingsProvider.overrideWithValue(settings),
          supertonicTtsProvider.overrideWithValue(prefetch),
        ],
      );
      addTearDown(container.dispose);
      final observer = watchVoiceMemory(container);
      addTearDown(() => tester.binding.removeObserver(observer));

      // M4's voice chips: the engine, no speaker's service.
      container.read(supertonicTtsProvider);
      observer.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump();
      expect(prefetch.releases, 1);

      tester.binding.handleMemoryPressure();
      await tester.pump();
      expect(prefetch.releases, 2);
      expect(
        container.exists(ttsProvider),
        isFalse,
        reason: 'no service built to release nothing (#906)',
      );
    });

    test('#906 the app watches the voice from its start', () {
      final main = File('lib/main.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      final wire = main.substring(main.indexOf('void wireApp('));
      expect(
        wire.substring(0, wire.indexOf('\n}\n')),
        contains('watchVoiceMemory(container);'),
      );
    });

    testWidgets('an engine that cannot prepare is left alone', (tester) async {
      final tts = service();
      await tts.prepare(<String>['das Haus']);
      expect(supertonic.spoken, isEmpty, reason: 'prepare never speaks');
    });
  });

  group('V03 the fallback to the phone voice, told once a session', () {
    testWidgets('Supertonic missing: the phone speaks; the first time says '
        'so, the next does not', (tester) async {
      final tts = service(installed: false);
      expect(await tts.speak('Hallo'), TtsOutcome.fellBack);
      tts.toldFallback();
      expect(await tts.speak('Tschüss'), TtsOutcome.spoke);
      expect(phone.spoken, <String>['Hallo', 'Tschüss']);
    });

    testWidgets('a notice that could not be shown is not spent', (
      tester,
    ) async {
      final tts = service(installed: false);
      expect(await tts.speak('Hallo'), TtsOutcome.fellBack);
      expect(await tts.speak('Hallo'), TtsOutcome.fellBack);
    });

    testWidgets('Supertonic answering false: the phone speaks that request, '
        'and Supertonic is stopped', (tester) async {
      supertonic.voice = false;
      final tts = service();
      expect(await tts.speak('Hallo'), TtsOutcome.fellBack);
      expect(supertonic.log, <String>['speak Hallo', 'stop']);
      expect(phone.spoken, <String>['Hallo']);
    });

    testWidgets('Supertonic throwing: the same, and still once', (
      tester,
    ) async {
      supertonic.error = StateError('onnx');
      final tts = service();
      expect(await tts.speak('Hallo'), TtsOutcome.fellBack);
      tts.toldFallback();
      expect(await tts.speak('Tschüss'), TtsOutcome.spoke);
      expect(phone.spoken, <String>['Hallo', 'Tschüss']);
      expect(supertonic.spoken, <String>['Hallo', 'Tschüss']);
    });

    testWidgets('no voice at all: silent, and the notice is kept for when '
        'the phone can speak', (tester) async {
      final tts = service(installed: false);
      phone.voice = false;
      expect(await tts.speak('Hallo'), TtsOutcome.silent);
      phone.voice = true;
      expect(await tts.speak('Hallo'), TtsOutcome.fellBack);
    });

    testWidgets('isAvailable: the chosen voice, or the phone behind it', (
      tester,
    ) async {
      final tts = service();
      phone.voice = false;
      expect(await tts.isAvailable(), isTrue, reason: 'Supertonic can');
      supertonic.voice = false;
      expect(await tts.isAvailable(), isFalse);
      phone.voice = true;
      expect(await tts.isAvailable(), isTrue, reason: 'the phone can');
      await choose(tester, TtsEngineSetting.system);
      supertonic.voice = true;
      phone.voice = false;
      expect(await tts.isAvailable(), isFalse, reason: 'not chosen');
    });
  });

  testWidgets('V03 one player: a second request stops the first, then '
      'speaks', (tester) async {
    await choose(tester, TtsEngineSetting.system);
    final tts = service();
    await tts.speak('Hallo');
    await tts.speak('Tschüss');
    expect(phone.log, <String>['speak Hallo', 'stop', 'speak Tschüss']);
    expect(states().last, ('Tschüss', TtsState.playing));
  });

  testWidgets('V03 a request replaced mid-synthesis leaves the player to '
      'the newer one', (tester) async {
    supertonic
      ..voice = false
      ..synthesis = Completer<void>();
    final tts = service();
    final first = tts.speak('Hallo');
    await tester.pump();
    final second = tts.speak('Tschüss');
    await tester.pump();
    supertonic.synthesis!.complete();
    expect(await first, TtsOutcome.spoke, reason: 'nothing to report');
    expect(await second, TtsOutcome.fellBack);
    expect(supertonic.log, <String>[
      'speak Hallo',
      'stop',
      'speak Tschüss',
      'stop',
    ]);
    expect(phone.spoken, <String>['Tschüss']);
  });

  testWidgets('V03 dispose retires a request in flight: no speech, no '
      'timer, no listener after it', (tester) async {
    await choose(tester, TtsEngineSetting.system);
    final tts = service();
    await tts.speak('Hallo');
    final late = tts.speak('Tschüss');
    tts.dispose();
    expect(await late, TtsOutcome.spoke, reason: 'nothing to report');
    expect(phone.log, <String>['speak Hallo', 'stop']);
  });

  testWidgets('V03 playback: playing for its text while it sounds, then '
      'idle; no loading under 150 ms', (tester) async {
    final tts = service();
    await tts.speak('Hallo');
    expect(states(), <(String, TtsState)>[('Hallo', TtsState.playing)]);
    supertonic.finish();
    await tester.pump();
    expect(states().last, ('', TtsState.idle));
    await tester.pump(const Duration(seconds: 1));
    expect(
      states().map((s) => s.$2),
      isNot(contains(TtsState.loading)),
      reason: 'the timer died with the request',
    );
  });

  testWidgets('V03 synthesis past 150 ms shows loading, and not before', (
    tester,
  ) async {
    final tts = service();
    supertonic.synthesis = Completer<void>();
    unawaited(tts.speak('Hallo'));
    await tester.pump(const Duration(milliseconds: 149));
    expect(states().map((s) => s.$2), isNot(contains(TtsState.loading)));
    await tester.pump(const Duration(milliseconds: 2));
    expect(states().last, ('Hallo', TtsState.loading));
    supertonic.synthesis!.complete();
    await tester.pump();
    expect(states().last, ('Hallo', TtsState.playing));
  });

  testWidgets('V03 a voice that reports nothing leaves no spinner behind', (
    tester,
  ) async {
    phone = FakeTts();
    await choose(tester, TtsEngineSetting.system);
    final tts = service();
    phone.synthesis = Completer<void>();
    unawaited(tts.speak('Hallo'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(states().last, ('Hallo', TtsState.loading));
    phone.synthesis!.complete();
    await tester.pump();
    expect(states().last, ('', TtsState.idle));
  });

  testWidgets('V03 FR-T2-09 tts_speed reaches the engine, and a long-press '
      'pace is 0.75× of it', (tester) async {
    await tester.runAsync(() => settings.write(SettingKeys.ttsSpeed, 1.25));
    final tts = service();
    await tts.speak('Hallo');
    await tts.speak('Hallo', pace: 0.75);
    expect(supertonic.said, <(String, double)>[
      ('Hallo', 1.25),
      ('Hallo', 0.9375),
    ]);
  });
}
