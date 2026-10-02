import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/domain/documents/clean.dart';
import 'package:sogda/domain/documents/lemmatiser.dart';
import 'package:sogda/domain/documents/stop_words.dart';
import 'package:sogda/domain/documents/tokens.dart';
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

/// [text] as #1224 splits it: its sentences' words and clause marks.
List<List<String>> sentencesOf(String text) => <List<String>>[
  for (final sentence in splitText(cleanPages(<String>[text]))) sentence.words,
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

  test('#1223 #1267 BR-DOC-03: the course words of the corpus (six texts, a '
      'held-out seventh and three held-out more), at least 95 % precision and '
      '90 % recall', () {
    final corpus = Directory('test/fixtures/documents/corpus');
    var predicted = 0;
    var correct = 0;
    var expected = 0;
    final report = StringBuffer();
    for (final file in corpus.listSync().whereType<File>().where(
      // The not-German texts (english, bangla) have no labels.
      (f) =>
          f.path.endsWith('.txt') &&
          File(f.path.replaceFirst('.txt', '.labels.json')).existsSync(),
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

  // #1267: the held-out texts word for word. One broken rule barely moves the
  // corpus's floor, so each text's misses are pinned: a change here is a
  // regression, or a fix, to name. The two known ones are written down.
  test('#1267 BR-DOC-03: the held-out texts find their labels, but for two '
      'known misses', () {
    const known = <String, ({Set<String> extra, Set<String> missed})>{
      // «…ab oder geben Sie ihm eine Erlaubnis mit,»: an imperative after
      // «oder» isn't read as the particle verb (#1256's review).
      'heldout_school': (extra: {'geben'}, missed: {}),
      'heldout_doctor': (extra: {}, missed: {}),
      // «auf den Bänken»: the course's Bank has only «Banken» (content).
      'heldout_news': (extra: {}, missed: {'Bank'}),
    };
    for (final MapEntry(key: name, value: misses) in known.entries) {
      final text = File('test/fixtures/documents/corpus/$name.txt')
          .readAsStringSync();
      final read =
          (jsonDecode(
                File('test/fixtures/documents/corpus/$name.labels.json')
                    .readAsStringSync(),
              ) as Map<String, dynamic>)['read']
              as List;
      final gold = goldOf(read.cast<String>(), course);
      final hits = found(lemmatiser, text);
      expect(hits.difference(gold), misses.extra, reason: '$name: not in it');
      expect(gold.difference(hits), misses.missed, reason: '$name: missed');
    }
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
      'is a name, not a form; after an article it is a nominalised '
      'infinitive', () {
    expect(lemmas('Wir sprechen mit Hansen.')[3], '');
    expect(lemmas('Beim Lesen lerne ich viel.')[1], 'lesen');
    expect(lemmas('Wir sprechen über das Leben.')[4], 'leben');
  });

  test('#1223: sein\'s Präteritum is sein, stopped, never the C2 headword '
      '«ward»', () {
    expect(byGerman, contains('ward'));
    for (final (sentence, at) in <(String, int)>[
      ('Das Wetter war schlecht.', 2),
      ('Er war gestern krank.', 1),
      ('Wir waren im Kino.', 1),
    ]) {
      final tokens = sentencesOf(sentence).single;
      final entries = lemmatiser.sentence(tokens)[at];
      expect(entries.map((e) => e.german), <String>['sein'], reason: sentence);
      expect(isStopWord(tokens[at], entries), isTrue, reason: sentence);
    }
  });

  test('#1223: a letter\'s salutation «Liebe …», «Lieber …» is no word to '
      'offer; «Liebe» alone is the noun', () {
    expect(lemmas('Liebe Eltern, wir laden Sie ein.')[0], '');
    expect(lemmas('Lieber Herr Becker, danke.')[0], '');
    expect(lemmas('Liebe ist schön.')[0], 'Liebe');
  });

  test('#1223: the old dative -e («nach Hause»), and -eln\'s 1st person', () {
    expect(lemmas('Ich gehe nach Hause.')[3], 'Haus');
    expect(lemmas('Ich sammle Briefmarken.')[1], 'sammeln');
  });

  test('#1223: a particle verb the course lacks, its verb opening the '
      'sentence, is unmatched; a direction alone keeps the verb', () {
    expect(byGerman, isNot(contains('mitgeben')));
    final words = lemmas('Geben Sie ihm eine Erlaubnis mit, allein zu gehen.');
    expect(words[0], '', reason: 'Geben … mit is mitgeben');
    expect(words[5], '');
    expect(byGerman, isNot(contains('hingehen')));
    expect(lemmas('Wo gehst du hin?')[1], 'gehen');
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

  test('#1274 BR-DOC-03: sein\'s and werden\'s irregular forms are their '
      'verb, and stopped', () {
    for (final (sentence, at, verb) in <(String, int, String)>[
      ('Ich bin heute zu Hause.', 1, 'sein'),
      ('Bist du morgen da?', 0, 'sein'),
      ('Die Unterlagen sind vollständig.', 2, 'sein'),
      ('Ihr seid herzlich eingeladen.', 1, 'sein'),
      ('Du wirst es sehen.', 1, 'werden'),
      ('Der Antrag ist geprüft worden.', 4, 'werden'),
    ]) {
      final tokens = sentencesOf(sentence).single;
      final entries = lemmatiser.sentence(tokens)[at];
      expect(entries.map((e) => e.german), <String>[verb], reason: sentence);
      expect(isStopWord(tokens[at], entries), isTrue, reason: sentence);
    }
  });

  test('#1274 BR-DOC-03: «mag» is mögen\'s, stopped, before the C1 headword '
      '«mag»', () {
    expect(byGerman.keys, containsAll(<String>['mag', 'mögen']));
    for (final (sentence, at) in <(String, int)>[
      ('Ich mag den Sommer.', 1),
      ('Magst du Kaffee?', 0),
    ]) {
      final tokens = sentencesOf(sentence).single;
      final entries = lemmatiser.sentence(tokens)[at];
      expect(entries.map((e) => e.german), <String>['mögen'], reason: sentence);
      expect(isStopWord(tokens[at], entries), isTrue, reason: sentence);
    }
    // The other headwords that are a form stay what they were.
    expect(lemmas('Das dürfte teuer werden.')[1], 'dürfte');
  });

  test('#1274: «weiß» is wissen or the colour, and D2 asks which', () {
    expect(lemmas('Ich weiß es nicht.')[1], 'weiß|wissen');
    expect(lemmas('Die Wand ist weiß.')[3], 'weiß|wissen');
    expect(lemmas('Das weiße Auto steht dort.')[1], 'weiß');
    expect(lemmas('Weißt du das?')[0], 'wissen');
  });
}
