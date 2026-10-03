import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/features/documents/doc_words_screen.dart';

import '../features/doc_words_fixtures.dart';
import 'golden_harness.dart';

/// D2 · The words in your text (#1230): the DocWords, DocWordsCard and
/// DocWordsEmpty artboards (#1222), on the artboard's own letter, matched by
/// the real lemmatiser; plus the long text the spec asks for.
void main() {
  goldenTest(
    'doc_words',
    overrides: docWordsStub(),
    builder: (_) => const DocWordsScreen(id: 7),
  );

  goldenTest(
    'doc_words_card',
    textAudit: false,
    overrides: docWordsStub(),
    builder: (_) => const DocWordsScreen(id: 7),
    act: (tester) async {
      await tester.tapOnText(find.textRange.ofSubstring('Nachzahlung').first);
      await tester.pumpAndSettle();
    },
  );

  // #1233: a word outside the course, with Hy-MT2's meaning, labelled.
  goldenTest(
    'doc_words_card_outside',
    textAudit: false,
    overrides: docWordsStub(
      meanings: const <String, List<({String meaning, bool here})>>{
        'en': <({String meaning, bool here})>[
          (meaning: 'water meter', here: false),
        ],
      },
    ),
    builder: (_) => const DocWordsScreen(id: 7),
    act: (tester) async {
      await tester.tapOnText(find.textRange.ofSubstring('Wasserzähler').first);
      await tester.pumpAndSettle();
    },
  );

  goldenTest(
    'doc_words_empty',
    textAudit: false,
    overrides: docWordsStub(
      documents: FakeDocuments(
        body: 'Ich bin hier.\n\nDas Wetter ist gut.',
        title: 'Kurz',
      ),
    ),
    builder: (_) => const DocWordsScreen(id: 7),
  );

  // #1333's "?" on the ambiguous words («fällt», «verschieben») and #1334's
  // note at a cap of 0: what's added waits.
  goldenTest(
    'doc_words_held',
    devices: const <GoldenDevice>[GoldenDevice.phone],
    overrides: docWordsStub(
      documents: FakeDocuments(
        body:
            'Am Montag fällt der Unterricht aus, und wir müssen den Termin '
            'verschieben. Die Kündigung und die Nebenkosten kommen später.',
        title: 'Elternbrief',
      ),
      plan: FakePlan(slots: 0, capZero: true),
    ),
    builder: (_) => const DocWordsScreen(id: 7),
  );

  // doc-words.md, *A very long text*: its first 20,000 characters, built a
  // paragraph at a time.
  goldenTest(
    'doc_words_long',
    textAudit: false,
    devices: const <GoldenDevice>[GoldenDevice.phone],
    overrides: docWordsStub(
      documents: FakeDocuments(
        body: List<String>.filled(30, artboardLetter).join('\n\n'),
      ),
    ),
    builder: (_) => const DocWordsScreen(id: 7),
  );
}
