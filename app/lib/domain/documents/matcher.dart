/// #1225: each word a document holds, once, classed (BR-DOC-03) and ranked
/// (`03-domain/document-matcher.md`, pipeline steps 6 and 7). Pure Dart: the
/// data layer hands over the course's words and the learner's state.
library;

import 'package:sogda/domain/documents/lemmatiser.dart';
import 'package:sogda/domain/documents/stop_words.dart';
import 'package:sogda/domain/documents/tokens.dart';
import 'package:sogda/domain/text_norm.dart';

/// BR-DOC-03's classes, in D2's order of interest.
enum DocClass { newInCourse, probablyKnown, known, mine, outside }

/// What the matcher needs of a course word beside its lemma.
class CourseWordInfo {
  const CourseWordInfo({
    required this.stepOrder,
    required this.level,
    required this.freq,
  });

  /// Its step's place in the course's order of steps (A1.1 is 1, C2.2 is
  /// 12): `allSublevels`' order, not a column read raw.
  final int stepOrder;

  /// A1 … C2.
  final String level;

  /// 1–5, 5 the commonest.
  final int freq;
}

/// The learner's state, read once before a run.
class LearnerSnapshot {
  const LearnerSnapshot({
    required this.status,
    required this.everPlanned,
    required this.mine,
    this.mineUids = const <String>{},
    this.activeStepOrder,
    this.level,
  });

  /// `word_state.status` by uid; a uid that isn't there is `todo`.
  final Map<String, String> status;

  /// Every uid any day's plan has held (`plan_items`).
  final Set<String> everPlanned;

  /// *My words*, by `searchKey` of their German.
  final Set<String> mine;

  /// The course words that are also *My words* (`custom_words.matched_uid`):
  /// offered as the course word, with D2's "My word" mark.
  final Set<String> mineUids;

  /// The active step's `sublevels.ord`; null with no step under way.
  final int? activeStepOrder;

  /// The active step's level (A2), which D2's *Add my level* adds.
  final String? level;
}

/// A lemma of the document, once, with every place it stands.
class DocWord {
  DocWord._(
    this.key,
    this.entries,
    this.surface,
    this.docClass,
    this.compound, {
    required this.mine,
  });

  /// Its lemma, as `document_words.lemma_key` stores it: the course uids
  /// (`|`-joined when ambiguous), or `outside:` and the search key.
  final String key;

  /// Its course entries: several when the learner has to choose («Morgen»
  /// at the start of a sentence), none when it's outside the course.
  final List<LemmaEntry> entries;

  /// The form it first appears in.
  final String surface;

  final DocClass docClass;

  /// A word outside the course that is a compound of course words: the
  /// hint «Nebenkosten + Abrechnung».
  final List<String>? compound;

  /// One of *My words*: the class [DocClass.mine], or a course word the
  /// learner also keeps as their own, which D2 marks "My word".
  final bool mine;

  /// Where it stands in the text: [start, end) of each occurrence.
  final List<(int, int)> spans = <(int, int)>[];

  /// The sentences it stands in, by index into [DocumentMatch.sentences].
  final List<int> sentences = <int>[];

  bool get ambiguous => entries.length > 1;
}

class DocumentMatch {
  const DocumentMatch(this.sentences, this.words, this.germanShare);

  final List<DocSentence> sentences;

  /// Ranked: course words by level (the learner's, then one above, then
  /// the rest) and frequency, then *Mine* and outside the course as they
  /// appear.
  final List<DocWord> words;

  /// FR-D1-04: below [germanThreshold], the text doesn't look German.
  final double germanShare;
}

const List<String> _levels = <String>['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

/// [text] (from `cleanPages`), matched against the course and the learner.
DocumentMatch matchText(
  String text,
  Lemmatiser lemmatiser,
  Map<String, CourseWordInfo> course,
  LearnerSnapshot learner,
) {
  final sentences = splitText(text);
  final byKey = <String, DocWord>{};
  for (final (s, sentence) in sentences.indexed) {
    final tokens = sentence.words;
    final lemmas = lemmatiser.sentence(tokens);
    final first = sentence.tokens.indexWhere((t) => t.isWord);
    // The word before, by its index: its text and its course readings, for
    // likelyName's adjective sign (#1270), as germanShare passes them.
    var previous = -1;
    for (final (i, token) in sentence.tokens.indexed) {
      if (!token.isWord) continue;
      final before = previous;
      previous = i;
      final entries = lemmas[i];
      if (isStopWord(token.text, entries)) continue;
      final String key;
      DocWord Function() create;
      if (entries.isNotEmpty) {
        key = entries.map((e) => e.uid).join('|');
        create = () => DocWord._(
          key,
          entries,
          token.text,
          _courseClass(entries, course, learner),
          null,
          mine: entries.any((e) => learner.mineUids.contains(e.uid)),
        );
      } else {
        // A word the sentence took up (a split particle, «findet … statt», a
        // salutation) has a reading of its own: it's no word outside the
        // course.
        final start = i == first;
        if (lemmatiser.lookup(token.text, sentenceStart: true).isNotEmpty) {
          continue;
        }
        final parts = lemmatiser.compoundParts(token.text);
        if (likelyName(
          token.text,
          sentenceStart: start,
          compound: parts != null,
          previous: before < 0 ? null : sentence.tokens[before].text,
          previousEntries: before < 0 ? const <LemmaEntry>[] : lemmas[before],
        )) {
          continue;
        }
        final search = searchKey(token.text, stripArticle: false);
        key = 'outside:$search';
        create = () => DocWord._(
          key,
          const <LemmaEntry>[],
          token.text,
          learner.mine.contains(search) ? DocClass.mine : DocClass.outside,
          parts,
          mine: learner.mine.contains(search),
        );
      }
      final word = byKey.putIfAbsent(key, create);
      word.spans.add((token.start, token.end));
      if (word.sentences.isEmpty || word.sentences.last != s) {
        word.sentences.add(s);
      }
    }
  }
  return DocumentMatch(
    sentences,
    _ranked(byKey.values.toList(), course, learner.level),
    germanShare(sentences, lemmatiser),
  );
}

/// One class for a lemma's entries: the most worth offering among them, so
/// an ambiguous word the learner may still need is offered (D2 asks which).
DocClass _courseClass(
  List<LemmaEntry> entries,
  Map<String, CourseWordInfo> course,
  LearnerSnapshot learner,
) {
  DocClass of(LemmaEntry entry) {
    final status = learner.status[entry.uid] ?? 'todo';
    // BR-STATUS-01: a word in learning, done or suspended (which no plan
    // takes, BR-STATUS-03) is never offered.
    if (status != 'todo') return DocClass.known;
    // A word of my own I added, so I don't know it: never probably known.
    if (learner.mineUids.contains(entry.uid)) return DocClass.newInCourse;
    final step = course[entry.uid]?.stepOrder;
    final active = learner.activeStepOrder;
    // A step placement or *Choose myself* skipped: before the active one,
    // and in no day's plan. A planned word left unlearned is backlog: new.
    if (step != null &&
        active != null &&
        step < active &&
        !learner.everPlanned.contains(entry.uid)) {
      return DocClass.probablyKnown;
    }
    return DocClass.newInCourse;
  }

  return entries.map(of).reduce((a, b) => a.index < b.index ? a : b);
}

List<DocWord> _ranked(
  List<DocWord> words,
  Map<String, CourseWordInfo> course,
  String? level,
) {
  final mine = _levels.indexOf(level ?? '');
  int levelRank(DocWord word) {
    final at = _levels.indexOf(course[word.entries.first.uid]?.level ?? '');
    if (mine < 0 || at < 0) return 2;
    if (at == mine) return 0;
    if (at == mine + 1) return 1;
    return 2;
  }

  int freq(DocWord word) => course[word.entries.first.uid]?.freq ?? 0;
  final inCourse = words.where((w) => w.entries.isNotEmpty).toList();
  final appearance = <DocWord, int>{
    for (final (i, word) in words.indexed) word: i,
  };
  inCourse.sort((a, b) {
    final byLevel = levelRank(a).compareTo(levelRank(b));
    if (byLevel != 0) return byLevel;
    final byFreq = freq(b).compareTo(freq(a));
    if (byFreq != 0) return byFreq;
    return appearance[a]!.compareTo(appearance[b]!);
  });
  return <DocWord>[...inCourse, ...words.where((w) => w.entries.isEmpty)];
}
