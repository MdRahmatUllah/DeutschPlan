import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/domain/documents/lemmatiser.dart';
import 'package:sogda/domain/documents/stop_words.dart';
import 'package:sqlite3/sqlite3.dart';

/// The course's words, from the shipped `content.db`, as the data layer will
/// hand them over (`kind` vocab only, BR-CONTENT-04).
List<LemmaEntry> courseEntries() {
  final db = sqlite3.open('assets/db/content.db', mode: OpenMode.readOnly);
  try {
    return <LemmaEntry>[
      for (final row in db.select(
        "SELECT uid, german, pos, article, forms FROM words WHERE kind = 'vocab'",
      ))
        LemmaEntry(
          uid: row['uid'] as String,
          german: row['german'] as String,
          pos: row['pos'] as String,
          article: row['article'] as String?,
          forms: row['forms'] as String?,
        ),
    ];
  } finally {
    db.close();
  }
}

/// A stand-in for #1224's splitter: sentences at an end mark (not a date's
/// «14.») or a line break, words and clause commas as tokens.
List<List<String>> sentencesOf(String text) => <List<String>>[
  for (final sentence in text.split(RegExp(r'(?<=[^0-9][.!?])\s+|\n+')))
    <String>[
      for (final match in RegExp(
        r'\p{L}+(?:-\p{L}+)*|[,;]',
        unicode: true,
      ).allMatches(sentence))
        match[0]!,
    ],
];

/// A reader's lemmas for a text (each `.labels.json`'s `read`), as the
/// course's headwords today, so a content update never leaves the labels
/// stale. «a|b» is the first of them that the course has. Homonyms all
/// count («schon», «schon (Partikel)»); a headword with more to it
/// («abhängen von») only where the course has no bare one.
Set<String> goldOf(List<String> read, List<LemmaEntry> course) {
  final byHead = <String, List<LemmaEntry>>{};
  for (final entry in course) {
    final head = Lemmatiser.headOf(entry);
    if (head != null) byHead.putIfAbsent(head, () => <LemmaEntry>[]).add(entry);
  }
  bool bare(LemmaEntry e) =>
      e.german
          .replaceAll(RegExp(r'\([^)]*\)'), ' ')
          .split(' ')
          .where((w) => w.isNotEmpty && w != 'sich')
          .length ==
      1;
  final gold = <String>{};
  for (final item in read) {
    for (final lemma in item.split('|')) {
      final entries = byHead[lemma];
      if (entries == null) continue;
      final bareOnes = entries.where(bare).toList();
      gold.addAll((bareOnes.isEmpty ? entries : bareOnes).map((e) => e.german));
      break;
    }
  }
  return gold;
}

/// The headwords [lemmatiser] finds in [text], stop words left out.
Set<String> found(Lemmatiser lemmatiser, String text) => <String>{
  for (final tokens in sentencesOf(text))
    for (final (i, entries) in lemmatiser.sentence(tokens).indexed)
      if (!isStopWord(tokens[i], entries))
        for (final entry in entries) entry.german,
};

void main() {
  late List<LemmaEntry> course;
  late Lemmatiser lemmatiser;
  late Map<String, LemmaEntry> byGerman;

  setUpAll(() {
    course = courseEntries();
    lemmatiser = Lemmatiser(course);
    byGerman = <String, LemmaEntry>{for (final e in course) e.german: e};
  });

  List<String> lemmas(String sentence) => <String>[
    for (final entries in lemmatiser.sentence(sentencesOf(sentence).single))
      entries.map((e) => e.german).join('|'),
  ];

  test('#1223 BR-DOC-03: the course words of the corpus (six texts and a '
      'held-out seventh), at least 95 % precision and 90 % recall', () {
    final corpus = Directory('test/fixtures/documents/corpus');
    var predicted = 0;
    var correct = 0;
    var expected = 0;
    final report = StringBuffer();
    for (final file in corpus.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.txt'),
    )) {
      final labels = File(file.path.replaceFirst('.txt', '.labels.json'));
      final read =
          (jsonDecode(labels.readAsStringSync())
                  as Map<String, dynamic>)['read']
              as List;
      final gold = goldOf(read.cast<String>(), course);
      final hits = found(lemmatiser, file.readAsStringSync());
      predicted += hits.length;
      correct += hits.intersection(gold).length;
      expected += gold.length;
      report
        ..writeln(file.uri.pathSegments.last)
        ..writeln('  not in the text: ${hits.difference(gold)}')
        ..writeln('  missed: ${gold.difference(hits)}');
    }
    final precision = correct / predicted;
    final recall = correct / expected;
    // ignore: avoid_print
    print(
      'precision ${precision.toStringAsFixed(3)}, '
      'recall ${recall.toStringAsFixed(3)}\n$report',
    );
    expect(precision, greaterThanOrEqualTo(0.95), reason: '$report');
    expect(recall, greaterThanOrEqualTo(0.90), reason: '$report');
  });

  test('#1223: a noun from its plural, dative plural and genitive', () {
    expect(lemmas('Wir wohnen in den Häusern.')[4], 'Haus');
    expect(lemmas('Die Kosten des Hauses steigen.')[3], 'Haus');
  });

  test('#1223: a strong verb from its Präteritum and Konjunktiv II, through '
      'its prefix', () {
    expect(lemmas('Er ging nach Hause.')[1], 'gehen');
    expect(lemmas('Sie verstand alles.')[1], 'verstehen');
    expect(lemmas('Das wäre gut.')[1], 'sein');
  });

  test('#1223: a separable verb split in a main clause is its particle verb, '
      'joined in a subordinate one too', () {
    expect(byGerman, contains('anrufen'));
    final split = lemmas('Ich rufe Sie morgen an.');
    expect(split[1], 'anrufen');
    expect(split.last, '', reason: 'the particle belongs to the verb');
    expect(lemmas('Bitte rufen Sie an, wenn Sie Zeit haben.')[1], 'anrufen');
    expect(lemmas('Ich weiß, dass er morgen anruft.')[6], 'anrufen');
    expect(lemmas('Er hat angerufen.')[2], 'anrufen');
  });

  test('#1223: a comma inside the main clause (a list) still finds the verb '
      'of a particle', () {
    expect(byGerman, contains('mitbringen'));
    expect(
      lemmas(
        'Bitte bringen Sie den Ausweis, den Lebenslauf und das Zeugnis mit.',
      )[1],
      'mitbringen',
    );
  });

  test('#1223: a particle verb the course lacks is neither its verb nor its '
      'particle', () {
    expect(byGerman, isNot(contains('stattfinden')));
    final words = lemmas(
      'Der Termin findet am Dienstag, dem 14. Oktober, um 10 Uhr statt.',
    );
    expect(words[2], '', reason: 'findet is no form of finden here');
    expect(words.last, '', reason: 'statt is no preposition here');
  });

  test('#1223: case decides between a noun and another word in the middle of '
      'a sentence', () {
    expect(byGerman.keys, containsAll(<String>['Morgen', 'morgen']));
    expect(lemmas('Der Morgen ist kalt.')[1], 'Morgen');
    expect(lemmas('Wir kommen morgen.')[2], 'morgen');
  });

  test('#1223: at the start of a sentence, where case says nothing, an open '
      'reading is offered as ambiguous', () {
    final start = lemmatiser.lookup('Morgen', sentenceStart: true);
    expect(start.map((e) => e.german), <String>['Morgen', 'morgen']);
  });

  test('#1223: a capital in the middle of a sentence with no noun behind it '
      'is a name, not a form', () {
    expect(lemmas('Wir sprechen über das Leben.')[4], '');
  });

  test('#1223: adjective endings and comparison', () {
    expect(lemmas('Das ist eine kleine Wohnung.')[3], 'klein');
    expect(lemmas('Die Wohnung ist kleiner.')[3], 'klein');
    expect(lemmas('Wir suchen eine kleinere Wohnung.')[3], 'klein');
    expect(lemmas('Wir wollen die leiseren Busse.')[3], 'leise');
    expect(lemmas('Das ist ein hoher Preis.')[3], 'hoch');
  });

  test(
    '#1223: an adverb used as an adjective, and an ordinal, take endings',
    () {
      expect(lemmas('Die monatliche Zahlung steigt.')[1], 'monatlich');
      expect(lemmas('Die ersten Busse kommen.')[1], 'erste');
    },
  );

  test('#1223: of two equally founded readings, the headword nearer the '
      'token', () {
    expect(byGerman.keys, containsAll(<String>['nächste', 'nah']));
    expect(lemmas('Wir kommen in den nächsten Tagen.')[4], 'nächste');
  });

  test('#1223 BR-DOC-03: stop words, by form and by lemma', () {
    expect(isStopWord('einige', lemmatiser.lookup('einige')), isTrue);
    expect(isStopWord('meinen', const <LemmaEntry>[]), isTrue);
    expect(isStopWord('wäre', lemmatiser.lookup('wäre')), isTrue);
    expect(isStopWord('Wohnung', lemmatiser.lookup('Wohnung')), isFalse);
  });
}
