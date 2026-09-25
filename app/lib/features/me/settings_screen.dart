import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_slider.dart';
import 'package:deutschplan/core/components/dp_stepper.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/model_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/domain/fsrs.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/router/cross_tab.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'settings_screen.g.dart';

/// The settings M3 reads and writes: the app's own. A provider of M3's so a
/// test that only needs it drawn — the router's — can give it settings
/// without a database, as M1's `meView` does.
@riverpod
SettingsRepository settingsSource(Ref ref) => ref.watch(settingsProvider);

/// FR-M3-01's input, read once while M3 is open: the slider re-sums these as
/// it moves rather than asking the database again.
@riverpod
Future<List<double>> learnedStabilities(Ref ref) =>
    ref.watch(wordRepositoryProvider).learnedStabilities();

/// The translation model's state, for its row's subtitle and FR-M3-03. Null
/// when the manifest has no such model.
///
/// ponytail: read once per visit; #156's manager is what makes a download's
/// percentage move while M3 is open.
@riverpod
Future<ModelState?> translationModel(Ref ref) async {
  final models = ref.watch(modelRepositoryProvider);
  final entry = (await models.manifest()).model(
    ModelRepository.translationModel,
  );
  if (entry == null || entry.variants.isEmpty) return null;
  final chosen = SettingKeys.mtVariant.encode(
    ref.watch(settingsSourceProvider).read(SettingKeys.mtVariant),
  );
  final variant = entry.variants.firstWhere(
    (variant) => variant.id == chosen,
    orElse: () => entry.variants.first,
  );
  return models.stateOf(entry, variant);
}

/// M3's writes, and what redraws it: the state counts the settings changed,
/// here or anywhere else, since M3 opened.
@riverpod
class SettingsEditor extends _$SettingsEditor {
  @override
  int build() {
    final changes = ref
        .watch(settingsSourceProvider)
        .changes
        .listen((_) => state++);
    ref.onDispose(changes.cancel);
    return 0;
  }

  /// Saved at once: M3 has no *Save*.
  Future<void> set<T>(SettingKey<T> key, T value) =>
      ref.read(settingsSourceProvider).write(key, value);

  /// *New words per day* reaches the open enrollment too, which is where
  /// the plan engine reads the pace (BR-PLAN-08).
  Future<void> dailyNew(int count) =>
      ref.read(setupRepositoryProvider).setDailyNew(count);

  /// M5's study days (#147) reach the open enrollment too, for the same
  /// reason. FR-M5-01: the last one can't go.
  Future<void> studyDays(int mask) async {
    if (mask & 127 == 0) return;
    await ref
        .read(setupRepositoryProvider)
        .setStudyDays(mask, today: ref.read(todayProvider));
  }

  /// FR-M3-03: on only once the model is ready. False otherwise, with the
  /// switch left off, and M3 opens M4 to get it.
  Future<bool> translation({required bool on}) async {
    if (on) {
      final model = await ref.read(translationModelProvider.future);
      // An update waiting still leaves the old model whole on disk.
      final usable =
          model != null &&
          (model.isReady || model.status == ModelStatus.updateAvailable);
      if (!usable) return false;
    }
    await set(SettingKeys.mtEnabled, on);
    return true;
  }
}

/// M3 · Settings: every learner-facing setting, in eight groups
/// (`settings.md`). Material headers on Android, inset groups on iOS.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  /// The ranges `settings.md` gives each stepper and slider.
  static const dailyNew = (min: 1, max: 50);
  static const reviseCount = (min: 0, max: 100);
  static const sentenceCount = (min: 0, max: 20);
  static const doneDays = (min: 3, max: 60);
  static const unlockPercent = (min: 50, max: 100);
  static const passPercent = (min: 50, max: 90);

  /// Speech speed in quarters: 0.5× to 1.5×, around the 1.0× the artboard
  /// draws at the middle, on the grid the study menu's 0.75 / 1 / 1.25 use.
  static const speed = (min: 2, max: 6);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(settingsEditorProvider);
    final settings = ref.watch(settingsSourceProvider);
    final editor = ref.read(settingsEditorProvider.notifier);
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;

    Future<void> set<T>(SettingKey<T> key, T value) => editor.set(key, value);
    Widget toggle(BoolSetting key, String label) => AdaptiveSwitch(
      value: settings.read(key),
      onChanged: (on) => set(key, on),
      semanticLabel: label,
    );

    final retention = (settings.read(SettingKeys.desiredRetention) * 100)
        .round();
    final stabilities = ref.watch(learnedStabilitiesProvider).value;
    final model = ref.watch(translationModelProvider).value;
    final meaning = settings.read(SettingKeys.meaningLanguage);
    final ui = settings.read(SettingKeys.uiLanguage);
    final theme = settings.read(SettingKeys.themeMode);
    final unlock = settings.read(SettingKeys.examUnlockPercent);
    final pass = settings.read(SettingKeys.examPassPercent);
    final speedQuarters = (settings.read(SettingKeys.ttsSpeed) * 4).round();

    String meaningName(MeaningLanguage language) => switch (language) {
      MeaningLanguage.english => l10n.settingsEnglish,
      MeaningLanguage.bangla => l10n.settingsBangla,
      MeaningLanguage.both => l10n.settingsBoth,
    };
    String uiName(UiLanguage language) => switch (language) {
      UiLanguage.english => l10n.settingsEnglish,
      UiLanguage.bangla => l10n.settingsBangla,
    };
    String themeName(ThemeModeSetting mode) => switch (mode) {
      ThemeModeSetting.system => l10n.settingsThemeSystem,
      ThemeModeSetting.light => l10n.settingsThemeLight,
      ThemeModeSetting.dark => l10n.settingsThemeDark,
      ThemeModeSetting.glass => l10n.settingsThemeGlass,
    };
    List<(int, String)> percents(({int min, int max}) range) => <(int, String)>[
      for (var p = range.min; p <= range.max; p += 5)
        (p, l10n.settingsPercent(p)),
    ];

    final scaffold = AdaptiveScaffold(
      title: l10n.settingsTitle,
      leading: AdaptiveBackButton(
        label: l10n.tabMe,
        // Ink on Android, the link colour beside "Me" on iOS: both artboards.
        colour: context.isCupertino ? null : tokens.color.ink,
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      // Glass has no paper of its own: the aurora is, led by Cobalt as the
      // glass artboards draw it.
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: <Widget>[
          _Group(
            title: l10n.settingsGroupDailyPlan,
            rows: <Widget>[
              _Row(
                title: l10n.settingsDailyNew,
                subtitle: l10n.settingsFromTomorrow,
                trailing: _stepper(
                  settings,
                  SettingKeys.dailyNew,
                  dailyNew,
                  l10n.settingsDailyNewDecrease,
                  l10n.settingsDailyNewIncrease,
                  <T>(key, value) => editor.dailyNew(value as int),
                ),
              ),
              _Row(
                title: l10n.settingsReviseCount,
                subtitle: l10n.settingsFromTomorrow,
                trailing: _stepper(
                  settings,
                  SettingKeys.reviseCount,
                  reviseCount,
                  l10n.settingsReviseCountDecrease,
                  l10n.settingsReviseCountIncrease,
                  set,
                ),
              ),
              _Row(
                title: l10n.settingsSentenceCount,
                trailing: _stepper(
                  settings,
                  SettingKeys.sentenceCount,
                  sentenceCount,
                  l10n.settingsSentenceCountDecrease,
                  l10n.settingsSentenceCountIncrease,
                  set,
                ),
              ),
              _Row(
                title: l10n.settingsStudyDays,
                subtitle: _studyDays(context, settings),
                onTap: () => context.jumpToTab(const ReminderSettingsRoute()),
              ),
              _Row(
                title: l10n.settingsAutoAdvance,
                labelledByControl: true,
                trailing: toggle(
                  SettingKeys.autoAdvance,
                  l10n.settingsAutoAdvance,
                ),
              ),
              _Row(
                title: l10n.settingsPauseNew,
                subtitle: l10n.settingsPauseNewNote,
                labelledByControl: true,
                trailing: toggle(
                  SettingKeys.pauseNewWhenBacklog,
                  l10n.settingsPauseNew,
                ),
              ),
            ],
          ),
          _Group(
            title: l10n.settingsGroupRevision,
            rows: <Widget>[
              _Row(
                title: l10n.settingsRetention,
                subtitle: stabilities == null
                    ? l10n.settingsPercent(retention)
                    : l10n.settingsRetentionLine(
                        retention,
                        Fsrs(desiredRetention: retention / 100)
                            .reviewsPerDay(stabilities)
                            .round(),
                      ),
                labelledByControl: true,
                trailing: _slider(
                  DpSlider(
                    value: retention,
                    min: (Fsrs.minRetention * 100).round(),
                    max: (Fsrs.maxRetention * 100).round(),
                    compact: true,
                    label: l10n.settingsRetention,
                    describe: l10n.settingsPercent,
                    onChanged: (percent) =>
                        set(SettingKeys.desiredRetention, percent / 100),
                  ),
                ),
              ),
              _Row(
                title: l10n.settingsDoneDays(
                  settings.read(SettingKeys.doneStabilityDays),
                ),
                trailing: _stepper(
                  settings,
                  SettingKeys.doneStabilityDays,
                  doneDays,
                  l10n.settingsDoneDaysDecrease,
                  l10n.settingsDoneDaysIncrease,
                  set,
                ),
              ),
              _Row(
                title: l10n.settingsSwipeToRate,
                subtitle: l10n.settingsSwipeToRateNote,
                labelledByControl: true,
                trailing: toggle(
                  SettingKeys.swipeToRate,
                  l10n.settingsSwipeToRate,
                ),
              ),
              _Row(
                title: l10n.settingsQuizCustomWords,
                subtitle: l10n.settingsQuizCustomWordsNote,
                labelledByControl: true,
                trailing: toggle(
                  SettingKeys.quizCustomWords,
                  l10n.settingsQuizCustomWords,
                ),
              ),
            ],
          ),
          _Group(
            title: l10n.settingsGroupDisplay,
            rows: <Widget>[
              _Row(
                title: l10n.settingsMeaning,
                value: meaningName(meaning),
                onTap: () async {
                  final chosen = await _choose(
                    context,
                    l10n.settingsMeaning,
                    <(MeaningLanguage, String)>[
                      for (final language in MeaningLanguage.values)
                        (language, meaningName(language)),
                    ],
                    meaning,
                  );
                  if (chosen != null) {
                    await ref
                        .read(languagesProvider.notifier)
                        .setMeaning(chosen);
                  }
                },
              ),
              _Row(
                title: l10n.settingsUiLanguage,
                value: uiName(ui),
                onTap: () async {
                  final chosen = await _choose(
                    context,
                    l10n.settingsUiLanguage,
                    <(UiLanguage, String)>[
                      for (final language in UiLanguage.values)
                        (language, uiName(language)),
                    ],
                    ui,
                  );
                  if (chosen != null) {
                    await ref.read(languagesProvider.notifier).setUi(chosen);
                  }
                },
              ),
              _Row(
                title: l10n.settingsTheme,
                value: themeName(theme),
                onTap: () async {
                  final chosen = await _choose(
                    context,
                    l10n.settingsTheme,
                    <(ThemeModeSetting, String)>[
                      for (final mode in ThemeModeSetting.values)
                        (mode, themeName(mode)),
                    ],
                    theme,
                  );
                  // FR-M3-02: through the notifier every frame reads.
                  if (chosen != null) {
                    await ref.read(themeProvider.notifier).choose(chosen);
                  }
                },
              ),
              _Row(
                title: l10n.settingsShowPronBn,
                labelledByControl: true,
                trailing: toggle(
                  SettingKeys.showPronBn,
                  l10n.settingsShowPronBn,
                ),
              ),
            ],
          ),
          _Group(
            title: l10n.settingsGroupAudio,
            rows: <Widget>[
              _Row(
                title: l10n.settingsVoiceEngine,
                subtitle: switch (settings.read(SettingKeys.ttsEngine)) {
                  TtsEngineSetting.supertonic => l10n.settingsVoiceSupertonic(
                    settings.read(SettingKeys.ttsVoice) ??
                        SettingKeys.ttsVoice.defaultValue!,
                  ),
                  TtsEngineSetting.system => l10n.settingsVoicePhone,
                },
                onTap: () => ModelsRoute.open(context),
              ),
              _Row(
                title: l10n.settingsSpeed,
                subtitle: l10n.settingsSpeedLine(
                  _times(speedQuarters.clamp(speed.min, speed.max)),
                ),
                labelledByControl: true,
                trailing: _slider(
                  DpSlider(
                    value: speedQuarters.clamp(speed.min, speed.max),
                    min: speed.min,
                    max: speed.max,
                    compact: true,
                    label: l10n.settingsSpeed,
                    describe: (quarters) => '${_times(quarters)}×',
                    onChanged: (quarters) =>
                        set(SettingKeys.ttsSpeed, quarters / 4),
                  ),
                ),
              ),
              _Row(
                title: l10n.settingsAutoplayHeadword,
                subtitle: l10n.settingsAutoplayHeadwordNote,
                labelledByControl: true,
                trailing: toggle(
                  SettingKeys.autoplayHeadword,
                  l10n.settingsAutoplayHeadword,
                ),
              ),
              _Row(
                title: l10n.settingsAutoplayExample,
                subtitle: l10n.settingsAutoplayExampleNote,
                labelledByControl: true,
                trailing: toggle(
                  SettingKeys.autoplayExample,
                  l10n.settingsAutoplayExample,
                ),
              ),
              _Row(
                title: l10n.settingsListening,
                subtitle: l10n.settingsListeningNote,
                labelledByControl: true,
                trailing: toggle(
                  SettingKeys.listeningQuestions,
                  l10n.settingsListening,
                ),
              ),
            ],
          ),
          _Group(
            title: l10n.settingsGroupExams,
            rows: <Widget>[
              _Row(
                title: l10n.settingsUnlockAt,
                subtitle: l10n.settingsUnlockAtNote,
                value: l10n.settingsPercent(unlock),
                onTap: () async {
                  final chosen = await _choose(
                    context,
                    l10n.settingsUnlockAt,
                    percents(unlockPercent),
                    unlock,
                  );
                  if (chosen != null) {
                    await set(SettingKeys.examUnlockPercent, chosen);
                  }
                },
              ),
              _Row(
                title: l10n.settingsPassMark,
                value: l10n.settingsPercent(pass),
                onTap: () async {
                  final chosen = await _choose(
                    context,
                    l10n.settingsPassMark,
                    percents(passPercent),
                    pass,
                  );
                  if (chosen != null) {
                    await set(SettingKeys.examPassPercent, chosen);
                  }
                },
              ),
              _Row(
                title: l10n.settingsTimerDefault,
                subtitle: l10n.settingsTimerDefaultNote,
                labelledByControl: true,
                trailing: toggle(
                  SettingKeys.examTimerDefault,
                  l10n.settingsTimerDefault,
                ),
              ),
            ],
          ),
          _Group(
            title: l10n.settingsGroupTranslation,
            rows: <Widget>[
              _Row(
                title: l10n.settingsTranslation,
                subtitle: model == null
                    ? null
                    : l10n.settingsTranslationStatus(switch (model.status) {
                        ModelStatus.downloading => 'downloading',
                        ModelStatus.verifying => 'verifying',
                        ModelStatus.ready => 'ready',
                        ModelStatus.updateAvailable => 'update',
                        ModelStatus.failed => 'failed',
                        ModelStatus.notDownloaded => 'none',
                      }, (model.progress * 100).round()),
                labelledByControl: true,
                trailing: AdaptiveSwitch(
                  value: settings.read(SettingKeys.mtEnabled),
                  semanticLabel: l10n.settingsTranslation,
                  onChanged: (on) async {
                    final done = await editor.translation(on: on);
                    if (!done && context.mounted) {
                      ModelsRoute.open(context);
                    }
                  },
                ),
              ),
            ],
          ),
          _Group(
            title: l10n.settingsGroupData,
            rows: <Widget>[
              _Row(
                title: l10n.settingsExport,
                subtitle: l10n.settingsExportNote,
                onTap: () => ExportImportRoute.open(context),
              ),
              _Row(
                title: l10n.settingsReset,
                subtitle: l10n.settingsResetNote,
                // ponytail: M7's sheet is #150; until it lands the row shows
                // where Reset will be and does nothing.
                chevron: true,
              ),
              _Row(
                title: l10n.settingsRestart,
                subtitle: l10n.settingsRestartNote,
                onTap: () => OnboardingRoute.restartSetup(context),
              ),
            ],
          ),
        ],
      ),
    );
    return tokens.isGlass
        ? AuroraBackdrop(leading: tokens.color.der, child: scaffold)
        : scaffold;
  }

  static Widget _stepper(
    SettingsRepository settings,
    IntSetting key,
    ({int min, int max}) range,
    String decrease,
    String increase,
    Future<void> Function<T>(SettingKey<T> key, T value) set,
  ) => DpStepper(
    value: settings.read(key).clamp(range.min, range.max),
    min: range.min,
    max: range.max,
    decreaseLabel: decrease,
    increaseLabel: increase,
    onChanged: (value) => set(key, value),
  );

  /// The artboard's 120 dp slider beside its row's text.
  static Widget _slider(DpSlider slider) => SizedBox(width: 120, child: slider);

  /// Quarters as the speed reads: 4 is "1.0", 3 is "0.75".
  static String _times(int quarters) => quarters.isEven
      ? (quarters / 4).toStringAsFixed(1)
      : (quarters / 4).toStringAsFixed(2);

  /// "Mon–Sat · 19:30 · only when something is due", from M5's settings.
  static String _studyDays(BuildContext context, SettingsRepository settings) {
    final l10n = AppLocalizations.of(context);
    final mask = settings.read(SettingKeys.studyDaysMask);
    final days = <int>[
      for (var day = 0; day < 7; day++)
        if (mask & (1 << day) != 0) day,
    ];
    // 1 January 2024 was a Monday: the locale's own short weekday names.
    final weekday = DateFormat.E(Localizations.localeOf(context).toString());
    String name(int day) => weekday.format(DateTime(2024, 1, 1 + day));

    // A run of days in a row, across the week's end too: it starts on the
    // day whose day before is not a study day ("Fri–Mon").
    final start = days.where((day) => !days.contains((day + 6) % 7));
    final run = start.length == 1 && days.length >= 3 ? start.single : null;
    final parts = <String>[
      if (days.length == 7)
        l10n.settingsEveryDay
      else if (run != null)
        l10n.settingsDayRange(name(run), name((run + days.length - 1) % 7))
      else if (days.isNotEmpty)
        days.map(name).join(', '),
    ];
    if (settings.read(SettingKeys.reminderEnabled)) {
      final time = settings.read(SettingKeys.reminderTime);
      parts.add(
        MaterialLocalizations.of(context).formatTimeOfDay(
          TimeOfDay(hour: time.hour, minute: time.minute),
          alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
        ),
      );
      if (settings.read(SettingKeys.reminderOnlyWhenDue)) {
        parts.add(l10n.settingsOnlyWhenDue);
      }
    } else {
      parts.add(l10n.settingsNoReminder);
    }
    return parts.join(' · ');
  }

  /// One choice from a short list, in a sheet: the chosen value, or null when
  /// the sheet is dismissed.
  static Future<T?> _choose<T>(
    BuildContext context,
    String title,
    List<(T, String)> options,
    T current,
  ) => Adaptive.showSheet<T>(
    context: context,
    builder: (sheet) {
      final tokens = sheet.tokens;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Semantics(
              header: true,
              child: DpText(title, role: DpTextRole.title),
            ),
            const SizedBox(height: 8),
            // Scrolls: Unlock's eleven rows outgrow a phone held sideways,
            // and any list outgrows 200 % text.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final (value, label) in options)
                      Semantics(
                        container: true,
                        button: true,
                        selected: value == current,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => Navigator.of(sheet).pop(value),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 48),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: DpText(
                                    label,
                                    role: DpTextRole.body,
                                    weight: value == current ? 600 : 400,
                                  ),
                                ),
                                if (value == current)
                                  Icon(
                                    Icons.check,
                                    size: 20,
                                    color: tokens.color.link,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// A group: a Cobalt header over flat rows on Android, an upper-case header
/// over an inset panel on iOS.
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final cupertino = context.isCupertino;

    final body = Column(
      children: <Widget>[
        for (final (i, row) in rows.indexed) ...<Widget>[
          if (i > 0) Container(height: 1, color: tokens.surface.outline),
          row,
        ],
      ],
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(16, cupertino ? 16 : 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: cupertino
                ? const EdgeInsets.fromLTRB(16, 0, 16, 6)
                : const EdgeInsets.only(bottom: 4),
            child: Semantics(
              header: true,
              child: cupertino
                  ? DpText(
                      title.toUpperCase(),
                      role: DpTextRole.label,
                      weight: 500,
                      letterSpacing: 0.4,
                      color: tokens.color.textSecondary,
                    )
                  // The artboard's #2F46E0: Cobalt's text shade.
                  : DpText(
                      title,
                      role: DpTextRole.label,
                      weight: 700,
                      color: tokens.color.derText,
                    ),
            ),
          ),
          if (cupertino)
            // ponytail: a blur per group under glass, past the budget of
            // three; #34's shared backdrop is the fix for every list.
            DpSurface(
              kind: DpSurfaceKind.bar,
              radius: 12,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: body,
            )
          else
            body,
        ],
      ),
    );
  }
}

/// One setting: its name, a line under it, and its control — or, for a row
/// that opens something, the value and a chevron.
class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    this.subtitle,
    this.trailing,
    this.value,
    this.onTap,
    this.chevron = false,
    this.labelledByControl = false,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final String? value;
  final VoidCallback? onTap;
  final bool chevron;

  /// The control already says the title — a switch's label, a slider's — so
  /// a screen reader hears it once.
  final bool labelledByControl;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final subtitle = this.subtitle;
    final value = this.value;
    final heading = DpText(title, role: DpTextRole.body, weight: 500);

    // 52 dp, as the artboards draw every row. The padding is the text's
    // alone: the controls' 48 dp tap targets fill the row themselves.
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (labelledByControl)
                    ExcludeSemantics(child: heading)
                  else
                    heading,
                  if (subtitle != null)
                    DpText(
                      subtitle,
                      role: DpTextRole.caption,
                      color: tokens.color.textSecondary,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          ?trailing,
          if (onTap != null || chevron) ...<Widget>[
            if (value != null)
              DpText(
                value,
                role: DpTextRole.body,
                color: tokens.color.textSecondary,
              ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: tokens.color.textSecondary,
            ),
          ],
        ],
      ),
    );

    return Semantics(
      container: true,
      button: onTap != null,
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
