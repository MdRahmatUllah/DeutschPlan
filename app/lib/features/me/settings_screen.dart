import 'dart:async' show unawaited;

import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/components/sg_slider.dart';
import 'package:sogda/core/components/sg_stepper.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/aurora_backdrop.dart';
import 'package:sogda/core/theme/sg_focusable.dart';
import 'package:sogda/core/theme/sg_surface.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/data/repositories/course_meanings.dart';
import 'package:sogda/data/repositories/meaning_choice.dart';
import 'package:sogda/data/repositories/model_repository.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/domain/fsrs.dart';
import 'package:sogda/features/me/reset_flow.dart';
import 'package:sogda/features/today/today_providers.dart'
    show voiceInstalledProvider;
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/l10n/ui_digits.dart';
import 'package:sogda/l10n/ui_language_locale.dart';
import 'package:sogda/router/cross_tab.dart';
import 'package:sogda/router/routes.dart';

part 'settings_screen.g.dart';

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
  // One build is offered, Q4_K_M (#409).
  return models.stateOf(entry, entry.variants.first);
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

  /// FR-M5-01: [day] (0 is Monday) switched against the mask as it is now,
  /// not the one M5 was drawn with: two quick taps are two days (#692 ME-9).
  // ponytail: a second tap within the first's history write (milliseconds,
  // before it writes the setting) still reads the old mask; chain the
  // toggles if that is ever seen.
  Future<void> toggleStudyDay(int day) => studyDays(
    ref.read(settingsSourceProvider).read(SettingKeys.studyDaysMask) ^
        (1 << day),
  );

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

  /// FR-D3-04: whether any document keeps its photos, so that turning
  /// *Save original images* off has something to ask about.
  Future<bool> keepsImages() async =>
      await ref.read(documentRepositoryProvider).imageBytes() > 0;

  /// FR-D3-04: the photos already kept go; every document keeps its text.
  Future<void> dropImages() =>
      ref.read(documentRepositoryProvider).dropImages();
}

/// M3 · Settings: every learner-facing setting, in nine groups
/// (`settings.md`). Material headers on Android, inset groups on iOS.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, this.row});

  /// `SettingsRoute.row`: the row to scroll to on opening (#1364).
  final String? row;

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
    final fits = ref.watch(translationFitsProvider).value ?? true;
    final meaning = meaningChoiceOf(settings);
    // #1081: the course's languages, each named in itself.
    final languages = ref.watch(courseLanguagesProvider).value ?? baseLanguages;
    final ui = settings.read(SettingKeys.uiLanguage);
    final theme = settings.read(SettingKeys.themeMode);
    final unlock = settings.read(SettingKeys.examUnlockPercent);
    final pass = settings.read(SettingKeys.examPassPercent);
    final speedQuarters = (settings.read(SettingKeys.ttsSpeed) * 4).round();
    final autodelete = settings.read(SettingKeys.docAutodeleteDays);

    String? secondName(String? code) =>
        code == null ? null : ownNameOf(code, languages);
    String themeName(ThemeModeSetting mode) => switch (mode) {
      ThemeModeSetting.system => l10n.settingsThemeSystem,
      ThemeModeSetting.light => l10n.settingsThemeLight,
      ThemeModeSetting.dark => l10n.settingsThemeDark,
      ThemeModeSetting.glass => l10n.settingsThemeGlass,
    };
    String afterDays(int days) => days == 0
        ? l10n.settingsDocAutodeleteNever
        : l10n.settingsDocAutodeleteAfter(days);
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
        // A row to show on opening (#1364) must be built to be scrolled to:
        // the whole list then, a few dozen rows, not only the first screen's.
        scrollCacheExtent: row == null
            ? null
            : const ScrollCacheExtent.pixels(100000),
        // Where the learner had scrolled to survives a change of theme: glass
        // wraps the screen in its aurora, which builds the list anew (#345).
        key: const PageStorageKey<String>('settings'),
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
              _Held(
                value: retention,
                builder: (retention, hold) => _Row(
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
                  controlValue: l10n.settingsPercent(retention),
                  trailing: _slider(
                    SgSlider(
                      value: retention,
                      min: (Fsrs.minRetention * 100).round(),
                      max: (Fsrs.maxRetention * 100).round(),
                      compact: true,
                      label: l10n.settingsRetention,
                      describe: l10n.settingsPercent,
                      onChanged: hold,
                      onChangeEnd: (percent) =>
                          set(SettingKeys.desiredRetention, percent / 100),
                    ),
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
                value: ownNameOf(meaning.primary, languages),
                onTap: () async {
                  final chosen = await _choose(
                    context,
                    l10n.settingsMeaning,
                    <(String, String)>[
                      for (final language in languages)
                        (language.code, language.ownName),
                    ],
                    meaning.primary,
                  );
                  if (chosen != null) {
                    // The second becomes the first: the two swap places.
                    await ref
                        .read(languagesProvider.notifier)
                        .setMeaning(
                          MeaningChoice(
                            chosen,
                            meaning.secondary == chosen
                                ? meaning.primary
                                : meaning.secondary,
                          ),
                        );
                  }
                },
              ),
              _Row(
                title: l10n.settingsMeaningSecond,
                value:
                    secondName(meaning.secondary) ?? l10n.settingsMeaningNone,
                onTap: () async {
                  final chosen = await _choose(
                    context,
                    l10n.settingsMeaningSecond,
                    <(String, String)>[
                      ('', l10n.settingsMeaningNone),
                      for (final language in languages)
                        if (language.code != meaning.primary)
                          (language.code, language.ownName),
                    ],
                    meaning.secondary ?? '',
                  );
                  if (chosen != null) {
                    await ref
                        .read(languagesProvider.notifier)
                        .setMeaning(
                          MeaningChoice(
                            meaning.primary,
                            chosen.isEmpty ? null : chosen,
                          ),
                        );
                  }
                },
              ),
              _Row(
                title: l10n.settingsUiLanguage,
                // #1078: each named in itself, as a learner looks for it.
                value: ui.nativeName,
                onTap: () async {
                  final chosen = await _choose(
                    context,
                    l10n.settingsUiLanguage,
                    <(UiLanguage, String)>[
                      for (final language in UiLanguage.values)
                        (language, language.nativeName),
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
              // #1077: offered only while Bangla is a meaning language.
              if (meaning.hasBangla)
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
                // What speaks: Supertonic chosen but not on the phone is the
                // phone's voice, standing in (#345). Until the check answers
                // it reads as chosen.
                subtitle: switch (settings.read(SettingKeys.ttsEngine)) {
                  TtsEngineSetting.supertonic
                      when ref.watch(voiceInstalledProvider).value == false =>
                    l10n.settingsVoicePhoneForSupertonic,
                  TtsEngineSetting.supertonic => l10n.settingsVoiceSupertonic(
                    settings.read(SettingKeys.ttsVoice) ??
                        SettingKeys.ttsVoice.defaultValue!,
                  ),
                  TtsEngineSetting.system => l10n.settingsVoicePhone,
                },
                onTap: () => ModelsRoute.open(context),
              ),
              _Held(
                value: speedQuarters.clamp(speed.min, speed.max),
                builder: (shown, hold) => _Row(
                  title: l10n.settingsSpeed,
                  subtitle: l10n.settingsSpeedLine(_times(l10n, shown)),
                  labelledByControl: true,
                  controlValue: '${_times(l10n, shown)}×',
                  trailing: _slider(
                    SgSlider(
                      value: shown,
                      min: speed.min,
                      max: speed.max,
                      compact: true,
                      label: l10n.settingsSpeed,
                      describe: (quarters) => '${_times(l10n, quarters)}×',
                      onChanged: hold,
                      onChangeEnd: (quarters) =>
                          set(SettingKeys.ttsSpeed, quarters / 4),
                    ),
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
                shown: row == SettingsRoute.examUnlock,
                title: l10n.settingsUnlockAt,
                subtitle: l10n.settingsUnlockAtNote,
                value: l10n.settingsPercent(unlock),
                onTap: () async {
                  final chosen = await _choose(
                    context,
                    l10n.settingsUnlockAt,
                    percents(SettingKeys.examUnlockPercent.range!),
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
                    percents(SettingKeys.examPassPercent.range!),
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
                // #154: below Hy-MT2's memory floor, translation can't be
                // turned on, and the row says why.
                subtitle: !fits
                    ? l10n.modelsNeedsMemory(l10n.modelsSizeGb(l10n.digits(4)))
                    : model == null
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
                  value: fits && settings.read(SettingKeys.mtEnabled),
                  semanticLabel: l10n.settingsTranslation,
                  onChanged: !fits
                      ? null
                      : (on) async {
                          final done = await editor.translation(on: on);
                          if (!done && context.mounted) {
                            ModelsRoute.open(context);
                          }
                        },
                ),
              ),
            ],
          ),
          // #1296: Learn from your documents (`document-matcher.md`).
          _Group(
            title: l10n.settingsGroupDocuments,
            rows: <Widget>[
              _Row(
                title: l10n.settingsDocDailyCap,
                // BR-PLAN-08: the plan today opened with keeps its cap.
                subtitle: l10n.settingsFromTomorrow,
                trailing: _stepper(
                  settings,
                  SettingKeys.docDailyCap,
                  l10n.settingsDocDailyCapDecrease,
                  l10n.settingsDocDailyCapIncrease,
                  set,
                ),
              ),
              _Row(
                title: l10n.settingsDocSaveImages,
                labelledByControl: true,
                trailing: AdaptiveSwitch(
                  value: settings.read(SettingKeys.docSaveImages),
                  semanticLabel: l10n.settingsDocSaveImages,
                  onChanged: (on) async {
                    await set(SettingKeys.docSaveImages, on);
                    // FR-D3-04: off, with photos kept, asks about those.
                    if (on || !await editor.keepsImages()) return;
                    if (!context.mounted) return;
                    final drop = await Adaptive.showConfirm(
                      context: context,
                      title: l10n.settingsDocImagesDropTitle,
                      message: l10n.settingsDocImagesDropMessage,
                      confirmLabel: l10n.settingsDocImagesDrop,
                      cancelLabel: l10n.settingsDocImagesKeep,
                      destructive: true,
                    );
                    if (drop ?? false) await editor.dropImages();
                  },
                ),
              ),
              _Row(
                title: l10n.settingsDocAutodelete,
                subtitle: l10n.settingsDocAutodeleteNote,
                value: afterDays(autodelete),
                onTap: () async {
                  final chosen = await _choose(
                    context,
                    l10n.settingsDocAutodelete,
                    <(int, String)>[
                      for (final days in SettingKeys.docAutodeleteDays.choices!)
                        (days, afterDays(days)),
                    ],
                    autodelete,
                  );
                  if (chosen != null) {
                    await set(SettingKeys.docAutodeleteDays, chosen);
                  }
                },
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
                onTap: () => openReset(context),
              ),
              _Row(
                title: l10n.settingsRestart,
                subtitle: l10n.settingsRestartNote,
                onTap: () => unawaited(_restart(context)),
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
    String decrease,
    String increase,
    Future<void> Function<T>(SettingKey<T> key, T value) set,
  ) => SgStepper(
    value: settings.read(key).clamp(key.range!.min, key.range!.max),
    min: key.range!.min,
    max: key.range!.max,
    decreaseLabel: decrease,
    increaseLabel: increase,
    onChanged: (value) => set(key, value),
  );

  /// The artboard's 120 dp slider beside its row's text.
  static Widget _slider(SgSlider slider) => SizedBox(width: 120, child: slider);

  /// Quarters as the speed reads: 4 is "1.0", 3 is "0.75" («0,75» in
  /// Polish, #1197).
  static String _times(AppLocalizations l10n, int quarters) =>
      l10n.decimal(quarters / 4, quarters.isEven ? 1 : 2);

  /// "Mon–Sat · 19:30 · only when something is due", from M5's settings.
  static String _studyDays(BuildContext context, SettingsRepository settings) {
    final l10n = AppLocalizations.of(context);
    final mask = settings.read(SettingKeys.studyDaysMask);
    final days = <int>[
      for (var day = 0; day < 7; day++)
        if (mask & (1 << day) != 0) day,
    ];
    // 1 January 2024 was a Monday: the locale's own short weekday names.
    // Not M5's chip names ("Mo", "বৃহঃ"), which are as short as a chip is
    // narrow: a line of text reads "Mon–Sat" (#704, declined).
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
              child: SgText(title, role: SgTextRole.title),
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
                        child: SgTappable(
                          onTap: () => Navigator.of(sheet).pop(value),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 48),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: SgText(
                                    label,
                                    role: SgTextRole.body,
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

/// A slider row's value while the finger is on it (#698): the row shows it at
/// once, the retention estimate and the speed with it, and the slider's
/// `onChangeEnd` saves it when the finger lets go: one write a drag, where
/// every step wrote user.db and woke every listener of the setting.
class _Held extends StatefulWidget {
  const _Held({required this.value, required this.builder});

  /// The saved value.
  final int value;

  /// The row, showing [shown]; [hold] is its slider's `onChanged`.
  final Widget Function(int shown, ValueChanged<int> hold) builder;

  @override
  State<_Held> createState() => _HeldState();
}

class _HeldState extends State<_Held> {
  int? _held;

  @override
  void didUpdateWidget(_Held old) {
    super.didUpdateWidget(old);
    // The save came back (or another writer's did): the setting shows again.
    if (widget.value != old.value) _held = null;
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    _held ?? widget.value,
    (value) => setState(() => _held = value),
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
                  ? SgText(
                      title.toUpperCase(),
                      role: SgTextRole.label,
                      weight: 500,
                      letterSpacing: 0.4,
                      color: tokens.color.textSecondary,
                    )
                  // The artboard's #2F46E0: Cobalt's text shade.
                  : SgText(
                      title,
                      role: SgTextRole.label,
                      weight: 700,
                      color: tokens.color.derText,
                    ),
            ),
          ),
          if (cupertino)
            // Under glass the groups in the list share the screen's one
            // read of the backdrop (#709).
            SgSurface(
              kind: SgSurfaceKind.bar,
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

/// #704: Restart setup reads the learner's values before it pushes its
/// page, and a second tap in between pushed a second. Held until that page is
/// up. (Reset's sheet needs none: a second tap opens no second sheet.)
bool _restarting = false;

Future<void> _restart(BuildContext context) async {
  if (_restarting) return;
  _restarting = true;
  try {
    await OnboardingRoute.restartSetup(context);
  } finally {
    // Until the page it pushed is up: go_router builds it on the next
    // frame, and M3 is the current route until then.
    await WidgetsBinding.instance.endOfFrame;
    _restarting = false;
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
    this.labelledByControl = false,
    this.controlValue,
    this.shown = false,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final String? value;
  final VoidCallback? onTap;

  /// The control already says the title — a switch's label, a slider's — so
  /// a screen reader hears it once.
  final bool labelledByControl;

  /// The value the control announces (a slider's), when the subtitle opens
  /// with it too: a screen reader hears the subtitle without it, so the value
  /// is said once (#1190).
  final String? controlValue;

  /// Scrolled into view as M3 opens, for a pointer to it (#1364).
  final bool shown;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final subtitle = this.subtitle;
    final value = this.value;
    // #1079: beside a stepper at 200 %, Russian's "Повторений" is wider than
    // what is left: it breaks between syllables, not at any letter.
    final heading = SgText(
      title,
      role: SgTextRole.body,
      weight: 500,
      breakTooWide: true,
    );

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
                    _spoken(
                      subtitle,
                      SgText(
                        subtitle,
                        role: SgTextRole.caption,
                        color: tokens.color.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          ?trailing,
          if (onTap != null) ...<Widget>[
            if (value != null)
              SgText(
                value,
                role: SgTextRole.body,
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

    // A switch row flips from anywhere on it, as Material's rows do, through
    // the switch's own onChanged, so each keeps its rule; a screen reader
    // already hears the row as the switch (#345).
    final tap =
        onTap ??
        switch (trailing) {
          AdaptiveSwitch(:final value, :final onChanged?) => () => onChanged(
            !value,
          ),
          _ => null,
        };
    final tile = Semantics(
      container: true,
      button: onTap != null,
      child: onTap != null
          ? SgTappable(onTap: onTap, child: row)
          : tap == null
          ? row
          // A switch row's tap is its switch's: the switch is the Tab stop
          // (#1021), and a screen reader has it. ponytail: allow-bare-tap
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: tap,
              child: row,
            ),
    );
    return shown ? _ShownOnOpen(child: tile) : tile;
  }

  /// The subtitle as a screen reader hears it: without the leading value the
  /// control has already said («90% · ≈ 3 reviews/day» → «≈ 3 reviews/day»).
  Widget _spoken(String subtitle, Widget text) {
    final said = controlValue;
    if (said == null || !subtitle.startsWith(said)) return text;
    final rest = subtitle
        .substring(said.length)
        .replaceFirst(RegExp(r'^\s*·\s*'), '');
    return rest.isEmpty
        ? ExcludeSemantics(child: text)
        : Semantics(label: rest, excludeSemantics: true, child: text);
  }
}

/// [child] scrolled into view once, after M3's first frame: the row a
/// pointer elsewhere opened M3 at (#1364, `SettingsRoute.row`).
class _ShownOnOpen extends StatefulWidget {
  const _ShownOnOpen({required this.child});

  final Widget child;

  @override
  State<_ShownOnOpen> createState() => _ShownOnOpenState();
}

class _ShownOnOpenState extends State<_ShownOnOpen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(Scrollable.ensureVisible(context, alignment: 0.3));
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
