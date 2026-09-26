import 'dart:async';
import 'dart:io';

import 'package:deutschplan/bootstrap.dart';
import 'package:deutschplan/core/adaptive/orientation.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/main.dart' show BootstrapHost;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// #577, the owner's call: a phone stays portrait, a tablet turns.
void main() {
  const portrait = <String>['DeviceOrientation.portraitUp'];
  const every = <String>[];

  test('#577 a phone stays portrait however it is held; from a 600 dp '
      'shortest side, a tablet turns', () {
    const up = <DeviceOrientation>[DeviceOrientation.portraitUp];
    expect(orientationsFor(const Size(390, 844)), up);
    expect(orientationsFor(const Size(844, 390)), up, reason: 'held so');
    expect(orientationsFor(const Size(360, 640)), up);
    expect(orientationsFor(const Size(599, 960)), up);
    expect(orientationsFor(const Size(600, 960)), isEmpty, reason: 'every one');
    expect(orientationsFor(const Size(1024, 768)), isEmpty);
  });

  group('#577 OrientationLock', () {
    late List<Object?> asked;

    setUp(() {
      asked = <Object?>[];
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'SystemChrome.setPreferredOrientations') {
              asked.add(call.arguments);
            }
            return null;
          });
    });

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    test('the window before its first size locks nothing: read as a phone, '
        'it locked tablets at start', () async {
      final lock = OrientationLock();
      await lock.update(Size.zero);
      expect(asked, isEmpty);
      await lock.update(const Size(1024, 768));
      expect(asked, <Object?>[every]);
    });

    test('a phone asks once, however often its metrics change', () async {
      final lock = OrientationLock();
      await lock.update(const Size(390, 844));
      await lock.update(const Size(390, 544)); // the keyboard up
      await lock.update(const Size(390, 844));
      expect(asked, <Object?>[portrait]);
    });

    test('a foldable asks again each time it crosses the tablet line: '
        'opened, it turns; closed, its cover screen is portrait', () async {
      final lock = OrientationLock();
      await lock.update(const Size(344, 882)); // folded
      await lock.update(const Size(673, 841)); // opened
      await lock.update(const Size(344, 882)); // folded again
      expect(asked, <Object?>[portrait, every, portrait]);
    });
  });

  testWidgets('#577 the app asks from its window as the size comes and '
      'crosses the tablet line: a tablet turns, then its split-screen half '
      'is portrait', (tester) async {
    final asked = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          asked.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    addTearDown(tester.view.reset);
    tester.view
      ..physicalSize = const Size(1024, 768) * 2
      ..devicePixelRatio = 2;

    final never = Completer<BootstrapResult>();
    await tester.pumpWidget(
      BootstrapHost(
        run: ({
          Brightness platformBrightness = Brightness.light,
          void Function(UiLanguage)? onUiLanguage,
        }) => never.future,
      ),
    );
    await tester.pump();
    expect(asked, <Object?>[every], reason: 'a tablet turns');

    tester.view.physicalSize = const Size(500, 768) * 2;
    await tester.pump();
    expect(asked, <Object?>[every, portrait], reason: 'a half as narrow');
  });

  test('#577 the app decides it from the window as its size comes and goes, '
      'not before runApp', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('with WidgetsBindingObserver'));
    expect(
      RegExp(r'void didChangeMetrics\(\) \{[^}]*_orientation\.update\(')
          .hasMatch(main),
      isTrue,
    );
    expect(main, contains('addObserver(this)'));
  });
}
