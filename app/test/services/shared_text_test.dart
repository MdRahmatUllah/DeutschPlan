import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/services/shared_text.dart';

/// "Share → Sogda" over `sogda/share` (#1227, #1228, #1332): what
/// `MainActivity` answers, as D1 reads it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sogda/share');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void answer(Object? Function(String method) reply) => messenger
      .setMockMethodCallHandler(channel, (call) async => reply(call.method));

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('#1332 FR-D1-01 shared photos come as their copies, in order, and '
      'how many were shared', () async {
    answer(
      (method) => method == 'takeImages'
          ? <String, Object>{
              'pages': <String>['/c/shared/01-a.jpg', '/c/shared/02-b.jpg'],
              'of': 34,
            }
          : null,
    );
    final images = await const PlatformSharedText().takeImages();
    expect(images?.pages, <String>['/c/shared/01-a.jpg', '/c/shared/02-b.jpg']);
    expect(images?.of, 34);
  });

  test(
    '#1332 no photos, or an answer this build does not know, is none',
    () async {
      for (final reply in <Object?>[
        null,
        'x.jpg',
        <String, Object>{'of': 1},
      ]) {
        answer((_) => reply);
        expect(await const PlatformSharedText().takeImages(), isNull);
      }
      answer((_) => throw PlatformException(code: 'gone'));
      expect(await const PlatformSharedText().takeImages(), isNull);
    },
  );

  test('#1227 #1228 the text and the PDF still come as text', () async {
    answer((method) => '$method!');
    expect(await const PlatformSharedText().take(), 'take!');
    expect(await const PlatformSharedText().takePdf(), 'takePdf!');
  });
}
