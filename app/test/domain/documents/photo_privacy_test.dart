import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/domain/documents/photo_privacy.dart';

/// A segment: its marker, its length, its bytes.
List<int> segment(int marker, List<int> payload) => <int>[
  0xFF,
  marker,
  (payload.length + 2) >> 8,
  (payload.length + 2) & 0xFF,
  ...payload,
];

/// A big-endian EXIF APP1: the camera's make «SQA», orientation [rotation],
/// and a GPS IFD with «N».
List<int> exif({int rotation = 6}) => segment(0xE1, <int>[
  ...ascii.encode('Exif'), 0, 0, //
  0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08, // MM, IFD0 at 8
  0x00, 0x03, // three entries
  0x01, 0x0F, 0x00, 0x02, 0x00, 0x00, 0x00, 0x04, ...ascii.encode('SQA'), 0,
  0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, rotation, 0, 0,
  0x88, 0x25, 0x00, 0x04, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x32,
  0x00, 0x00, 0x00, 0x00, // no next IFD
  // GPS IFD at 50: latitude ref «N».
  0x00, 0x01,
  0x00, 0x01, 0x00, 0x02, 0x00, 0x00, 0x00, 0x02, ...ascii.encode('N'), 0, 0, 0,
  0x00, 0x00, 0x00, 0x00,
]);

/// A small JPEG: JFIF, then [extra] segments, a table, the scan and its end.
Uint8List jpeg([List<int> extra = const <int>[]]) => Uint8List.fromList(<int>[
  0xFF, 0xD8, //
  ...segment(0xE0, <int>[
    ...ascii.encode('JFIF'),
    0,
    1,
    1,
    0,
    0,
    1,
    0,
    1,
    0,
    0,
  ]),
  ...extra,
  ...segment(0xDB, <int>[0, 1, 2, 3]),
  ...segment(0xDA, <int>[1, 1, 0, 0, 63, 0]),
  ...ascii.encode('PIXELS'),
  0xFF, 0xD9,
]);

bool holds(List<int> bytes, String text) => latin1.decode(bytes).contains(text);

/// The orientation in the first EXIF APP1 of [bytes], big-endian as written.
int? orientationOf(List<int> bytes) {
  final at = latin1.decode(bytes).indexOf('Exif');
  if (at < 0) return null;
  final tiff = at + 6;
  final ifd =
      (bytes[tiff + 4] << 24) |
      (bytes[tiff + 5] << 16) |
      (bytes[tiff + 6] << 8) |
      bytes[tiff + 7];
  final count = (bytes[tiff + ifd] << 8) | bytes[tiff + ifd + 1];
  for (var n = 0; n < count; n++) {
    final entry = tiff + ifd + 2 + n * 12;
    if (bytes[entry] == 0x01 && bytes[entry + 1] == 0x12) {
      return (bytes[entry + 8] << 8) | bytes[entry + 9];
    }
  }
  return null;
}

void main() {
  test('#1229 BR-DOC-05 a JPEG loses its EXIF (camera, GPS), its XMP and its '
      'comments, and keeps its orientation, colour profile and pixels', () {
    final photo = jpeg(<int>[
      ...exif(),
      ...segment(0xE1, <int>[
        ...ascii.encode('http://ns.adobe.com/xap/1.0/'),
        0,
        ...ascii.encode('<x:xmpmeta>GPSLatitude 52,31</x:xmpmeta>'),
      ]),
      ...segment(0xFE, ascii.encode('taken at Rahim\'s flat')),
      ...segment(0xED, ascii.encode('Photoshop 3.0 IPTC city Berlin')),
      ...segment(0xE2, <int>[...ascii.encode('ICC_PROFILE'), 0, 1, 1]),
    ]);
    expect(holds(photo, 'SQA'), isTrue, reason: 'the fixture has them');

    final clean = withoutMetadata(photo)!;
    for (final gone in <String>['SQA', 'xmpmeta', 'Rahim', 'Berlin']) {
      expect(holds(clean, gone), isFalse, reason: gone);
    }
    expect(orientationOf(clean), 6, reason: 'pages stay the right way up');
    expect(holds(clean, 'ICC_PROFILE'), isTrue);
    expect(holds(clean, 'JFIF'), isTrue);
    expect(holds(clean, 'PIXELS'), isTrue);
    expect(clean.sublist(clean.length - 2), <int>[0xFF, 0xD9]);
  });

  test('#1229 BR-DOC-05 what follows a JPEG\'s end goes (MPF\'s second '
      'picture, a phone\'s trailer), and so do MPF\'s index and a comment '
      'between a progressive file\'s scans', () {
    final first = jpeg(<int>[
      ...segment(0xE2, <int>[...ascii.encode('MPF'), 0, 0x4D, 0x4D]),
    ]);
    final photo = Uint8List.fromList(<int>[
      ...first.sublist(0, first.length - 2), // the first scan, not its end
      ...segment(0xFE, ascii.encode('between scans: Rahim')),
      ...segment(0xC4, <int>[0x10, 0xFF, 0xD9]), // a table holding FF D9
      ...segment(0xDA, <int>[1, 1, 0, 0, 63, 0]),
      0x12, 0xFF, 0x00, 0x34, 0xFF, 0xD3, ...ascii.encode('MORE'), //
      0xFF, 0xD9,
      ...jpeg(exif()), // MPF's second picture, with the camera's make
      ...ascii.encode('MotionPhoto_Data SEFT'),
    ]);

    final clean = withoutMetadata(photo)!;
    for (final gone in <String>['SQA', 'MPF', 'Rahim', 'SEFT']) {
      expect(holds(clean, gone), isFalse, reason: gone);
    }
    expect(holds(clean, 'PIXELS'), isTrue);
    expect(holds(clean, 'MORE'), isTrue, reason: 'the second scan is whole');
    expect(clean.sublist(clean.length - 2), <int>[0xFF, 0xD9]);
    expect(
      withoutMetadata(first.sublist(0, first.length - 2)),
      isNull,
      reason: 'no end: a broken file',
    );
  });

  test('a JPEG with no EXIF gains none, and a little-endian orientation is '
      'read too', () {
    expect(holds(withoutMetadata(jpeg())!, 'Exif'), isFalse);

    final little = segment(0xE1, <int>[
      ...ascii.encode('Exif'), 0, 0, //
      0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00, // II, IFD0 at 8
      0x01, 0x00,
      0x12, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x03, 0x00, 0, 0,
      0, 0, 0, 0,
    ]);
    expect(orientationOf(withoutMetadata(jpeg(little))!), 3);
  });

  test('a PNG keeps the chunks that draw it, and loses its text, EXIF and '
      'time', () {
    List<int> chunk(String type, List<int> data) => <int>[
      0, 0, data.length >> 8, data.length & 0xFF, //
      ...ascii.encode(type), ...data, 0, 0, 0, 0,
    ];
    final photo = Uint8List.fromList(<int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      ...chunk('IHDR', List<int>.filled(13, 1)),
      ...chunk('tEXt', ascii.encode('Author\u0000Rahim')),
      ...chunk('eXIf', ascii.encode('MM GPS N 52')),
      ...chunk('tIME', <int>[7, 234, 10, 2, 9, 0, 0]),
      ...chunk('IDAT', ascii.encode('PIXELS')),
      ...chunk('IEND', <int>[]),
    ]);
    final clean = withoutMetadata(photo)!;
    for (final gone in <String>['tEXt', 'Rahim', 'eXIf', 'GPS', 'tIME']) {
      expect(holds(clean, gone), isFalse, reason: gone);
    }
    for (final kept in <String>['IHDR', 'IDAT', 'PIXELS', 'IEND']) {
      expect(holds(clean, kept), isTrue, reason: kept);
    }
  });

  test('a format it can\'t clean, or a broken JPEG, gives nothing to keep', () {
    expect(
      withoutMetadata(Uint8List.fromList(ascii.encode('RIFF....WEBP'))),
      isNull,
    );
    expect(
      withoutMetadata(Uint8List.fromList(<int>[0xFF, 0xD8, ...exif()])),
      isNull,
      reason: 'no image data',
    );
  });
}
