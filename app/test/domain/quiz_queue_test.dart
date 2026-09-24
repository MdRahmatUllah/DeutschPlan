import 'package:deutschplan/domain/answer_check.dart';
import 'package:deutschplan/domain/quiz_builder.dart';
import 'package:deutschplan/domain/quiz_queue.dart';
import 'package:flutter_test/flutter_test.dart';

/// FR-L8-03 / BR-QUIZ-01: the re-ask queue (#125).
void main() {
  QuizItem item(int ord) => QuizItem(
    ord: ord,
    wordUid: 'w$ord',
    direction: QuizDirection.deEn,
    prompt: 'p$ord',
    expected: 'e$ord',
  );

  /// Runs [queue] to its end, answering each item with [verdicts] (by ord,
  /// first answer then re-ask), and returns the ords in the order asked.
  List<int> run(QuizQueue queue, Map<int, List<Verdict>> verdicts) {
    final asked = <int>[];
    final seen = <int, int>{};
    do {
      final ord = queue.current.ord;
      asked.add(ord);
      final n = seen[ord] = (seen[ord] ?? 0) + 1;
      final given = verdicts[ord] ?? const <Verdict>[];
      queue.answered(n <= given.length ? given[n - 1] : Verdict.correct);
    } while (queue.next());
    return asked;
  }

  test('FR-L8-03 all right: nothing is asked again', () {
    final queue = QuizQueue([item(1), item(2), item(3)]);
    expect(run(queue, const {}), [1, 2, 3]);
  });

  test('FR-L8-03 each item not right is asked once more, at the end, in '
      'order', () {
    final queue = QuizQueue([item(1), item(2), item(3), item(4)]);
    expect(
      run(queue, const {
        2: [Verdict.wrong],
        3: [Verdict.almost],
        4: [Verdict.wrongArticle],
      }),
      [1, 2, 3, 4, 2, 3, 4],
    );
  });

  test('FR-L8-03 a re-ask wrong again is not asked a third time', () {
    final queue = QuizQueue([item(1), item(2)]);
    expect(
      run(queue, const {
        1: [Verdict.wrong, Verdict.wrong],
        2: [Verdict.wrong, Verdict.wrong],
      }),
      [1, 2, 1, 2],
    );
  });

  test('a re-ask knows its place among them', () {
    final queue = QuizQueue([item(1), item(2), item(3)]);
    queue
      ..answered(Verdict.wrong)
      ..next();
    expect(queue.reasking, isFalse);
    queue
      ..answered(Verdict.wrong)
      ..next()
      ..answered(Verdict.correct);
    expect(queue.next(), isTrue);
    expect((queue.reasking, queue.current.ord, queue.reask), (true, 1, (1, 2)));
    queue
      ..answered(Verdict.wrong)
      ..next();
    expect((queue.current.ord, queue.reask), (2, (2, 2)));
    expect(queue.next(), isFalse);
  });

  test('FR-L8-03 a re-asked item is the same question, its tiles moved', () {
    const tiles = QuizItem(
      ord: 1,
      wordUid: 'haus',
      direction: QuizDirection.deBn,
      prompt: 'das Haus',
      expected: 'বাড়ি',
      options: <String>['গাড়ি', 'বাড়ি', 'দরজা', 'রাস্তা'],
    );
    final queue = QuizQueue(<QuizItem>[tiles])..answered(Verdict.wrong);
    expect(queue.next(), isTrue);
    final again = queue.current;
    expect(
      (again.ord, again.wordUid, again.prompt, again.expected, again.tiles),
      (1, 'haus', 'das Haus', 'বাড়ি', true),
    );
    expect(again.options.toSet(), tiles.options.toSet());
    for (var i = 0; i < tiles.options.length; i++) {
      expect(again.options[i], isNot(tiles.options[i]), reason: 'tile $i');
    }
  });

  test('an empty quiz has nothing to move to', () {
    expect(QuizQueue(const <QuizItem>[]).next(), isFalse);
  });
}
