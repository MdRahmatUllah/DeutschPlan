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
  /// the set's that are about it ([compareMembers]).
  final List<CompareExample> examples;

  /// The Example row's sentence.
  CompareExample? get example => examples.firstOrNull;

  /// "der Grund", as it is said.
  String get spoken => article == null ? headword : '$article $headword';

  /// Where [text] names this member, inflected or not ("Folgen haben" names
  /// *Folge*): `clozeGap`'s test. Null for nowhere.
  ClozeGap? gapIn(String text) => clozeGap(text, headword, pos: pos);
}

/// FR-W1-06: whether a headword names a near-synonym set W2 compares —
/// "circa / etwa / rund", "Grüß Gott / Servus / Pfiat di". Not a
/// word-formation entry ("Adjektive auf -bar / -lich / -sam", "Präfix
/// voll- / durch- / über-"): its parts are affixes, not words to choose
/// between.
///
/// `compare.md` also names a `compare_group`; content.db has no such column,
/// so the headword is the only signal.
/// ponytail: add the group when content.db grows one.
bool comparesSet(String german) =>
    german.contains(' / ') && !_affix.hasMatch(german);

final RegExp _affix = RegExp(r'(^|\s)-\p{L}|\p{L}-(\s|$)', unicode: true);

/// FR-W2-01: a set's members, from its headword split on " / " — and on
/// ", ", for "legen / liegen, setzen / sitzen, …" — without a trailing "…"
/// ("Lieber …").
List<String> compareMemberNames(String german) => <String>[
  for (final part in german.split(_members))
    if (part.replaceFirst(_ellipsis, '').trim() case final name
        when name.isNotEmpty)
      name,
];

final RegExp _members = RegExp(r' / |, ');
final RegExp _ellipsis = RegExp(r'\s*…\s*$');

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
/// - Meaning: the set's English split on " / " (or " vs. ") when it has one
///   part per member; else the member's word's English.
/// - Register: the labels in brackets after the member's name in the set's
///   `synonyms_register` ("etwa (neutral)", "circa/rund (written)"), of two
///   words at most — a longer bracket is a note, not a register.
/// - With: the set's collocations (split on ";") that name the member;
///   else the member's word's own.
/// - Example: the member's word's first sentence; else the first of the
///   set's that is about it ([_about]).
/// - Use it when: "member = note" in the set's `synonyms_register`
///   ("Ursache = objective cause").
List<CompareMember> compareMembers(CompareSet set) {
  final word = set.word;
  final names = compareMemberNames(word.german);
  final meanings = <List<String>>[
    for (final separator in const <String>[' / ', ' vs. '])
      word.english.split(separator),
  ].where((parts) => parts.length == names.length).firstOrNull;
  final collocations = <String>[
    for (final part in (word.collocations ?? '').split(';'))
      if (part.trim().isNotEmpty) part.trim(),
  ];

  // The columns without their sentences first: which of the set's sentences
  // is whose takes every member's gap in it.
  CompareMember bare(int i, String name) {
    final own = set.resolved[name];
    final (written, headword) = splitArticle(name);
    return CompareMember(
      headword: headword,
      article: own?.article ?? written,
      uid: own?.uid,
      step: own?.step ?? word.step,
      pos: own?.pos ?? word.pos,
      meaning: meanings?[i].trim() ?? own?.english,
      register: _labels(word.register, headword),
      useWhen: _note(word.register, headword),
    );
  }

  final columns = <CompareMember>[
    for (final (i, name) in names.indexed) bare(i, name),
  ];
  final about = <String, CompareMember?>{
    for (final example in word.examples)
      example.german: _about(example.german, columns),
  };

  CompareMember full(int i, CompareMember member) {
    final own = set.resolved[names[i]];
    final withs = collocations
        .where((part) => member.gapIn(part) != null)
        .join(' · ');
    final ownWith = (own?.collocations ?? '')
        .split(';')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(' · ');
    final seen = <String>{};
    return CompareMember(
      headword: member.headword,
      article: member.article,
      uid: member.uid,
      step: member.step,
      pos: member.pos,
      meaning: member.meaning,
      register: member.register,
      useWhen: member.useWhen,
      withText: withs.isNotEmpty
          ? withs
          : ownWith.isNotEmpty
          ? ownWith
          : null,
      examples: <CompareExample>[
        for (final example in <CompareExample>[
          ...?own?.examples,
          ...word.examples.where((e) => identical(about[e.german], member)),
        ])
          if (seen.add(example.german)) example,
      ],
    );
  }

  return <CompareMember>[
    for (final (i, member) in columns.indexed) full(i, member),
  ];
}

/// The member of [members] a sentence is about, of those it names: one
/// named by its own key before one named by a prefix or by one of its words,
/// then the longest gap, then the first. "Lieber Tom" is *Lieber*'s, not
/// *Liebe*'s; "gerade erst erschienen" is *gerade erst*'s, not *eben
/// erst*'s. Null when it names none.
CompareMember? _about(String sentence, List<CompareMember> members) {
  CompareMember? best;
  var bestExact = false;
  var bestLength = 0;
  for (final member in members) {
    final gap = member.gapIn(sentence);
    if (gap == null) continue;
    final exact =
        searchKey(sentence.substring(gap.start, gap.end)) ==
        searchKey(member.headword);
    final length = gap.end - gap.start;
    if (best == null ||
        (exact && !bestExact) ||
        (exact == bestExact && length > bestLength)) {
      best = member;
      bestExact = exact;
      bestLength = length;
    }
  }
  return best;
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
/// [headword]'s name, of two words at most ("teilen (German verbs exist)"
/// is a note).
List<String>? _labels(String? register, String headword) {
  final labels = <String>[
    for (final match in _labelled.allMatches(register ?? ''))
      if (_named(match[1]!, headword) &&
          match[2]!.trim().split(_space).length <= 2)
        match[2]!.trim(),
  ];
  return labels.isEmpty ? null : labels;
}

final RegExp _labelled = RegExp(r'([^,;()]+?)\s*\(([^)]+)\)');
final RegExp _space = RegExp(r'\s+');

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
/// Every sentence of every member (its word's own, and the set's it is
/// about) is asked once, gapped where it names its member — but only one
/// that names a single member: where two are named, the other's name gives
/// the answer away, or the gap is a guess ("Lieber Tom" names *Liebe* by
/// prefix too). Each item rates the member's word, or the set's, [setUid],
/// for one the course has no word for. The tiles are the members (at most
/// four), the hint the sentence's English. Up to [length] of them, in
/// [seed]'s order.
List<QuizItem> compareQuizItems(
  List<CompareMember> members, {
  required String setUid,
  required int seed,
  int length = 5,
}) {
  final random = Random(seed);
  final seen = <String>{};
  final asked = <(CompareMember, CompareExample, ClozeGap)>[];
  for (final example in <CompareExample>[
    for (final member in members) ...member.examples,
  ]) {
    if (!seen.add(example.german)) continue;
    final named = <(CompareMember, ClozeGap)>[
      for (final member in members)
        if (member.gapIn(example.german) case final gap?) (member, gap),
    ];
    if (named case [(final member, final gap)]) {
      asked.add((member, example, gap));
    }
  }
  asked.shuffle(random);
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
