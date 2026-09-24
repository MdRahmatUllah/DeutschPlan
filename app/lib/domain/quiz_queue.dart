import 'package:deutschplan/domain/answer_check.dart';
import 'package:deutschplan/domain/quiz_builder.dart';

/// The order a run asks its items in (FR-L8-03, BR-QUIZ-01): the quiz, then
/// each item not answered correctly, asked once more at the end. L9 counts a
/// typo as a mistake ("die Kausion"), so an almost is asked again too.
///
/// A re-ask is asked once whatever its answer: it goes to the back of no
/// queue, and it doesn't change the score.
class QuizQueue {
  QuizQueue(this.items);

  /// The quiz, in its order.
  final List<QuizItem> items;

  final List<QuizItem> _again = <QuizItem>[];
  int _at = 0;

  /// The item being asked.
  QuizItem get current =>
      _at < items.length ? items[_at] : _again[_at - items.length];

  /// Whether [current] is a re-ask, past the quiz itself.
  bool get reasking => _at >= items.length;

  /// A re-ask's place among them: (2, 4). Only while [reasking].
  (int, int) get reask => (_at - items.length + 1, _again.length);

  /// Records [current]'s verdict. A first answer that wasn't right is
  /// queued for the end.
  void answered(Verdict verdict) {
    if (!reasking && verdict != Verdict.correct) _again.add(_moved(current));
  }

  /// A re-ask's tiles each move one place, so it can't be answered by where
  /// the answer was. Articles keep der · die · das: that order is the
  /// layout, not a clue.
  static QuizItem _moved(QuizItem item) => item.options.length < 2
      ? item
      : QuizItem(
          ord: item.ord,
          wordUid: item.wordUid,
          direction: item.direction,
          prompt: item.prompt,
          expected: item.expected,
          options: <String>[...item.options.skip(1), item.options.first],
          form: item.form,
          hint: item.hint,
        );

  /// Moves to the next item; false when there is none.
  bool next() {
    if (_at + 1 >= items.length + _again.length) return false;
    _at++;
    return true;
  }
}
