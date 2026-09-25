import 'package:deutschplan/domain/plan_engine.dart'
    show PlanDate, addDays, parsePlanDate, planDate;

/// M2's three views (`progress.md`).
enum ProgressRange { week, month, all }

/// One bar of M2's chart: the revisions and new words of a day (or, for
/// All, a month).
typedef ProgressBar = ({PlanDate start, int reviews, int newWords});

/// What `daily_stats` says about a day: the two counts the chart draws.
typedef DayCounts = ({PlanDate day, int reviews, int newWords});

/// The days M2's Week and Month draw: this week Monday to Sunday, or the
/// last 30 days to [today].
List<PlanDate> rangeDays(ProgressRange range, PlanDate today) {
  final date = parsePlanDate(today);
  return switch (range) {
    ProgressRange.week => <PlanDate>[
      for (var i = 0; i < 7; i++)
        addDays(today, i - (date.weekday - DateTime.monday)),
    ],
    ProgressRange.month => <PlanDate>[
      for (var i = 29; i >= 0; i--) addDays(today, -i),
    ],
    ProgressRange.all => const <PlanDate>[],
  };
}

/// The bars: a day each for Week and Month; for All, a month each from the
/// first day with anything done to [today]'s month.
List<ProgressBar> progressBars(
  ProgressRange range,
  PlanDate today,
  List<DayCounts> days,
) {
  final byDay = <PlanDate, DayCounts>{for (final d in days) d.day: d};
  if (range != ProgressRange.all) {
    return <ProgressBar>[
      for (final day in rangeDays(range, today))
        (
          start: day,
          reviews: byDay[day]?.reviews ?? 0,
          newWords: byDay[day]?.newWords ?? 0,
        ),
    ];
  }
  final active = days.where((d) => d.reviews + d.newWords > 0).toList()
    ..sort((a, b) => a.day.compareTo(b.day));
  if (active.isEmpty) return const <ProgressBar>[];
  final first = parsePlanDate(active.first.day);
  final last = parsePlanDate(today);
  return <ProgressBar>[
    for (
      var month = DateTime.utc(first.year, first.month);
      !month.isAfter(DateTime.utc(last.year, last.month));
      month = DateTime.utc(month.year, month.month + 1)
    )
      (
        start: planDate(month),
        reviews: _sum(active, month, (d) => d.reviews),
        newWords: _sum(active, month, (d) => d.newWords),
      ),
  ];
}

int _sum(List<DayCounts> days, DateTime month, int Function(DayCounts) of) =>
    days
        .where((d) => d.day.startsWith(planDate(month).substring(0, 8)))
        .fold(0, (sum, d) => sum + of(d));

/// FR-M2-01: the share of revision ratings that remembered — Hard, Good or
/// Easy (2 and up) — or null when there were none.
double? retention(Iterable<int> ratings) {
  var all = 0;
  var remembered = 0;
  for (final rating in ratings) {
    all++;
    if (rating >= 2) remembered++;
  }
  return all == 0 ? null : remembered / all;
}

/// M2 shows retention only after 30 days of data (`progress.md`): the first
/// day anything was done is at least 30 days before [today].
bool retentionReady(PlanDate? firstDay, PlanDate today) =>
    firstDay != null && addDays(firstDay, 30).compareTo(today) <= 0;
