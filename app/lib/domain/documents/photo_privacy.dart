/// BR-DOC-05 (#1229): a photo kept with its document keeps no metadata: no
/// GPS, no camera make or model, no time it was taken. Only what the page
/// needs to show the right way up stays: a JPEG's EXIF orientation. Pure:
/// bytes in, bytes out.
library;

import 'dart:typed_data';

/// [bytes] with their metadata gone, or null when the format isn't one this
/// knows (JPEG, PNG): such a photo isn't kept, and its document's text is.
Uint8List? withoutMetadata(Uint8List bytes) {
  if (_isJpeg(bytes)) return _jpeg(bytes);
  if (_isPng(bytes)) return _png(bytes);
  return null;
}

bool _isJpeg(Uint8List b) => b.length > 3 && b[0] == 0xFF && b[1] == 0xD8;

bool _isPng(Uint8List b) =>
    b.length > 8 &&
    b[0] == 0x89 &&
    b[1] == 0x50 &&
    b[2] == 0x4E &&
    b[3] == 0x47;

/// A JPEG's segments up to the image data, kept or dropped: the JFIF header,
/// the colour profile (APP2) and Adobe's colour transform (APP14) stay, as
/// does everything that draws the picture. EXIF and XMP (APP1), IPTC (APP13),
/// every other APPn and the comments go. A minimal EXIF with the orientation
/// alone goes back in, since the pixels aren't rotated.
Uint8List? _jpeg(Uint8List b) {
  final out = BytesBuilder(copy: false)..add(<int>[0xFF, 0xD8]);
  int? orientation;
  var at = 2;
  var wroteOrientation = false;
  void putOrientation() {
    final value = orientation;
    if (wroteOrientation || value == null) return;
    out.add(_orientationExif(value));
    wroteOrientation = true;
  }

  while (at + 4 <= b.length) {
    if (b[at] != 0xFF) return null; // not a segment: a broken file
    final marker = b[at + 1];
    if (marker == 0xFF) {
      at++; // fill byte
      continue;
    }
    // Start of scan: the image data, then the end, kept as they are.
    if (marker == 0xDA) {
      putOrientation();
      out.add(Uint8List.sublistView(b, at));
      return out.takeBytes();
    }
    final length = (b[at + 2] << 8) | b[at + 3];
    final end = at + 2 + length;
    if (length < 2 || end > b.length) return null;
    final segment = Uint8List.sublistView(b, at, end);
    if (marker == 0xE1) {
      orientation ??= _readOrientation(segment);
    } else if (_keeps(marker)) {
      out.add(segment);
      // After JFIF's header, as an EXIF segment usually stands.
      if (marker == 0xE0) putOrientation();
    }
    at = end;
  }
  return null; // no image data
}

bool _keeps(int marker) {
  if (marker == 0xFE) return false; // a comment
  if (marker >= 0xE0 && marker <= 0xEF) {
    return marker == 0xE0 || marker == 0xE2 || marker == 0xEE;
  }
  return true; // quantisation, Huffman, frame, restart interval…
}

/// The EXIF orientation (1–8) in an APP1 segment, or null.
int? _readOrientation(Uint8List segment) {
  // FF E1, length, "Exif\0\0", then TIFF.
  const start = 10;
  if (segment.length < start + 8) return null;
  if (String.fromCharCodes(segment.sublist(4, 8)) != 'Exif') return null;
  final little = segment[start] == 0x49 && segment[start + 1] == 0x49;
  int u16(int i) => little
      ? segment[start + i] | (segment[start + i + 1] << 8)
      : (segment[start + i] << 8) | segment[start + i + 1];
  int u32(int i) =>
      little ? u16(i) | (u16(i + 2) << 16) : (u16(i) << 16) | u16(i + 2);
  final ifd = u32(4);
  if (start + ifd + 2 > segment.length) return null;
  final entries = u16(ifd);
  for (var n = 0; n < entries; n++) {
    final entry = ifd + 2 + n * 12;
    if (start + entry + 12 > segment.length) return null;
    if (u16(entry) == 0x0112) {
      final value = u16(entry + 8);
      return value >= 1 && value <= 8 ? value : null;
    }
  }
  return null;
}

/// APP1 with a TIFF header and one entry: Orientation = [value]. Big-endian.
Uint8List _orientationExif(int value) => Uint8List.fromList(<int>[
  0xFF, 0xE1, 0x00, 0x22, // APP1, 34 bytes after the marker
  0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // "Exif\0\0"
  0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08, // MM, 42, IFD0 at 8
  0x00, 0x01, // one entry
  0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, // Orientation, SHORT, 1
  0x00, value, 0x00, 0x00, // its value
  0x00, 0x00, 0x00, 0x00, // no next IFD
]);

/// A PNG's chunks: only those that draw it (and its colour) stay. Text,
/// EXIF, the time it was made and any other ancillary chunk go.
Uint8List? _png(Uint8List b) {
  const kept = <String>{
    'IHDR', 'PLTE', 'IDAT', 'IEND', 'tRNS', //
    'gAMA', 'cHRM', 'sRGB', 'iCCP', 'sBIT', 'pHYs',
  };
  final out = BytesBuilder(copy: false)..add(Uint8List.sublistView(b, 0, 8));
  var at = 8;
  while (at + 12 <= b.length) {
    final length =
        (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];
    final end = at + 12 + length;
    if (length < 0 || end > b.length) return null;
    final type = String.fromCharCodes(b.sublist(at + 4, at + 8));
    if (kept.contains(type)) out.add(Uint8List.sublistView(b, at, end));
    at = end;
    if (type == 'IEND') return out.takeBytes();
  }
  return null; // no end
}
