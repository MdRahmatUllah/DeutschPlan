/// BR-SEARCH-03's distance: optimal string alignment, not plain Levenshtein.
///
/// OSA counts a transposition as one edit, which is what makes "Strasse" two
/// away from "Straße" rather than three and what a mistyped "Haus" → "Huas"
/// costs. It is Damerau-Levenshtein restricted to adjacent swaps — the
/// unrestricted version allows a substring to be edited and then transposed
/// again, which is not a typo anyone makes and costs a great deal more to
/// compute.
///
/// Plain Dart: no Flutter, no drift. Search runs this over a few hundred
/// trigram candidates per keystroke, so it is written to allocate two rows
/// rather than a matrix, and to give up as soon as the whole row is over the
/// budget.
library;

/// The OSA distance between [a] and [b], or a number greater than [limit] when
/// it is further than that.
///
/// [limit] is not an optimisation detail — it is the answer. Search only ever
/// asks "is this within 2 (or 3)", so the exact distance of a word twelve
/// edits away is worth nothing and costs a full matrix to find.
int editDistance(String a, String b, {int limit = 3}) {
  if (identical(a, b) || a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  // A length difference is a lower bound on the distance, so this is a real
  // answer rather than a shortcut: neither string can be reached from the
  // other in fewer edits than the characters they differ by.
  final over = limit + 1;
  if ((a.length - b.length).abs() > limit) return over;

  final source = a.codeUnits;
  final target = b.codeUnits;

  var twoBack = List<int>.filled(target.length + 1, 0);
  var previous = List<int>.generate(target.length + 1, (i) => i);
  var current = List<int>.filled(target.length + 1, 0);

  for (var i = 1; i <= source.length; i++) {
    current[0] = i;
    var best = current[0];

    for (var j = 1; j <= target.length; j++) {
      final substitution = source[i - 1] == target[j - 1] ? 0 : 1;
      var cost = _min3(
        current[j - 1] + 1,
        previous[j] + 1,
        previous[j - 1] + substitution,
      );

      if (i > 1 &&
          j > 1 &&
          source[i - 1] == target[j - 2] &&
          source[i - 2] == target[j - 1]) {
        final transposed = twoBack[j - 2] + 1;
        if (transposed < cost) cost = transposed;
      }

      current[j] = cost;
      if (cost < best) best = cost;
    }

    // Every alignment from here on only grows, so a whole row over budget
    // means the answer is over budget. This is what keeps a long query cheap
    // against four hundred candidates.
    if (best > limit) return over;

    final spare = twoBack;
    twoBack = previous;
    previous = current;
    current = spare;
  }

  final distance = previous[target.length];
  return distance > limit ? over : distance;
}

int _min3(int a, int b, int c) {
  final smaller = a < b ? a : b;
  return smaller < c ? smaller : c;
}
