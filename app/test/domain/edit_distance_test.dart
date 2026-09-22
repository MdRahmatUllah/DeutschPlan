@TestOn('vm')
library;

import 'package:deutschplan/domain/edit_distance.dart';
import 'package:flutter_test/flutter_test.dart';

/// `editDistance` — BR-SEARCH-03's OSA distance.
void main() {
  group('the four edits', () {
    test('an identical string is zero', () {
      expect(editDistance('haus', 'haus'), 0);
    });

    test('a substitution is one', () {
      expect(editDistance('haus', 'maus'), 1);
    });

    test('a deletion is one', () {
      expect(editDistance('haus', 'hus'), 1);
    });

    test('an insertion is one', () {
      expect(editDistance('hus', 'haus'), 1);
    });

    test('a transposition is one, not two', () {
      // This is the whole reason it is OSA and not Levenshtein: swapping two
      // letters is the commonest typo there is, and plain Levenshtein charges
      // two for it — which would push it out of BR-SEARCH-03's budget of 2
      // alongside any second mistake.
      expect(editDistance('haus', 'huas'), 1);
    });
  });

  group('the cases search actually hits', () {
    test('strase finds strasse', () {
      expect(editDistance('strase', 'strasse'), 1);
    });

    test('tur is one from tuer', () {
      expect(editDistance('tur', 'tuer'), 1);
    });

    test('an unrelated word is far', () {
      expect(editDistance('haus', 'entschuldigung'), greaterThan(3));
    });
  });

  group('the limit is the answer, not an optimisation', () {
    test('a distance inside the budget is exact', () {
      expect(editDistance('haus', 'mais', limit: 2), 2);
    });

    test('a distance outside it only has to be outside it', () {
      // The contract is "greater than limit", not a particular number: the
      // row-pruning returns as soon as the budget is blown, so the exact
      // distance is not computed and must not be relied on.
      expect(editDistance('haus', 'mais', limit: 1), greaterThan(1));
    });

    test('a length difference alone can blow the budget', () {
      expect(editDistance('haus', 'haushaltsgerat', limit: 3), greaterThan(3));
    });

    test('pruning does not cut a match short', () {
      // A long word where the middle rows are all at distance 2 and the last
      // row comes back to 2. If the pruning used the last cell rather than
      // the row minimum it would give up here.
      expect(editDistance('entschuldigung', 'entshculdigung', limit: 3), 1);
    });
  });

  group('the edges', () {
    test('an empty query is the length of the word', () {
      expect(editDistance('', 'haus', limit: 9), 4);
    });

    test('an empty word is the length of the query', () {
      expect(editDistance('haus', '', limit: 9), 4);
    });

    test('two empties are zero', () {
      expect(editDistance('', ''), 0);
    });

    test('it is symmetric', () {
      for (final pair in const <List<String>>[
        <String>['haus', 'maus'],
        <String>['strase', 'strasse'],
        <String>['huas', 'haus'],
        <String>['tur', 'tuer'],
      ]) {
        expect(
          editDistance(pair[0], pair[1]),
          editDistance(pair[1], pair[0]),
          reason: '${pair[0]} / ${pair[1]}',
        );
      }
    });

    test('a distance is never more than the longer string', () {
      expect(editDistance('abc', 'xyz', limit: 9), 3);
    });
  });

  test('four hundred candidates cost less than a frame', () {
    // The number search.md caps tier 3 at. The point is not the exact figure
    // but that the Dart half of a keystroke is nowhere near the 50 ms budget.
    final candidates = <String>[
      for (var i = 0; i < 400; i++) 'wohnungsgeberbestatigung$i',
    ];

    final watch = Stopwatch()..start();
    for (final candidate in candidates) {
      editDistance(candidate, 'wohnungsgeberbestatigung');
    }
    watch.stop();

    expect(watch.elapsedMilliseconds, lessThan(16));
  });
}
