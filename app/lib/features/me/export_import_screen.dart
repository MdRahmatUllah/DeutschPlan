import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/components/sg_button.dart';
import 'package:sogda/core/components/sg_feedback.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/aurora_backdrop.dart';
import 'package:sogda/core/theme/sg_focusable.dart';
import 'package:sogda/core/theme/sg_surface.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/data/repositories/backup_repository.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/domain/plan_engine.dart' show planDate;
import 'package:sogda/features/today/today_providers.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/l10n/ui_digits.dart';
import 'package:sogda/services/backup_files.dart';

part 'export_import_screen.g.dart';

/// M6's share sheet and file picker: the seam a test replaces.
@riverpod
BackupFiles backupFiles(Ref ref) => const PlatformBackupFiles();

/// The export's size in bytes, for "Export progress · 1.8 MB".
///
/// ponytail: builds the whole export to measure it, a few MB at most; a
/// row-count estimate if a learner's file ever grows past that.
@riverpod
Future<int> exportSize(Ref ref) async {
  final backups = ref.watch(backupRepositoryProvider);
  final content = ref.watch(contentDaoProvider);
  final json = await backups.exportJson(
    contentVersion: await content.version(),
  );
  return utf8.encode(json).length;
}

/// FR-M6-03/04: [json] into this phone's data, one transaction, and what
/// read the data before told. M6's import and S2 page 1's *Restore a backup*
/// (#822, a Replace).
Future<void> importBackup(
  ProviderContainer container,
  String json,
  ImportMode mode,
) async {
  final today = container.read(todayProvider);
  // #809: a file from an older course, under the uids this one has now.
  final aliases = await container.read(contentUpdaterProvider).aliases();
  await container
      .read(backupRepositoryProvider)
      .import(json, mode: mode, today: today, aliases: aliases);
  if (mode == ImportMode.replace) {
    // #688 DA-6: the attempts replaced leave their recordings behind, and
    // an imported attempt given the same id would take one on. After the
    // data and best effort, as a reset drops them.
    try {
      await container.read(modelRepositoryProvider).deleteRecordings();
    } on Object catch (error) {
      debugPrint('import: recordings not deleted: $error');
    }
  }
  // The settings cache, the plan engine (built with four of them, and kept
  // alive under Today) and Today's plan were read before the import: the
  // streams follow drift, these don't. The data is in by now: a reload
  // that fails is logged, not reported as the import's failure, whose
  // "Nothing changed" would be untrue (#692 ME-7). The file's settings then
  // reach the cache at the next start.
  try {
    await container.read(settingsSourceProvider).reload();
  } on Object catch (error) {
    debugPrint('import: settings not reloaded: $error');
  }
  container.invalidate(planEngineProvider);
  if (mode == ImportMode.merge) {
    // #622, #937: today planned again from the merged data, by the engine
    // the file's settings made. Best effort: the data is in, and Today opens
    // on what is planned either way.
    try {
      await container.read(planEngineProvider).replanToday(today);
    } on Object catch (error) {
      debugPrint('import: today not planned again: $error');
    }
  }
  container
    ..invalidate(todayPlanProvider)
    ..invalidate(exportSizeProvider);
}

/// What the import card has to say instead of a preview.
enum _Problem { notABackup, newer, failed }

/// M6 · Export / import (`export-import.md`, the ExportImport artboards):
/// the export card with its size and last date, and the import card with
/// the chosen file's preview, Merge or Replace, and the button.
class ExportImportScreen extends ConsumerStatefulWidget {
  const ExportImportScreen({super.key});

  /// `sogda-2026-09-20.json`: the file an export shares.
  static String fileName(DateTime now) => 'sogda-${planDate(now)}.json';

  @override
  ConsumerState<ExportImportScreen> createState() => _ExportImportState();
}

class _ExportImportState extends ConsumerState<ExportImportScreen> {
  PickedBackup? _file;
  BackupPreview? _preview;
  _Problem? _problem;
  ImportMode _mode = ImportMode.merge;
  bool _busy = false;

  /// FR-M6-01: the file to the share sheet, or saved on the phone (#1066),
  /// and the day remembered once the learner sent or saved it.
  Future<void> _export({bool save = false}) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final backups = ref.read(backupRepositoryProvider);
    final content = ref.read(contentDaoProvider);
    final files = ref.read(backupFilesProvider);
    final settings = ref.read(settingsSourceProvider);
    final now = ref.read(clockProvider)();
    setState(() => _busy = true);
    try {
      final json = await backups.exportJson(
        contentVersion: await content.version(),
      );
      final name = ExportImportScreen.fileName(now);
      if (await (save ? files.save(name, json) : files.share(name, json))) {
        await settings.write(SettingKeys.lastExport, now);
      }
    } on Object catch (error) {
      debugPrint('export: $error');
      if (mounted) SgToast.show(context, l10n.exportImportExportFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// FR-M6-02: the file read and previewed; nothing is written yet.
  Future<void> _choose() async {
    final files = ref.read(backupFilesProvider);
    final backups = ref.read(backupRepositoryProvider);
    final PickedBackup? file;
    try {
      file = await files.pick();
    } on Object catch (error) {
      // Not text, too big to be a backup, or the picker failed (#657): the
      // card says so rather than doing nothing.
      debugPrint('import pick: $error');
      // #692 ME-6: and the file chosen before goes with it, or its Import
      // button stayed under the error and imported that one.
      if (mounted) {
        setState(() {
          _file = null;
          _preview = null;
          _problem = _Problem.notABackup;
        });
      }
      return;
    }
    // Backed out of the picker: whatever was chosen before stays.
    if (file == null || !mounted) return;
    BackupPreview? preview;
    _Problem? problem;
    try {
      preview = await backups.preview(file.json);
    } on ImportException catch (error) {
      problem = error.reason == ImportRefusal.newerSchema
          ? _Problem.newer
          : _Problem.notABackup;
    } on Object catch (error) {
      debugPrint('import preview: $error');
      problem = _Problem.notABackup;
    }
    setState(() {
      _file = file;
      _preview = preview;
      _problem = problem;
      // #721: each file starts on Merge, the default; *Replace* is chosen
      // for a file, never carried over from the last one.
      _mode = ImportMode.merge;
    });
  }

  /// FR-M6-03/04: one transaction, so a failure leaves this phone as it was.
  Future<void> _import() async {
    final file = _file;
    if (file == null || _busy) return;
    final l10n = AppLocalizations.of(context);
    if (_mode == ImportMode.replace) {
      final sure = await Adaptive.showConfirm(
        context: context,
        title: l10n.exportImportReplaceTitle,
        message: l10n.exportImportReplaceMessage,
        confirmLabel: l10n.exportImportReplaceConfirm,
        cancelLabel: l10n.exportImportReplaceCancel,
        destructive: true,
      );
      if (sure != true || !mounted) return;
    }
    // Held, not this screen's ref: Back can close M6 during the import,
    // and Today must still let go of the old plan (#679).
    final container = ProviderScope.containerOf(context, listen: false);
    final mode = _mode;
    setState(() => _busy = true);
    try {
      await importBackup(container, file.json, mode);
      if (!mounted) return;
      setState(() {
        _file = null;
        _preview = null;
        _problem = null;
      });
      SgToast.show(context, l10n.exportImportDone);
    } on Object catch (error) {
      debugPrint('import: $error');
      if (mounted) setState(() => _problem = _Problem.failed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final size = ref.watch(exportSizeProvider).value;
    final last = ref.watch(settingsSourceProvider).read(SettingKeys.lastExport);
    final file = _file;
    final preview = _preview;
    final problem = _problem;

    final scaffold = AdaptiveScaffold(
      title: l10n.exportImportTitle,
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
          _Card(
            heading: l10n.exportImportExportHeading,
            children: <Widget>[
              SgText(l10n.exportImportExportBody, role: SgTextRole.body),
              SgButton(
                label: size == null
                    ? l10n.exportImportExport
                    : l10n.exportImportExportSized(_size(l10n, size)),
                drawnHeight: 48,
                onPressed: _busy ? null : () => unawaited(_export()),
              ),
              // #1066: a copy on the phone itself, where the share sheet
              // has no local target (One UI).
              SgButton(
                label: l10n.exportImportSave,
                kind: SgButtonKind.secondary,
                onPressed: _busy ? null : () => unawaited(_export(save: true)),
              ),
              _Caption(
                last == null
                    ? l10n.exportImportLastNever
                    : l10n.exportImportLast(_day(context, last)),
              ),
              _Caption(l10n.exportImportRecordings),
            ],
          ),
          const SizedBox(height: 12),
          _Card(
            heading: l10n.exportImportImportHeading,
            children: <Widget>[
              if (file != null)
                _FileTile(
                  name: file.name,
                  lines: preview == null
                      ? const <String>[]
                      : _lines(context, preview),
                ),
              if (problem != null)
                SgText(
                  switch (problem) {
                    _Problem.notABackup => l10n.exportImportNotABackup,
                    _Problem.newer => l10n.exportImportNewer,
                    _Problem.failed => l10n.exportImportFailed,
                  },
                  role: SgTextRole.label,
                  color: tokens.color.wrongText,
                ),
              if (file != null && preview != null) ...<Widget>[
                for (final mode in ImportMode.values)
                  _Choice(
                    label: switch (mode) {
                      ImportMode.merge => l10n.exportImportMerge,
                      ImportMode.replace => l10n.exportImportReplace,
                    },
                    selected: _mode == mode,
                    onTap: () => setState(() => _mode = mode),
                  ),
                SgButton(
                  label: _mode == ImportMode.merge
                      ? l10n.exportImportDoMerge
                      : l10n.exportImportDoReplace,
                  kind: SgButtonKind.secondary,
                  onPressed: _busy ? null : () => unawaited(_import()),
                ),
              ],
              if (file == null)
                SgButton(
                  label: l10n.exportImportChoose,
                  kind: SgButtonKind.secondary,
                  onPressed: _busy ? null : () => unawaited(_choose()),
                )
              else
                _Link(
                  label: l10n.exportImportChooseOther,
                  onTap: _busy ? null : () => unawaited(_choose()),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SgText(
              l10n.exportImportFooter,
              role: SgTextRole.caption,
              textAlign: TextAlign.center,
              color: tokens.color.textSecondary,
            ),
          ),
        ],
      ),
    );
    return tokens.isGlass
        ? AuroraBackdrop(leading: tokens.color.der, child: scaffold)
        : scaffold;
  }

  /// "1.8 MB", or "240 KB" under a megabyte.
  static String _size(AppLocalizations l10n, int bytes) {
    const kb = 1024;
    return bytes < kb * kb
        ? l10n.exportImportSizeKb((bytes / kb).ceil())
        : l10n.exportImportSizeMb(
            l10n.digits((bytes / (kb * kb)).toStringAsFixed(1)),
          );
  }

  static String _day(BuildContext context, DateTime day) => DateFormat(
    'd MMM',
    Localizations.localeOf(context).toString(),
  ).format(day);

  /// "2,104 word states · last active 20 Sep · A2.1", then when the file
  /// was written and what else it holds, so a *Replace* can be judged
  /// (#396): "Exported 20 Sep · 5,321 reviews · 30 days planned · …".
  static List<String> _lines(BuildContext context, BackupPreview preview) {
    final l10n = AppLocalizations.of(context);
    final active = preview.lastActive == null
        ? null
        : DateTime.tryParse(preview.lastActive!)?.toLocal();
    final exported = DateTime.tryParse(preview.exportedAt)?.toLocal();
    int rows(String table) => preview.rowCounts[table] ?? 0;
    return <String>[
      <String>[
        l10n.exportImportWordStates(preview.wordStates),
        if (active != null) l10n.exportImportLastActive(_day(context, active)),
        ?preview.activeStep,
      ].join(' · '),
      <String>[
        if (exported != null)
          l10n.exportImportExported(_day(context, exported)),
        // What there is, and nothing of what there isn't.
        if (rows('review_log') > 0)
          l10n.exportImportReviews(rows('review_log')),
        if (preview.planDays > 0) l10n.exportImportPlanDays(preview.planDays),
        if (rows('quiz_attempts') > 0)
          l10n.exportImportQuizzes(rows('quiz_attempts')),
        if (rows('exam_attempts') > 0)
          l10n.exportImportExams(rows('exam_attempts')),
        if (rows('custom_words') > 0)
          l10n.exportImportMyWords(rows('custom_words')),
      ].join(' · '),
    ]..removeWhere((line) => line.isEmpty);
  }
}

/// One of M6's two cards: a spaced heading over its content, 10 apart.
class _Card extends StatelessWidget {
  const _Card({required this.heading, required this.children});

  final String heading;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SgSurface(
    kind: SgSurfaceKind.bar,
    radius: 16,
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          header: true,
          child: SgText(
            heading.toUpperCase(),
            role: SgTextRole.caption,
            weight: 700,
            letterSpacing: 0.6,
            color: context.tokens.color.textSecondary,
          ),
        ),
        // A node each: left to merge, the heading, the text and the button
        // become one, and the button's tap belongs to the whole card.
        for (final child in children) ...<Widget>[
          const SizedBox(height: 10),
          Semantics(container: true, child: child),
        ],
      ],
    ),
  );
}

/// "Last export: never": 12/16 in the secondary text colour.
class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => SgText(
    text,
    role: SgTextRole.caption,
    color: context.tokens.color.textSecondary,
  );
}

/// The chosen file on Oat: its name, and the preview lines under it.
class _FileTile extends StatelessWidget {
  const _FileTile({required this.name, required this.lines});

  final String name;

  /// Empty when the file can't be previewed; the card says why below.
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.surface.muted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.download, size: 22, color: tokens.color.ink),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // No line may break at "-2026" (a hyphen before a digit), so
                // the whole name is one word, and at 150 % Flutter cut it
                // between "2" and "0" (#165). Above 100 % it may break after
                // each hyphen; a screen reader hears the name as it is.
                SgText(
                  SgScript.scaled(context) ? name.replaceAll('-', '-​') : name,
                  role: SgTextRole.body,
                  weight: 600,
                  semanticsLabel: name,
                ),
                for (final line in lines) ...<Widget>[
                  const SizedBox(height: 1),
                  _Caption(line),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A Merge or Replace choice: the radio the artboards draw, a ring with a
/// Lagoon dot, on both platforms.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      container: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: SgTappable(
        onTap: onTap,
        child: ConstrainedBox(
          // accessibility-performance.md: 48 dp on Android, 44 pt on iOS.
          constraints: BoxConstraints(minHeight: context.isCupertino ? 44 : 48),
          child: Row(
            children: <Widget>[
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? null : tokens.surface.card,
                  border: Border.all(
                    color: selected ? tokens.color.ink : tokens.surface.outline,
                    width: 2,
                  ),
                ),
                child: selected
                    ? Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: tokens.color.primary,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(child: SgText(label, role: SgTextRole.body)),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Choose a different file": the artboard's small grey line, as a button
/// with a full-size target.
class _Link extends StatelessWidget {
  const _Link({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    enabled: onTap != null,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: SgTappable(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: context.isCupertino ? 44 : 48),
        child: Align(alignment: Alignment.centerLeft, child: _Caption(label)),
      ),
    ),
  );
}
