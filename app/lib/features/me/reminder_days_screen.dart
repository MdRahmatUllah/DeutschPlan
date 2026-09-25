import 'dart:async';

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/features/me/settings_screen.dart'
    show settingsEditorProvider, settingsSourceProvider;
import 'package:deutschplan/features/onboarding/onboarding_pace_page.dart'
    show StudyDayToggle, studyWeekdays;
import 'package:deutschplan/features/today/today_providers.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/services/background_tasks.dart'
    show reminderBodyProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// M5 · Study days & reminder (`reminder-days.md`, the ReminderDays
/// artboards): the week's study days, the reminder and its time, *Only when
/// there is something to do*, and tonight's text as the task would write it.
class ReminderDaysScreen extends ConsumerStatefulWidget {
  const ReminderDaysScreen({super.key});

  @override
  ConsumerState<ReminderDaysScreen> createState() => _ReminderDaysState();
}

class _ReminderDaysState extends ConsumerState<ReminderDaysScreen> {
  /// The phone said no this visit: the switch stays off, and M5 says where
  /// to allow it (FR-M5-02).
  bool _blocked = false;

  /// FR-M5-02: asked when the switch goes on, as S2 page 5 asks.
  Future<void> _reminder({required bool on}) async {
    final editor = ref.read(settingsEditorProvider.notifier);
    if (!on) {
      setState(() => _blocked = false);
      return editor.set(SettingKeys.reminderEnabled, false);
    }
    // A request that throws was never answered: nothing changes.
    final bool allowed;
    try {
      allowed = await ref.read(notificationPermissionProvider).request();
    } on Object {
      return;
    }
    if (!mounted) return;
    setState(() => _blocked = !allowed);
    if (allowed) await editor.set(SettingKeys.reminderEnabled, true);
  }

  /// FR-M5-04: a new time reschedules the reminders and their compose
  /// (`ReminderScheduler` follows `reminder_time`).
  Future<void> _time(Clock current) async {
    final picked = await Adaptive.showTimePickerFor(
      context: context,
      initial: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null) return;
    await ref.read(settingsEditorProvider.notifier).set(
      SettingKeys.reminderTime,
      (hour: picked.hour, minute: picked.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(settingsEditorProvider);
    final settings = ref.watch(settingsSourceProvider);
    final editor = ref.read(settingsEditorProvider.notifier);
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;

    final mask = settings.read(SettingKeys.studyDaysMask);
    final on = settings.read(SettingKeys.reminderEnabled);
    final onlyWhenDue = settings.read(SettingKeys.reminderOnlyWhenDue);
    final clock = settings.read(SettingKeys.reminderTime);
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: clock.hour, minute: clock.minute),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

    final scaffold = AdaptiveScaffold(
      title: l10n.settingsStudyDays,
      leading: AdaptiveBackButton(
        label: l10n.settingsTitle,
        colour: context.isCupertino ? null : tokens.color.ink,
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          DpSurface(
            kind: DpSurfaceKind.bar,
            radius: 16,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _Heading(l10n.reminderDaysStudyDays),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    for (final (index, (short, full)) in studyWeekdays(
                      l10n,
                    ).indexed) ...<Widget>[
                      if (index > 0) const SizedBox(width: 6),
                      Expanded(
                        child: StudyDayToggle(
                          short: short,
                          full: full,
                          on: mask & (1 << index) != 0,
                          // FR-M5-01: the last study day stays.
                          onTap: () =>
                              unawaited(editor.studyDays(mask ^ (1 << index))),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Semantics(
                  container: true,
                  child: _Note(_restNote(context, mask)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          DpSurface(
            kind: DpSurfaceKind.bar,
            radius: 16,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _Row(
                  title: l10n.onboardingReminder,
                  subtitle: _blocked
                      ? l10n.onboardingReminderBlocked
                      : on
                      ? l10n.reminderDaysGranted
                      : l10n.onboardingReminderOff,
                  labelledByControl: true,
                  trailing: AdaptiveSwitch(
                    value: on,
                    onChanged: (value) => unawaited(_reminder(on: value)),
                    semanticLabel: l10n.onboardingReminder,
                  ),
                ),
                if (_blocked)
                  // Its own node: left to merge, the card takes its label and
                  // its tap, and a touch anywhere on the card reads it.
                  Semantics(
                    container: true,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: DpButton(
                        label: l10n.reminderDaysOpenSettings,
                        kind: DpButtonKind.text,
                        expand: false,
                        onPressed: () => unawaited(
                          ref
                              .read(notificationPermissionProvider)
                              .openSettings(),
                        ),
                      ),
                    ),
                  ),
                const _Hairline(),
                _Row(
                  title: l10n.reminderDaysTime,
                  semanticLabel: l10n.onboardingReminderTime(time),
                  onTap: () => unawaited(_time(clock)),
                  trailing: _Time(time),
                ),
                const _Hairline(),
                _Row(
                  title: l10n.reminderDaysOnlyWhenDue,
                  subtitle: l10n.reminderDaysOnlyWhenDueNote,
                  labelledByControl: true,
                  trailing: AdaptiveSwitch(
                    value: onlyWhenDue,
                    onChanged: (value) => unawaited(
                      editor.set(SettingKeys.reminderOnlyWhenDue, value),
                    ),
                    semanticLabel: l10n.reminderDaysOnlyWhenDue,
                  ),
                ),
              ],
            ),
          ),
          if (on) ...<Widget>[
            const SizedBox(height: 16),
            _Heading(l10n.reminderDaysTonight),
            const SizedBox(height: 8),
            _Preview(time: time, onlyWhenDue: onlyWhenDue),
            const SizedBox(height: 8),
            _Note(l10n.reminderDaysPreviewNote),
          ],
        ],
      ),
    );
    return tokens.isGlass
        ? AuroraBackdrop(leading: tokens.color.der, child: scaffold)
        : scaffold;
  }

  /// "Sunday is a rest day: …", "Saturday and Sunday are rest days: …", or
  /// every day a study day.
  static String _restNote(BuildContext context, int mask) {
    final l10n = AppLocalizations.of(context);
    // The pills' own full names, so both say the same in both languages.
    final names = studyWeekdays(l10n);
    final rest = <String>[
      for (var day = 0; day < 7; day++)
        if (mask & (1 << day) == 0) names[day].$2,
    ];
    if (rest.isEmpty) return l10n.reminderDaysEveryDay;
    final days = rest.length == 1
        ? rest.single
        : '${rest.sublist(0, rest.length - 1).join(', ')}'
              '${l10n.reminderDaysAnd}${rest.last}';
    return l10n.reminderDaysRest(rest.length, days);
  }
}

/// FR-M5-03: tonight's notification, from the composer `reminder_compose`
/// uses, over today's plan.
class _Preview extends ConsumerWidget {
  const _Preview({required this.time, required this.onlyWhenDue});

  final String time;
  final bool onlyWhenDue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final today = ref.watch(todayViewProvider).value;
    final body = ref.watch(reminderBodyProvider);
    if (today == null || !body.hasValue) return const SizedBox.shrink();
    final text = body.value;
    final lines = !today.isStudyDay
        ? <String>[l10n.reminderDaysRestToday]
        : text != null
        ? text.split('\n')
        : <String>[
            if (onlyWhenDue) l10n.reminderDaysNothing else l10n.reminderBody,
          ];

    return Semantics(
      container: true,
      child: DpSurface(
        kind: DpSurfaceKind.bar,
        radius: 16,
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // The app's icon, as the phone draws it beside a notification.
            ExcludeSemantics(
              child: SizedBox.square(
                dimension: 36,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.color.accent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: tokens.color.ink, width: 1.5),
                  ),
                  // An icon, not text: it keeps its size at 200 %.
                  child: Center(
                    child: MediaQuery.withNoTextScaling(
                      child: DpText(
                        'D',
                        role: DpTextRole.title,
                        color: tokens.color.onAccent,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DpText(
                    l10n.reminderDaysFrom(l10n.appTitle, time),
                    role: DpTextRole.label,
                    weight: 700,
                  ),
                  const SizedBox(height: 2),
                  for (final (index, line) in lines.indexed)
                    DpText(
                      line,
                      role: index == 0 ? DpTextRole.body : DpTextRole.caption,
                      color: index == 0 ? null : tokens.color.textSecondary,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "STUDY DAYS": small spaced capitals, a heading to a screen reader.
class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    header: true,
    child: DpText(
      text.toUpperCase(),
      role: DpTextRole.caption,
      weight: 700,
      letterSpacing: 0.6,
      color: context.tokens.color.textSecondary,
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => DpText(
    text,
    role: DpTextRole.caption,
    color: context.tokens.color.textSecondary,
  );
}

/// One of the reminder card's rows: a title, maybe a line under it, and the
/// control. Its own node, so a switch isn't merged into its neighbour's.
class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.trailing,
    this.subtitle,
    this.onTap,
    this.semanticLabel,
    this.labelledByControl = false,
  });

  final String title;
  final String? subtitle;
  final Widget trailing;

  /// The whole row's tap: the time row's picker.
  final VoidCallback? onTap;

  /// Read for a row that is one button, instead of its parts.
  final String? semanticLabel;

  /// The switch says the title, so the title isn't read twice (as M3's rows).
  final bool labelledByControl;

  @override
  Widget build(BuildContext context) {
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (labelledByControl)
                    ExcludeSemantics(
                      child: DpText(title, role: DpTextRole.body),
                    )
                  else
                    DpText(title, role: DpTextRole.body),
                  if (subtitle case final subtitle?) _Note(subtitle),
                ],
              ),
            ),
            const SizedBox(width: 12),
            trailing,
          ],
        ),
      ),
    );
    final onTap = this.onTap;
    return Semantics(
      container: true,
      button: onTap != null,
      label: semanticLabel,
      onTap: onTap,
      excludeSemantics: semanticLabel != null,
      child: onTap == null
          ? row
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: row,
            ),
    );
  }
}

/// "19:30": bold on Android, in an Oat pill on iOS, as the artboards draw it.
class _Time extends StatelessWidget {
  const _Time(this.time);

  final String time;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = DpText(time, role: DpTextRole.bodyLarge, weight: 600);
    return context.isCupertino
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: tokens.surface.muted,
              borderRadius: BorderRadius.circular(8),
            ),
            child: text,
          )
        : text;
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: context.tokens.surface.outline);
}
