import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/services/backup_files.dart';

/// M6's picked file, read with a cap (#657).
void main() {
  test('#657 a file under the cap is read as text', () async {
    final text = await readCapped(
      Stream<List<int>>.fromIterable(<List<int>>[
        utf8.encode('{"schema_'),
        utf8.encode('version": 3}'),
      ]),
      cap: 64,
    );

    expect(text, '{"schema_version": 3}');
  });

  test('#657 a file over it stops at the chunk that passes it, unread past '
      'there', () async {
    var chunks = 0;
    Stream<List<int>> big() async* {
      for (var i = 0; i < 100; i++) {
        chunks++;
        yield List<int>.filled(10, 0x20);
      }
    }

    await expectLater(readCapped(big(), cap: 25), throwsFormatException);
    expect(chunks, 3);
  });
}
