import 'dart:math';

import 'package:deutschplan/domain/plan_engine.dart' show PlanDate;
import 'package:deutschplan/domain/text_norm.dart';

/// An example sentence that could be practised: its headword and place in
/// the word's examples, which together are its key in `sentence_log`.
class SentenceCandidate {
  const SentenceCandidate({
    required this.wordUid,
    required this.ord,
    required this.german,
    this.english,
  });

  final String wordUid;
  final int ord;
  final String german;
  final String? english;

  @override
  bool operator ==(Object other) =>
      other is SentenceCandidate &&
      other.wordUid == wordUid &&
      other.ord == ord;

  @override
  int get hashCode => Object.hash(wordUid, ord);

  @override
  String toString() => 'SentenceCandidate($wordUid#$ord)';
}

/// What the picker needs from the database. `sentence_picker.dart` stays pure
/// Dart, like the plan engine, so its choices are testable without one.
abstract interface class SentenceStore {
  /// The sentences already picked for [date], in the order they were picked.
  Future<List<SentenceCandidate>> shownOn(PlanDate date);

  /// The examples of learned words (learning or done, not suspended) that
  /// were not shown on the [gapDays] days before [today].
  Future<List<SentenceCandidate>> candidates(
    PlanDate today, {
    required int gapDays,
  });

  /// The search keys of the learned words.
  Future<Set<String>> learnedKeys();

  /// Writes [picked] to `sentence_log` as shown on [date].
  Future<void> record(PlanDate date, List<SentenceCandidate> picked);
}

/// Picks the day's practice sentences (`docs/03-domain/sentences.md`).
class SentencePicker {
  SentencePicker(this._store, {required this.count, required this.gapDays});

  final SentenceStore _store;

  /// `sentence_count`.
  final int count;

  /// `sentence_repeat_gap_days`.
  final int gapDays;

  /// FR-T5-01: the day's sentences, stable once picked — the day reopened
  /// gets the same set back from `sentence_log`.
  Future<List<SentenceCandidate>> forDay(PlanDate today) async {
    final shown = await _store.shownOn(today);
    if (shown.isNotEmpty) return shown;

    final picked = pickSentences(
      await _store.candidates(today, gapDays: gapDays),
      learned: await _store.learnedKeys(),
      count: count,
      seed: seedFor(today),
    );
    if (picked.isNotEmpty) await _store.record(today, picked);
    return picked;
  }

  /// The day's seed: the same date draws the same jitter.
  static int seedFor(PlanDate day) => int.parse(day.replaceAll('-', ''));
}

/// How many candidates are scored: the spec's "random 400".
const int sentenceSampleSize = 400;

/// The jitter's ceiling. Small enough to reorder only near-equal sentences,
/// so coverage still decides and the same few do not win every day.
const double sentenceJitter = 0.05;

/// Share of [sentence]'s tokens longer than two letters whose search key is
/// a learned word's key or starts with one — "Wohnungen" counts for
/// "Wohnung".
double coverage(String sentence, Set<String> learned) {
  final tokens = <String>[
    for (final match in _word.allMatches(sentence))
      if (match[0]!.length > 2) searchKey(match[0]!, stripArticle: false),
  ];
  if (tokens.isEmpty) return 0;
  final known = tokens.where(
    (token) =>
        learned.contains(token) ||
        learned.any((key) => key.isNotEmpty && token.startsWith(key)),
  );
  return known.length / tokens.length;
}

/// Picks [count] sentences with distinct headwords, highest coverage first.
///
/// A seeded sample of [sentenceSampleSize], scored with a seeded jitter, so a
/// day's choice can be reproduced — though `sentence_log` is what makes it
/// stable.
List<SentenceCandidate> pickSentences(
  List<SentenceCandidate> candidates, {
  required Set<String> learned,
  required int count,
  required int seed,
}) {
  if (count <= 0 || candidates.isEmpty) return const <SentenceCandidate>[];
  final random = Random(seed);
  final sample = (List<SentenceCandidate>.of(
    candidates,
  )..shuffle(random)).take(sentenceSampleSize);
  final scored = <(SentenceCandidate, double)>[
    for (final candidate in sample)
      (
        candidate,
        coverage(candidate.german, learned) +
            random.nextDouble() * sentenceJitter,
      ),
  ]..sort((a, b) => b.$2.compareTo(a.$2));

  final headwords = <String>{};
  return <SentenceCandidate>[
    for (final (candidate, _) in scored)
      if (headwords.length < count && headwords.add(candidate.wordUid))
        candidate,
  ];
}

final RegExp _word = RegExp(r'\p{L}+', unicode: true);
