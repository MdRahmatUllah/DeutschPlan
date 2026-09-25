/// The reminders ahead of [now] (`notifications-widget.md`): [hour]:[minute]
/// local on each study day of [studyDaysMask] (Monday the lowest bit, as
/// `study_days_mask`), over the next [days] days. Today's is there only
/// while it is still to come.
///
/// One local time per date rather than a weekly repeat: each is 19:30 on its
/// own day, so a daylight-saving change can't move it by an hour.
List<DateTime> reminderTimes({
  required DateTime now,
  required int hour,
  required int minute,
  required int studyDaysMask,
  int days = 7,
}) => <DateTime>[
  for (var day = 0; day <= days; day++)
    if (DateTime(now.year, now.month, now.day + day, hour, minute) case final at
        when at.isAfter(now) &&
            at.isBefore(now.add(Duration(days: days))) &&
            studyDaysMask & (1 << (at.weekday - 1)) != 0)
      at,
];
