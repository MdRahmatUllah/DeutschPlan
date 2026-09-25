import 'package:deutschplan/services/device_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// M4's storage card and its space check (#156): the platform's answer, and
/// the shortfall a disabled download button states.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('deutschplan/storage');

  void answer(Object? Function(MethodCall call) reply) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => reply(call));
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
  }

  test('FR-M4-01 the free and total bytes the phone reports', () async {
    answer((call) {
      expect(call.method, 'space');
      return <String, Object?>{'free': 12400000000, 'total': 64000000000};
    });
    expect(await const PlatformDeviceStorage().space(), (
      free: 12400000000,
      total: 64000000000,
    ));
  });

  test('nothing, rather than a guess, when the phone does not say', () async {
    answer((call) => throw PlatformException(code: 'io'));
    expect(await const PlatformDeviceStorage().space(), isNull);
    answer((call) => <String, Object?>{'free': 5});
    expect(await const PlatformDeviceStorage().space(), isNull);
  });

  test('FR-M4-01 the shortfall: what the download lacks, and 0 when it fits '
      'or the phone will not say', () {
    const space = (free: 300, total: 1000);
    expect(shortfall(needed: 440, space: space), 140);
    expect(shortfall(needed: 300, space: space), 0);
    expect(shortfall(needed: 440, space: null), 0);
  });
}
