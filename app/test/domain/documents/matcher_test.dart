import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/domain/documents/clean.dart';
import 'package:sogda/domain/documents/lemmatiser.dart';
import 'package:sogda/domain/documents/matcher.dart';
import 'package:sogda/domain/text_norm.dart';
import 'package:sqlite3/sqlite3.dart';

import 'lemmatiser_test.dart' show courseEntries;

/// Each course word's step, level and frequency, from the shipped content.
Map<String, CourseWordInfo> courseInfo() {
  final db = sqlite3.open('assets/db/content.db', mode: OpenMode.readOnly);
  try {
    return <String, CourseWordInfo>{
      for (final row in db.select(
        'SELECT w.uid, w.level_code, w.freq, s.ord FROM words w '
        'JOIN sublevels s ON s.code = w.sublevel_code',
      ))
        row['uid'] as String: CourseWordInfo(
          stepOrder: row['ord'] as int,
          level: row['level_code'] as String,
          freq: row['freq'] as int,
        ),
    };
  } finally {
    db.close();
  }
}

const String letter =
    'Der Vermieter schickt die Kündigung. Die Kündigung kommt pünktlich. '
    'Bitte überweisen Sie die Miete auf das Konto. Die Nachzahlung ist '
    'hoch, und wir erhöhen die Miete. Frau Okafor liest den Wasserzähler ab. '
    'Der Hausmeister kommt. Ich rufe einen Taxifahrer.';

void main() {
  late Lemmatiser lemmatiser;
  late Map<String, CourseWordInfo> course;
  late Map<String, String> uid;

  setUpAll(() {
    final entries = courseEntries();
    lemmatiser = Lemmatiser(entries);
    course = courseInfo();
    uid = <String, String>{for (final e in entries) e.german: e.uid};
  });

  /// A learner in A2.1 (step 3), A2.
  LearnerSnapshot learner({int? step = 3}) => LearnerSnapshot(
    status: <String, String>{
      uid['überweisen']!: 'done',
      uid['Miete']!: 'suspended',
      uid['Konto']!: 'learning',
      uid['Hausmeister']!: 'learning',
    },
    everPlanned: <String>{uid['pünktlich']!},
    mine: <String>{searchKey('Wasserzähler', stripArticle: false)},
    activeStepOrder: step,
    level: step == null ? null : 'A2',
  );

  DocumentMatch match([LearnerSnapshot? who]) =>
      matchText(letter, lemmatiser, course, who ?? learner());

  DocWord word(DocumentMatch m, String surface) =>
      m.words.singleWhere((w) => w.surface == surface);

  test('#1225 BR-DOC-03: known is learning, done or suspended', () {
    final m = match();
    for (final known in <String>[
      'überweisen',
      'Miete',
      'Konto',
      'Hausmeister',
    ]) {
      expect(word(m, known).docClass, DocClass.known, reason: known);
    }
  });

  test('#1225 BR-DOC-03: probably known is a step before the active one, in '
      'no day\'s plan; planned and unlearned is backlog, so new', () {
    final m = match();
    expect(word(m, 'Vermieter').docClass, DocClass.probablyKnown);
    expect(word(m, 'pünktlich').docClass, DocClass.newInCourse);
    expect(
      word(match(learner(step: null)), 'Vermieter').docClass,
      DocClass.newInCourse,
      reason: 'with no step under way, nothing is probably known',
    );
  });

  test('#1225 BR-DOC-03: new in the course, in the active step or later', () {
    final m = match();
    for (final fresh in <String>['Kündigung', 'Nachzahlung', 'erhöhen']) {
      expect(word(m, fresh).docClass, DocClass.newInCourse, reason: fresh);
    }
  });

  test('#1225 BR-DOC-03: mine, and outside the course with its compound '
      'hint', () {
    final m = match();
    expect(word(m, 'Wasserzähler').docClass, DocClass.mine);
    final outside = word(m, 'Taxifahrer');
    expect(outside.docClass, DocClass.outside);
    expect(outside.compound, <String>['Taxi', 'Fahrer']);
  });

  test('#1225 BR-DOC-03: no stop word, no name, and no word the sentence '
      'took up («liest … ab», a particle verb the course lacks)', () {
    final surfaces = match().words.map((w) => w.surface).toSet();
    expect(uid, isNot(contains('ablesen')));
    for (final none in <String>[
      'Der',
      'die',
      'Sie',
      'ist',
      'Okafor',
      'liest',
      'ab',
    ]) {
      expect(surfaces, isNot(contains(none)), reason: none);
    }
  });

  test('#1225 BR-DOC-03: a lemma once per document, with all its sentences '
      'and every place it stands', () {
    final m = match();
    final kuendigung = word(m, 'Kündigung');
    expect(kuendigung.sentences, <int>[0, 1]);
    expect(kuendigung.spans, hasLength(2));
    for (final (start, end) in kuendigung.spans) {
      expect(letter.substring(start, end), 'Kündigung');
    }
    expect(
      m.words.where((w) => w.entries.any((e) => e.german == 'Miete')),
      hasLength(1),
    );
  });

  test('#1225: ranked by the learner\'s level, then one above, then the rest '
      'by frequency; mine and outside last, as they appear', () {
    final words = match().words;
    expect(
      words.first.surface,
      'Kündigung',
      reason: 'A2, the learner\'s level',
    );
    int at(String surface) => words.indexWhere((w) => w.surface == surface);
    expect(at('Nachzahlung'), lessThan(at('erhöhen')), reason: 'B1 before B2');
    expect(words.skip(words.length - 2).map((w) => w.surface), <String>[
      'Wasserzähler',
      'Taxifahrer',
    ]);
  });

  test('#1225: an ambiguous word is one entry with its readings, classed as '
      'the one most worth offering', () {
    final m = matchText(
      'Morgen kommt der Hausmeister.',
      lemmatiser,
      course,
      learner(),
    );
    final morgen = word(m, 'Morgen');
    expect(morgen.ambiguous, isTrue);
    expect(morgen.entries.map((e) => e.german), <String>['Morgen', 'morgen']);
  });

  test('#1225: a word twice in one sentence is one sentence, two places', () {
    final m = matchText(
      'Die Kündigung kommt, die Kündigung gilt.',
      lemmatiser,
      course,
      learner(),
    );
    final kuendigung = word(m, 'Kündigung');
    expect(kuendigung.sentences, <int>[0]);
    expect(kuendigung.spans, hasLength(2));
  });

  test('#1225: an ambiguous word is classed by its reading most worth '
      'offering', () {
    final who = learner();
    final m = matchText(
      'Morgen kommt der Hausmeister.',
      lemmatiser,
      course,
      LearnerSnapshot(
        status: <String, String>{...who.status, uid['Morgen']!: 'learning'},
        everPlanned: who.everPlanned,
        mine: who.mine,
        activeStepOrder: who.activeStepOrder,
        level: who.level,
      ),
    );
    expect(
      word(m, 'Morgen').docClass,
      isNot(DocClass.known),
      reason: 'the noun is known, the adverb is not',
    );
  });

  test('#1225 FR-D1-04: the run says how German the text is', () {
    expect(match().germanShare, greaterThanOrEqualTo(0.5));
  });

  test('#1225: a two-page letter, cleaned and matched, well inside 500 ms '
      'on this machine (the device budget is perf.py\'s)', () {
    final text = cleanPages(<String>[
      File('test/fixtures/documents/corpus/letter_landlord.txt')
          .readAsStringSync(),
      File('test/fixtures/documents/corpus/letter_jobcenter.txt')
          .readAsStringSync(),
    ]);
    final watch = Stopwatch()..start();
    final m = matchText(text, lemmatiser, course, learner());
    watch.stop();
    expect(m.words, isNotEmpty);
    expect(watch.elapsedMilliseconds, lessThan(500));
  });
}
