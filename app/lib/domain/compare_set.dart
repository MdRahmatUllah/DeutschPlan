/// W2's near-synonym sets (`compare.md`, #142): the members of a set and
/// what each one's cells say, and the quiz *Quiz these* asks from them.
///
/// Plain Dart: no Flutter, no drift.
library;

import 'dart:math';

import 'package:deutschplan/domain/cloze.dart';
import 'package:deutschplan/domain/quiz_builder.dart';
import 'package:deutschplan/domain/text_norm.dart';

/// An example sentence, and its English when the course has one.
typedef CompareExample = ({String german, String? english});

/// A course word as W2 reads it: the set's own row, or a member's.
class CompareWord {
  const CompareWord({
    required this.uid,
    required this.german,
    required this.english,
    required this.step,
    this.article,
    this.pos,
    this.register,
    this.collocations,
    this.examples = const <CompareExample>[],
  });

  final String uid;
  final String german;
  final String english;

  /// The sublevel code, e.g. `C2.1`.
  final String step;
  final String? article;
  final String? pos;

  /// The `synonyms_register` cell.
  final String? register;
  final String? collocations;
  final List<CompareExample> examples;
}

/// A set word, and the course words its members resolved to, keyed by the
/// member as the set writes it ("Grund", "die Kohle").
class CompareSet {
  const CompareSet(this.word, [this.resolved = const <String, CompareWord>{}]);

  final CompareWord word;
  final Map<String, CompareWord> resolved;
}

/// One column of W2. A null cell is drawn "—" (FR-W2-02).
class CompareMember {
  const CompareMember({
    required this.headword,
    required this.step,
    this.article,
    this.uid,
    this.pos,
    this.meaning,
    this.register,
    this.withText,
    this.useWhen,
    this.examples = const <CompareExample>[],
  });

  /// As the set writes it, without its article: "Grund", "ganz schön".
  final String headword;

  /// The resolved word's, or one the set writes before the member.
  final String? article;

  /// The resolved course word; null for a member the course has no word for.
  final String? uid;

  /// The resolved word's step, else the set's.
  final String step;

  /// Its part of speech, for finding it inflected in a sentence.
  final String? pos;
  final String? meaning;

  /// The register chips: "neutral", "written".
  final List<String>? register;

  /// The collocations it is used with: "aus diesem Grund".
  final String? withText;
  final String? useWhen;

  /// Every sentence it is shown or asked in: the resolved word's own, then
  /// the set's that name it.
  final List<CompareExample> examples;

  /// The Example row's sentence.
  CompareExample? get example => examples.firstOrNull;

  /// "der Grund", as it is said.
  String get spoken => article == null ? headword : '$article $headword';
}

/// FR-W2-01: a set's members, from its headword split on " / ".
///
/// `compare.md` also names a `compare_group`; content.db has no such column,
/// so the headword is the only source (as W1's `comparesSet` finds).
/// ponytail: add the group when content.db grows one.
List<String> compareMemberNames(String german) => <String>[
  for (final part in german.split(' / '))
    if (part.trim().isNotEmpty) part.trim(),
];

/// A member's article, when the set writes one ("die Kohle"), and the rest.
(String?, String) splitArticle(String name) {
  final match = _article.firstMatch(name);
  return match == null ? (null, name) : (match[1], match[2]!);
}

final RegExp _article = RegExp(r'^(der|die|das)\s+(.+)$');

/// W2's columns, one per member of [set], in the set's order (FR-W2-01,
/// FR-W2-02). The set's own cells speak for every member; a member's own
/// word fills what they leave out:
///
/// - Meaning: the set's English split on " / " when it has one part per
///   member; else the member's word's English.
/// - Register: the labels in brackets after the member's name in the set's
///   `synonyms_register` ("etwa (neutral)", "circa/rund (written)").
/// - With: the set's collocations (split on ";") that name the member;
///   else the member's word's own.
/// - Example: the member's word's first sentence; else the first of the
///   set's that names it.
/// - Use it when: "member = note" in the set's `synonyms_register`
///   ("Ursache = objective cause").
///
/// "Names" is `clozeGap`'s test: the member's search key, inflected or not
/// ("Folgen haben" names *Folge*).
List<CompareMember> compareMembers(CompareSet set) {
  final word = set.word;
  final names = compareMemberNames(word.german);
  final meanings = word.english.split(' / ');
  final collocations = <String>[
    for (final part in (word.collocations ?? '').split(';'))
      if (part.trim().isNotEmpty) part.trim(),
  ];
  CompareMember member(int i, String name) {
    final own = set.resolved[name];
    final (written, headword) = splitArticle(name);
    final pos = own?.pos ?? word.pos;
    bool mentions(String text) => clozeGap(text, headword, pos: pos) != null;
    final withs = collocations.where(mentions).join(' · ');
    final ownWith = (own?.collocations ?? '')
        .split(';')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(' · ');
    final seen = <String>{};
    return CompareMember(
      headword: headword,
      article: own?.article ?? written,
      uid: own?.uid,
      step: own?.step ?? word.step,
      pos: pos,
      meaning: meanings.length == names.length
          ? meanings[i].trim()
          : own?.english,
      register: _labels(word.register, headword),
      withText: withs.isNotEmpty
          ? withs
          : ownWith.isNotEmpty
          ? ownWith
          : null,
      useWhen: _note(word.register, headword),
      examples: <CompareExample>[
        for (final example in <CompareExample>[
          ...?own?.examples,
          ...word.examples.where((e) => mentions(e.german)),
        ])
          if (seen.add(example.german)) example,
      ],
    );
  }

  return <CompareMember>[
    for (final (i, name) in names.indexed) member(i, name),
  ];
}

/// Whether [text] names [headword]: the same search key, articles and
/// umlauts folded. "circa/rund" names both.
bool _named(String text, String headword) => text
    .split('/')
    .any(
      (name) =>
          name.trim().isNotEmpty && searchKey(name) == searchKey(headword),
    );

/// "ungefähr (spoken), etwa (neutral)": the bracketed labels after
/// [headword]'s name.
List<String>? _labels(String? register, String headword) {
  final labels = <String>[
    for (final match in _labelled.allMatches(register ?? ''))
      if (_named(match[1]!, headword)) match[2]!.trim(),
  ];
  return labels.isEmpty ? null : labels;
}

final RegExp _labelled = RegExp(r'([^,;()]+?)\s*\(([^)]+)\)');

/// "Anlass = occasion, Ursache = objective cause": the note after
/// [headword]'s name. Split at a semicolon, or at a comma that starts the
/// next pair, so a note may carry commas of its own.
String? _note(String? register, String headword) {
  for (final pair in (register ?? '').split(_pairs)) {
    final at = pair.indexOf('=');
    if (at < 0) continue;
    final note = pair.substring(at + 1).trim();
    if (note.isNotEmpty && _named(pair.substring(0, at), headword)) return note;
  }
  return null;
}

final RegExp _pairs = RegExp(r';|,(?=[^;,=]+=)');

/// FR-W2-03: *Quiz these* — pick the member a sentence is missing.
///
/// Every sentence of every member (its word's own, and the set's that name
/// it) is asked once, gapped where it names its member, with the member's
/// word — or the set's, [setUid], for one the course has no word for — as
/// the one it rates. The tiles are the members (at most four), the hint the
/// sentence's English. Up to [length] of them, in [seed]'s order.
List<QuizItem> compareQuizItems(
  List<CompareMember> members, {
  required String setUid,
  required int seed,
  int length = 5,
}) {
  final random = Random(seed);
  final seen = <String>{};
  final asked = <(CompareMember, CompareExample, ClozeGap)>[
    for (final member in members)
      for (final example in member.examples)
        if (clozeGap(example.german, member.headword, pos: member.pos)
            case final gap? when seen.add(example.german))
          (member, example, gap),
  ]..shuffle(random);
  final names = <String>{for (final member in members) member.headword};
  return <QuizItem>[
    for (final (i, (member, example, gap)) in asked.take(length).indexed)
      QuizItem(
        ord: i + 1,
        wordUid: member.uid ?? setUid,
        direction: QuizDirection.compare,
        prompt: example.german.replaceRange(gap.start, gap.end, '___'),
        expected: member.headword,
        options: <String>[
          member.headword,
          ...(names.where((name) => name != member.headword).toList()
                ..shuffle(random))
              .take(3),
        ]..shuffle(random),
        hint: example.english,
      ),
  ];
}
