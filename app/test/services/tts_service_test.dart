import 'dart:async';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/services/tts/tts_engine.dart';
import 'package:deutschplan/services/tts/tts_service.dart';
import 'package:flutter_test/flutter_test.dart';

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
