import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

/// #1228 (ADR 31): a PDF's text layer, page by page, read on the phone by
/// pdfbox-android (`PdfText.kt`) over `sogda/pdf`. Android only for now: iOS
/// (Later) would answer the same channel from PDFKit.
abstract interface class PdfText {
  /// D1's *Choose a PDF*: the system's file picker, PDFs only; a path, or
  /// null when the learner backs out.
  Future<String?> choose();

  /// Opens [source], a `content:` URI (the picker, a share) or a path: its
  /// handle and how many pages it has. Throws [PdfLocked] for a password,
  /// [PdfUnreadable] for anything else.
  Future<({int handle, int pages})> open(String source);

  /// Page [page]'s text, 1-based.
  Future<String> page(int handle, int page);

  Future<void> close(int handle);
}

/// A PDF that needs a password to open.
class PdfLocked implements Exception {
  const PdfLocked();
}

/// A file that isn't a PDF, or one that's broken.
class PdfUnreadable implements Exception {
  const PdfUnreadable(this.reason);

  final String? reason;

  @override
  String toString() => 'PdfUnreadable: $reason';
}

class PlatformPdfText implements PdfText {
  const PlatformPdfText();

  static const MethodChannel _channel = MethodChannel('sogda/pdf');

  @override
  Future<String?> choose() async => (await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const <String>['pdf'],
  ))?.path;

  @override
  Future<({int handle, int pages})> open(String source) async {
    final opened = await _call<Map<Object?, Object?>>('open', <String, Object>{
      'source': source,
    });
    return (handle: opened!['handle']! as int, pages: opened['pages']! as int);
  }

  @override
  Future<String> page(int handle, int page) async =>
      await _call<String>('page', <String, Object>{
        'handle': handle,
        'page': page,
      }) ??
      '';

  @override
  Future<void> close(int handle) =>
      _call<void>('close', <String, Object>{'handle': handle});

  static Future<T?> _call<T>(String method, Map<String, Object> args) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (error) {
      if (error.code == 'password') throw const PdfLocked();
      throw PdfUnreadable(error.message);
    } on MissingPluginException {
      throw const PdfUnreadable('no PDF reader on this platform');
    }
  }
}

/// BR-DOC-02: a document is at most 30 pages.
const int maxPdfPages = 30;

/// What a PDF gave: its pages' text, the first [maxPdfPages] of them, how
/// many it has, and whether it's a scan (no page with a text layer), which
/// D1 sends to the photo path instead (FR-D1-01).
typedef PdfRead = ({List<String> pages, int pageCount, bool scan});

/// [source]'s text layer, a page at a time: [onOpen] with how many pages it
/// has (D1 says at once when it's over 30), [onPage] before each («Reading
/// page 2 of 4…»), and [cancelled] asked between two pages, which answers
/// null (FR-D1-05). The document is closed however it ends.
Future<PdfRead?> readPdf(
  PdfText pdf,
  String source, {
  void Function(int pages)? onOpen,
  void Function(int page, int of)? onPage,
  bool Function()? cancelled,
}) async {
  final opened = await pdf.open(source);
  onOpen?.call(opened.pages);
  try {
    final count = math.min(opened.pages, maxPdfPages);
    final pages = <String>[];
    for (var n = 1; n <= count; n++) {
      if (cancelled?.call() ?? false) return null;
      onPage?.call(n, count);
      pages.add(await pdf.page(opened.handle, n));
    }
    return (pages: pages, pageCount: opened.pages, scan: !pages.any(_hasText));
  } finally {
    await pdf.close(opened.handle);
  }
}

/// A page with a text layer: some words, not a stray page number or header.
// ponytail: 25 letters, a guess from the fixtures; a scan's text layer, when
// it has one, is empty or a few characters.
bool _hasText(String page) => _letter.allMatches(page).length >= 25;

final RegExp _letter = RegExp(r'\p{L}', unicode: true);
