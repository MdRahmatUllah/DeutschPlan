import 'package:deutschplan/domain/placement.dart';
import 'package:flutter_test/flutter_test.dart';

/// S3 · the placement check — #93. `placement.md`: "Unit: level walk with
/// scripted answers."
void main() {
  const steps = <String>[
    'A1.1', 'A1.2', 'A2.1', 'A2.2', 'B1.1', 'B1.2', //
    'B2.1', 'B2.2', 'C1.1', 'C1.2', 'C2.1', 'C2.2',
  ];

  /// Twelve words per step: four nouns with articles, four verbs, four
  /// adjectives — enough for four same-POS options, and each with an example
  /// that holds it.
  List<PlacementWord> poolFor(String step) => <PlacementWord>[
    for (var i = 0; i < 12; i++) wordFor(step, i),
  ];

  /// Plays [answers] (true = right) through a session, one item each.
  PlacementSession play(List<bool> answers, {int seed = 7}) {
    final session = PlacementSession(steps: steps, seed: seed);
    for (final right in answers) {
      if (session.finished) break;
      final item = session.next(poolFor(session.step))!;
      session.answer(item, correct: right);
    }
    return session;
  }

  const r = true;
  const w = false;

  group('FR-S3-01 the walk', () {
    test('starts at A1.1', () {
      expect(PlacementSession(steps: steps, seed: 1).step, 'A1.1');
    });

    test('two right in a row move up a step', () {
      expect(play(<bool>[r]).step, 'A1.1', reason: 'one is not enough');
      expect(play(<bool>[r, r]).step, 'A1.2');
      expect(play(<bool>[r, r, r, r]).step, 'A2.1');
    });

    test('two wrong in a row move down a step', () {
      expect(play(<bool>[r, r, r, r, w]).step, 'A2.1');
      expect(play(<bool>[r, r, r, r, w, w]).step, 'A1.2');
    });

    test('and never below the first step or above the last', () {
      expect(play(<bool>[w, w, w, w]).step, 'A1.1');

      // Twenty right climb ten steps, so the ceiling needs a shorter course
      // to show: two steps, and six right answers.
      final short = PlacementSession(
        steps: const <String>['C2.1', 'C2.2'],
        seed: 1,
      );
      for (var i = 0; i < 6; i++) {
        short.answer(short.next(poolFor(short.step))!, correct: true);
      }
      expect(short.step, 'C2.2');
    });

    test('a right and a wrong in turn hold the step', () {
      // The streak counts *consecutive* answers; alternating resets both.
      expect(play(<bool>[r, w, r, w, r, w]).step, 'A1.1');
    });

    test('stops after 20', () {
      // Right, right climbs; wrong, wrong falls: never three items at one
      // step, so only the limit stops it.
      final session = play(<bool>[for (var i = 0; i < 30; i++) i % 4 < 2]);
      expect(session.answered, 20);
      expect(session.finished, isTrue);
    });

    test('or after 8, once the step has held for 3', () {
      // Six climbing, then alternating at A2.2 from the seventh.
      final session = play(<bool>[r, r, r, r, r, r, r, w, r, w, r]);
      expect(session.answered, 9);
      expect(session.finished, isTrue);
      expect(session.step, 'A2.2');
    });

    test('but not before 8, however steady', () {
      final session = PlacementSession(steps: steps, seed: 1);
      for (final right in <bool>[r, w, r, w, r, w, r]) {
        session.answer(session.next(poolFor(session.step))!, correct: right);
      }
      expect(session.answered, 7);
      expect(session.finished, isFalse);
    });

    test('the result suggests where the walk ended', () {
      final result = play(<bool>[r, r, r, r, r, r, r, w, r, w, r]).result();
      expect(result.step, 'A2.2');
      expect((result.correct, result.answered), (8, 9));
    });
  });

  group('FR-S3-02 the items', () {
    List<String> drawn(int seed) {
      final session = PlacementSession(steps: steps, seed: seed);
      return <String>[
        for (var i = 0; i < 6; i++)
          () {
            final item = session.next(poolFor(session.step))!;
            session.answer(item, correct: i.isEven);
            return '${item.word.uid} ${item.options.join('|')}';
          }(),
      ];
    }

    test('the same seed draws the same items in the same order', () {
      expect(drawn(42), drawn(42));
    });

    test('and another seed draws others', () {
      expect(drawn(42), isNot(drawn(43)));
    });

    test('the wrong options share the right one\'s part of speech', () {
      final session = PlacementSession(steps: steps, seed: 3);
      final pool = poolFor('A1.1');
      final byMeaning = <String, String>{
        for (final w in pool) w.english: w.pos,
        for (final w in pool) w.german: w.pos,
      };
      for (var i = 0; i < 9; i++) {
        final item = session.next(pool)!;
        session.answer(item, correct: false);
        if (item.kind == PlacementKind.article) continue;
        for (final option in item.options) {
          expect(byMeaning[option], item.word.pos, reason: option);
        }
      }
    });

    test('an article item asks der, die or das of a noun', () {
      final session = PlacementSession(steps: steps, seed: 5);
      PlacementItem? article;
      for (var i = 0; i < 6 && article == null; i++) {
        final item = session.next(poolFor(session.step))!;
        if (item.kind == PlacementKind.article) article = item;
        session.answer(item, correct: false);
      }

      expect(article, isNotNull);
      expect(article!.options, <String>['der', 'die', 'das']);
      expect(article.options[article.answer], article.word.article);
    });

    test('a gap item blanks the word in its own sentence', () {
      final session = PlacementSession(steps: steps, seed: 5);
      PlacementItem? gap;
      for (var i = 0; i < 6 && gap == null; i++) {
        final item = session.next(poolFor(session.step))!;
        if (item.kind == PlacementKind.gap) gap = item;
        session.answer(item, correct: false);
      }

      expect(gap!.sentence, contains('___'));
      expect(gap.sentence, isNot(contains(gap.word.german)));
      expect(gap.options[gap.answer], gap.word.german);
    });

    test('a word the sentence has conjugated is not a gap', () {
      // "gehen" does not appear in "Ich gehe nach Hause", and blanking the
      // wrong word would give the answer away.
      final session = PlacementSession(steps: steps, seed: 1);
      final pool = <PlacementWord>[
        for (var i = 0; i < 6; i++)
          PlacementWord(
            uid: 'v$i',
            german: 'gehen$i',
            english: 'go $i',
            pos: 'verb',
            examples: const <String>['Ich gehe nach Hause.'],
          ),
      ];
      for (var i = 0; i < 6; i++) {
        final item = session.next(pool)!;
        expect(item.kind, isNot(PlacementKind.gap));
        session.answer(item, correct: false);
      }
    });

    test('a word spelt like another is never asked alone', () {
      // "Ihr" (your) is also "ihr" (you all) at the top of a question with
      // nothing round it. The real A1.1 has both.
      final session = PlacementSession(steps: steps, seed: 4);
      final pool = <PlacementWord>[
        const PlacementWord(
          uid: 'ihr',
          german: 'ihr',
          english: 'you all',
          pos: 'pron',
        ),
        const PlacementWord(
          uid: 'Ihr',
          german: 'Ihr',
          english: 'your',
          pos: 'pron',
        ),
        for (var i = 0; i < 8; i++)
          PlacementWord(
            uid: 'p$i',
            german: 'pron$i',
            english: 'p $i',
            pos: 'pron',
          ),
      ];
      for (var i = 0; i < 8; i++) {
        final item = session.next(pool)!;
        expect(item.word.german.toLowerCase(), isNot('ihr'), reason: '$i');
        session.answer(item, correct: false);
      }
    });

    test('and a gap never offers the answer in another case', () {
      // Built so the third item — the gap turn — can only be "Morgen", and
      // so that were "morgen" allowed as a wrong option it would have to be
      // one: it is one of only three other nouns.
      final session = PlacementSession(steps: steps, seed: 4);
      final pool = <PlacementWord>[
        const PlacementWord(
          uid: 'Morgen',
          german: 'Morgen',
          english: 'morning',
          pos: 'noun',
          examples: <String>['Guten Morgen!'],
        ),
        const PlacementWord(
          uid: 'morgen',
          german: 'morgen',
          english: 'tomorrow',
          pos: 'noun',
        ),
        const PlacementWord(
          uid: 'a',
          article: 'der',
          german: 'Tisch',
          english: 'table',
          pos: 'noun',
        ),
        const PlacementWord(
          uid: 'b',
          article: 'die',
          german: 'Tür',
          english: 'door',
          pos: 'noun',
        ),
        const PlacementWord(
          uid: 'v',
          german: 'gehen',
          english: 'go',
          pos: 'verb',
        ),
        const PlacementWord(
          uid: 'w',
          german: 'essen',
          english: 'eat',
          pos: 'verb',
        ),
      ];

      session
        ..answer(session.next(pool)!, correct: false)
        ..answer(session.next(pool)!, correct: false);
      final gap = session.next(pool)!;

      expect((gap.kind, gap.word.uid), (PlacementKind.gap, 'Morgen'));
      expect(
        gap.options.where((o) => o.toLowerCase() == 'morgen'),
        hasLength(1),
      );
    });

    test('no word is asked twice', () {
      final session = PlacementSession(steps: steps, seed: 9);
      final seen = <String>{};
      for (var i = 0; i < 10; i++) {
        final item = session.next(poolFor('A1.1'))!;
        expect(seen.add(item.word.uid), isTrue, reason: item.word.uid);
        session.answer(item, correct: i.isEven);
      }
    });
  });

  group('the breakdown', () {
    test('groups word items by level and articles apart', () {
      final result = play(<bool>[
        r, r, r, r, r, r, r, w, r, w, r, //
      ]).result();

      final areas = <String, (int, int)>{
        for (final a in result.areas) a.area: (a.correct, a.total),
      };
      final total = areas.values.fold(0, (sum, a) => sum + a.$2);
      expect(total, result.answered);
      expect(areas.keys.first, 'A1', reason: 'levels in course order');
      expect(areas.keys.last, PlacementSession.articles);
    });
  });
}

PlacementWord wordFor(String step, int i) {
  final (pos, stem) = switch (i ~/ 4) {
    0 => ('noun', 'Nomen'),
    1 => ('verb', 'verb'),
    _ => ('adj', 'adj'),
  };
  final german = '$stem$step$i';
  return PlacementWord(
    uid: '$step-$i',
    article: pos == 'noun'
        ? const <String>['der', 'die', 'das', 'die'][i]
        : null,
    german: german,
    english: 'meaning $step $i',
    pos: pos,
    examples: <String>['Ein Satz mit $german darin.'],
  );
}
