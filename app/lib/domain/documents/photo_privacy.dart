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

/// A JPEG's segments, kept or dropped: the JFIF header, the colour profile
/// (APP2's `ICC_PROFILE`) and Adobe's colour transform (APP14) stay, as does
/// everything that draws the picture. EXIF and XMP (APP1), IPTC (APP13),
/// MPF and every other APPn, and the comments go, and so does whatever
/// follows the image's end. A minimal EXIF with the orientation alone goes
/// back in, since the pixels aren't rotated.
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
    // Start of scan: the image data, to the image's end.
    if (marker == 0xDA) {
      putOrientation();
      return _scans(b, at, out) ? out.takeBytes() : null;
    }
    final end = _segmentEnd(b, at);
    if (end == null) return null;
    final segment = Uint8List.sublistView(b, at, end);
    if (marker == 0xE1) {
      orientation ??= _readOrientation(segment);
    } else if (_keeps(segment)) {
      out.add(segment);
      // After JFIF's header, as an EXIF segment usually stands.
      if (marker == 0xE0) putOrientation();
    }
    at = end;
  }
  return null; // no image data
}

/// Just past the segment with its length at [at], or null past the file.
int? _segmentEnd(Uint8List b, int at) {
  if (at + 4 > b.length) return null;
  final length = (b[at + 2] << 8) | b[at + 3];
  final end = at + 2 + length;
  return length < 2 || end > b.length ? null : end;
}

/// The scans from [at] to the image's end (FF D9) into [out]: the image data
/// as it is, and the segments between a progressive file's scans as
/// [_keeps] says. What follows the end goes: MPF's second pictures, a
/// phone's trailer (Samsung's motion photo), each with an EXIF of its own.
/// False when the file ends first.
bool _scans(Uint8List b, int at, BytesBuilder out) {
  var run = at;
  var i = at;
  while (i + 1 < b.length) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    final next = b[i + 1];
    if (next == 0x00 || (next >= 0xD0 && next <= 0xD7)) {
      i += 2; // a stuffed FF, a restart marker: the scan's own
    } else if (next == 0xFF) {
      i++; // fill
    } else if (next == 0xD9) {
      out.add(Uint8List.sublistView(b, run, i + 2));
      return true;
    } else {
      final end = _segmentEnd(b, i);
      if (end == null) return false;
      if (!_keeps(Uint8List.sublistView(b, i, end))) {
        out.add(Uint8List.sublistView(b, run, i));
        run = end;
      }
      i = end;
    }
  }
  return false;
}

bool _keeps(Uint8List segment) {
  final marker = segment[1];
  if (marker == 0xFE) return false; // a comment
  // APP2 is a colour profile, or MPF's index of the pictures after the end.
  if (marker == 0xE2) {
    return segment.length >= 16 &&
        String.fromCharCodes(segment.sublist(4, 16)) == 'ICC_PROFILE\u0000';
  }
  if (marker >= 0xE0 && marker <= 0xEF) {
    return marker == 0xE0 || marker == 0xEE;
  }
  return true; // quantisation, Huffman, frame, scan, restart interval…
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
