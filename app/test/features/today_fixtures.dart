import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/features/today/today_providers.dart';
import 'package:deutschplan/features/today/today_view.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// The Today artboard's values: 12 of 20 done, A2.1, day 34, a backlog from
/// Tuesday to Wednesday and Konjunktiv II this week.
TodayView artboardToday({
  int reviseDone = 10,
  int newDone = 2,
  int backlog = 14,
  int grammarDue = 0,
  int sentencesDone = 0,
  bool isStudyDay = true,
  int courseDay = 34,
  String? learnerName = 'Maruf',
}) => TodayView(
  date: '2026-09-21',
  hour: 8,
  revise: BlockProgress(done: reviseDone, total: 10),
  newToday: BlockProgress(done: newDone, total: 7),
  openRevise: <String>[for (var i = reviseDone; i < 10; i++) 'r$i'],
  openNew: <String>[for (var i = newDone; i < 7; i++) 'n$i'],
  grammarDue: <String>[for (var i = 0; i < grammarDue; i++) 'g$i'],
  sentences: BlockProgress(done: sentencesDone, total: 3),
  isStudyDay: isStudyDay,
  backlog: backlog,
  backlogFrom: backlog == 0 ? null : '2026-09-15',
  backlogTo: backlog == 0 ? null : '2026-09-16',
  streak: 12,
  estimate: const Duration(minutes: 6),
  courseDay: courseDay,
  stepWords: (done: 184, learning: 60, todo: 296, total: 540),
  step: 'A2.1',
  learnerName: learnerName,
  newCategory: 'Wohnen & Haushalt',
  grammar: const GrammarPreview(
    uid: 'konj2',
    topic: 'Konjunktiv II – Höflichkeit',
    rule: 'Könnten Sie …? — polite requests with könnte and würde',
  ),
);

/// The TodayDone artboard: 20 of 20, day 34 · 17 words · 12 min, and a
/// Tomorrow of 12 revisions, 7 new and one grammar topic.
TodayView artboardDone({int backlog = 0, TomorrowPreview? tomorrow}) =>
    TodayView(
      date: '2026-09-21',
      hour: 19,
      revise: const BlockProgress(done: 10, total: 10),
      newToday: const BlockProgress(done: 7, total: 7),
      openRevise: const <String>[],
      openNew: const <String>[],
      grammarDue: const <String>[],
      sentences: const BlockProgress(done: 3, total: 3),
      backlog: backlog,
      streak: 13,
      estimate: Duration.zero,
      courseDay: 34,
      minutes: 12,
      stepWords: (done: 191, learning: 60, todo: 289, total: 540),
      step: 'A2.1',
      learnerName: 'Maruf',
      grammar: const GrammarPreview(
        uid: 'konj2',
        topic: 'Konjunktiv II – Höflichkeit',
        rule: 'Könnten Sie …? — polite requests with könnte and würde',
      ),
      tomorrow:
          tomorrow ??
          const TomorrowPreview(
            revise: 12,
            newWords: 7,
            grammar: 1,
            estimate: Duration(minutes: 13),
            category: 'Wohnen & Haushalt',
          ),
    );

/// The TodayRest artboard: Sunday the 27th off, six revisions optional, and
/// twelve due tomorrow if they are left alone.
TodayView artboardRest({int reviseDone = 0}) => TodayView(
  date: '2026-09-27',
  hour: 10,
  revise: BlockProgress(done: reviseDone, total: 6),
  newToday: BlockProgress.none,
  openRevise: <String>[for (var i = reviseDone; i < 6; i++) 'r$i'],
  openNew: const <String>[],
  grammarDue: const <String>[],
  sentences: const BlockProgress(done: 0, total: 3),
  isStudyDay: false,
  backlog: 0,
  streak: 12,
  estimate: const Duration(minutes: 3),
  courseDay: 40,
  stepWords: (done: 191, learning: 60, todo: 289, total: 540),
  step: 'A2.1',
  learnerName: 'Maruf',
  dueTomorrow: 12,
  grammar: const GrammarPreview(
    uid: 'konj2',
    topic: 'Konjunktiv II – Höflichkeit',
    rule: 'Könnten Sie …? — polite requests with könnte and würde',
  ),
);

/// Today without a database: the artboard's plan, and no coach mark.
///
/// For tests about something else — the router, the shell — that only need
/// the first tab to draw.
List<Override> todayStub([TodayView? view]) => <Override>[
  todayViewProvider.overrideWith((ref) async => view ?? artboardToday()),
  coachMarkProvider.overrideWithValue(false),
];
