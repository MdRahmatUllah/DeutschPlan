import 'dart:io';

import 'package:deutschplan/core/adaptive/orientation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// #577, the owner's call: a phone stays portrait, a tablet turns.
void main() {
  test('#577 a phone stays portrait however it is held; from a 600 dp '
      'shortest side, a tablet turns', () {
    const portrait = <DeviceOrientation>[DeviceOrientation.portraitUp];
    expect(orientationsFor(const Size(390, 844)), portrait);
    expect(orientationsFor(const Size(844, 390)), portrait, reason: 'held so');
    expect(orientationsFor(const Size(360, 640)), portrait);
    expect(orientationsFor(const Size(599, 960)), portrait);
    expect(orientationsFor(const Size(600, 960)), isEmpty, reason: 'every one');
    expect(orientationsFor(const Size(1024, 768)), isEmpty);
  });

  testWidgets('#577 lockOrientation asks the platform for the view it runs '
      'in', (tester) async {
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
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    await lockOrientation(tester.view);
    tester.view.physicalSize = const Size(1024, 768) * 2;
    tester.view.devicePixelRatio = 2;
    await lockOrientation(tester.view);

    expect(asked, <Object?>[
      <String>['DeviceOrientation.portraitUp'],
      <String>[],
    ]);
  });

  test('#577 the app sets it at start', () {
    expect(
      File('lib/main.dart').readAsStringSync(),
      contains('await lockOrientation('),
    );
  });
}
