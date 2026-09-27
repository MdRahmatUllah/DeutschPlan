/// The reminders ahead of [now] (`notifications-widget.md`): [hour]:[minute]
/// local on each study day of [studyDaysMask] (Monday the lowest bit, as
/// `study_days_mask`), over the next [days] days. Today's is there only
/// while it is still to come.
///
/// One local time per date rather than a weekly repeat: each is 19:30 on its
/// own day, so a daylight-saving change can't move it by an hour.
///
/// [todayMask] is the study days today was planned with, once it has been
/// (BR-PLAN-08): a change to the study days applies from tomorrow, so today
/// keeps its reminder, or keeps its rest, as its plan does (#751).
List<DateTime> reminderTimes({
  required DateTime now,
  required int hour,
  required int minute,
  required int studyDaysMask,
  int? todayMask,
  int days = 7,
}) => <DateTime>[
  for (var day = 0; day <= days; day++)
    if (DateTime(now.year, now.month, now.day + day, hour, minute) case final at
        when at.isAfter(now) &&
            at.isBefore(now.add(Duration(days: days))) &&
            (day == 0 ? todayMask ?? studyDaysMask : studyDaysMask) &
                    (1 << (at.weekday - 1)) !=
                0)
      at,
];
