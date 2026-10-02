import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/services/pdf_text.dart';

/// A PDF of [texts], one per page, as the platform would read it.
class _FakePdf implements PdfText {
  _FakePdf(this.texts, {this.failAt});

  final List<String> texts;
  final int? failAt;
  final List<int> asked = <int>[];
  final List<int> closed = <int>[];

  @override
  Future<String?> choose() async => '/picked.pdf';

  @override
  Future<({int handle, int pages})> open(String source) async =>
      (handle: 7, pages: texts.length);

  @override
  Future<String> page(int handle, int page) async {
    asked.add(page);
    if (page == failAt) throw const PdfUnreadable('broken page');
    return texts[page - 1];
  }

  @override
  Future<void> close(int handle) async => closed.add(handle);

  @override
  Future<void> discard(String path) async {}
}

const String _letter =
    'Sehr geehrte Frau Okafor, Ihre Nebenkostenabrechnung liegt bei.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('#1228 FR-D1-01 BR-DOC-02 readPdf', () {
    test('reads every page in order, says which, and closes', () async {
      final pdf = _FakePdf(<String>[_letter, _letter, _letter]);
      final progress = <(int, int)>[];
      final read = await readPdf(
        pdf,
        'content://x',
        onPage: (page, of) => progress.add((page, of)),
      );

      expect(read!.pages, hasLength(3));
      expect(read.pageCount, 3);
      expect(read.scan, isFalse);
      expect(progress, <(int, int)>[(1, 3), (2, 3), (3, 3)]);
      expect(pdf.closed, <int>[7]);
    });

    test('reads the first 30 pages of a longer one, and says how long it '
        'is', () async {
      final pdf = _FakePdf(List<String>.filled(45, _letter));
      final read = await readPdf(pdf, '/x.pdf');

      expect(read!.pages, hasLength(maxPdfPages));
      expect(read.pageCount, 45);
      expect(pdf.asked.last, 30);
    });

    test('says how many pages it has as soon as it is open, before a page is '
        'read', () async {
      final pdf = _FakePdf(List<String>.filled(45, _letter));
      int? told;
      int? readWhenTold;
      await readPdf(
        pdf,
        '/x.pdf',
        onOpen: (pages) {
          told = pages;
          readWhenTold = pdf.asked.length;
        },
      );
      expect(told, 45);
      expect(readWhenTold, 0);
    });

    test('a scan, no page with a text layer, says so; one page of text is '
        'enough not to be', () async {
      final scan = await readPdf(
        // A scan's text layer, when it has one, is a few characters at most.
        _FakePdf(<String>['', '  \n', 'Seite 3']),
        '/scan.pdf',
      );
      expect(scan!.scan, isTrue);

      final mixed = await readPdf(_FakePdf(<String>['', _letter]), '/m.pdf');
      expect(mixed!.scan, isFalse);
    });

    test('FR-D1-05 Cancel between two pages reads no more, answers null and '
        'closes', () async {
      final pdf = _FakePdf(<String>[_letter, _letter, _letter]);
      final read = await readPdf(
        pdf,
        '/x.pdf',
        cancelled: () => pdf.asked.length == 1,
      );

      expect(read, isNull);
      expect(pdf.asked, <int>[1]);
      expect(pdf.closed, <int>[7]);
    });

    test('a page that fails closes the document too', () async {
      final pdf = _FakePdf(<String>[_letter, _letter], failAt: 2);

      await expectLater(readPdf(pdf, '/x.pdf'), throwsA(isA<PdfUnreadable>()));
      expect(pdf.closed, <int>[7]);
    });
  });

  group('#1228 PlatformPdfText over sogda/pdf', () {
    const channel = MethodChannel('sogda/pdf');
    final calls = <MethodCall>[];
    Object? Function(MethodCall call)? answer;

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return answer!(call);
          });
    });

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    test(
      'opens, reads a page and closes with the platform\'s arguments',
      () async {
        answer = (call) => switch (call.method) {
          'open' => <String, Object>{'handle': 3, 'pages': 2},
          'page' => 'Seite eins',
          _ => null,
        };
        const pdf = PlatformPdfText();

        final opened = await pdf.open('content://doc/1');
        expect((opened.handle, opened.pages), (3, 2));
        expect(await pdf.page(3, 1), 'Seite eins');
        await pdf.close(3);

        expect(
          <Object?>[for (final call in calls) call.method],
          <String>['open', 'page', 'close'],
        );
        expect(calls[0].arguments, <String, Object>{
          'source': 'content://doc/1',
        });
        expect(calls[1].arguments, <String, Object>{'handle': 3, 'page': 1});
      },
    );

    test('BR-DOC-05 discard deletes the copy D1 read, and a second one is '
        'nothing', () async {
      final folder = Directory.systemTemp.createTempSync('pdf_copy');
      addTearDown(() => folder.deleteSync(recursive: true));
      final copy = File('${folder.path}/Brief.pdf')..writeAsStringSync('%PDF');
      const pdf = PlatformPdfText();

      await pdf.discard(copy.path);
      expect(copy.existsSync(), isFalse);
      await pdf.discard(copy.path);
    });

    test('a password is PdfLocked; anything else, PdfUnreadable', () async {
      const pdf = PlatformPdfText();
      answer = (call) =>
          throw PlatformException(code: 'password', message: 'needs one');
      await expectLater(pdf.open('/locked.pdf'), throwsA(isA<PdfLocked>()));

      answer = (call) =>
          throw PlatformException(code: 'unreadable', message: 'not a PDF');
      await expectLater(pdf.open('/x.txt'), throwsA(isA<PdfUnreadable>()));
    });
  });
}
