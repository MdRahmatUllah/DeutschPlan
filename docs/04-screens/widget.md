# X1 · Home-screen widget

**Prototype.** `Widget` (small 2×2 and medium 4×2).

**Small.** Step "A2.1", ring, "8 left", "≈ 4 min". **Medium.** Ring "12/20", "8 left · A2.1", "Wort des Tages · die Wohnung · flat, apartment · ফ্ল্যাট", *Pronounce*. Done state: Lime check + tomorrow's preview. In the small size, tomorrow's preview runs under the ring across the widget's width, up to two lines: beside the ring, One UI's 2×2 left it some 50 dp and cut "Tomorrow · 7 revisions · 7…" (#1069). The widget picker shows a preview of the small size (`previewLayout`, Android 12+) rather than a placeholder tile (#1070).

**Functional requirements**
- FR-X1-01 Rendered from `widget_snapshot.json` written by the app (`03-domain/notifications-widget.md`); refreshed at midnight, after every session, hourly for the word.
- FR-X1-02 Taps: ring/count → `sogda://today`; word → `sogda://word/<uid>`; *Pronounce* → same link with `?speak=1` (the app plays on open, every time, whatever is on top: #442).
- FR-X1-03 Word of the day = a learned word due within 3 days, seeded by date; never a To-do word.
- FR-X1-04 Android: Glance widget + WorkManager refresh; iOS: WidgetKit timeline with hourly entries, App Group shared container. Respects the system light/dark; the glass theme renders as its opaque fallback on widgets.

**Tests.** snapshot writer; word-of-day selection.

**Built.** Android (#160): Glance, drawn from the snapshot, as `03-domain/notifications-widget.md` details. iOS: #161.
