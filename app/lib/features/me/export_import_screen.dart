import 'dart:async';
import 'dart:convert';

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/backup_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/domain/plan_engine.dart' show planDate;
import 'package:deutschplan/features/today/today_providers.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/l10n/ui_digits.dart';
import 'package:deutschplan/services/backup_files.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

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

/// What the import card has to say instead of a preview.
enum _Problem { notABackup, newer, failed }

/// M6 · Export / import (`export-import.md`, the ExportImport artboards):
/// the export card with its size and last date, and the import card with
/// the chosen file's preview, Merge or Replace, and the button.
class ExportImportScreen extends ConsumerStatefulWidget {
  const ExportImportScreen({super.key});

  /// `deutschplan-2026-09-20.json`: the file an export shares.
  static String fileName(DateTime now) => 'deutschplan-${planDate(now)}.json';

  @override
  ConsumerState<ExportImportScreen> createState() => _ExportImportState();
}

class _ExportImportState extends ConsumerState<ExportImportScreen> {
  PickedBackup? _file;
  BackupPreview? _preview;
  _Problem? _problem;
  ImportMode _mode = ImportMode.merge;
  bool _busy = false;

  /// FR-M6-01: the file to the share sheet, and the day remembered once the
  /// learner sent it somewhere.
  Future<void> _export() async {
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
      if (await files.share(ExportImportScreen.fileName(now), json)) {
        await settings.write(SettingKeys.lastExport, now);
      }
    } on Object catch (error) {
      debugPrint('export: $error');
      if (mounted) DpToast.show(context, l10n.exportImportExportFailed);
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
    } on FormatException {
      if (mounted) setState(() => _problem = _Problem.notABackup);
      return;
    }
    // Backed out of the picker: whatever was chosen before stays.
    if (file == null || !mounted) return;
    BackupPreview? preview;
    _Problem? problem;
    try {
      preview = backups.preview(file.json);
    } on ImportException catch (error) {
      problem = error.reason == ImportRefusal.newerSchema
          ? _Problem.newer
          : _Problem.notABackup;
    }
    setState(() {
      _file = file;
      _preview = preview;
      _problem = problem;
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
    final backups = ref.read(backupRepositoryProvider);
    final settings = ref.read(settingsSourceProvider);
    setState(() => _busy = true);
    try {
      await backups.import(file.json, mode: _mode);
      // The settings cache, the plan engine (built with four of them, and
      // kept alive under Today) and Today's plan were read before the
      // import: the streams follow drift, these don't.
      await settings.reload();
      ref
        ..invalidate(planEngineProvider)
        ..invalidate(todayPlanProvider)
        ..invalidate(exportSizeProvider);
      if (!mounted) return;
      setState(() {
        _file = null;
        _preview = null;
        _problem = null;
      });
      DpToast.show(context, l10n.exportImportDone);
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
              DpText(l10n.exportImportExportBody, role: DpTextRole.body),
              DpButton(
                label: size == null
                    ? l10n.exportImportExport
                    : l10n.exportImportExportSized(_size(l10n, size)),
                drawnHeight: 48,
                onPressed: _busy ? null : () => unawaited(_export()),
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
                DpText(
                  switch (problem) {
                    _Problem.notABackup => l10n.exportImportNotABackup,
                    _Problem.newer => l10n.exportImportNewer,
                    _Problem.failed => l10n.exportImportFailed,
                  },
                  role: DpTextRole.label,
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
                DpButton(
                  label: _mode == ImportMode.merge
                      ? l10n.exportImportDoMerge
                      : l10n.exportImportDoReplace,
                  kind: DpButtonKind.secondary,
                  onPressed: _busy ? null : () => unawaited(_import()),
                ),
              ],
              if (file == null)
                DpButton(
                  label: l10n.exportImportChoose,
                  kind: DpButtonKind.secondary,
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
            child: DpText(
              l10n.exportImportFooter,
              role: DpTextRole.caption,
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
  Widget build(BuildContext context) => DpSurface(
    kind: DpSurfaceKind.bar,
    radius: 16,
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          header: true,
          child: DpText(
            heading.toUpperCase(),
            role: DpTextRole.caption,
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
  Widget build(BuildContext context) => DpText(
    text,
    role: DpTextRole.caption,
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
                DpText(
                  DpScript.scaled(context) ? name.replaceAll('-', '-​') : name,
                  role: DpTextRole.body,
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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
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
              Expanded(child: DpText(label, role: DpTextRole.body)),
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
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: context.isCupertino ? 44 : 48),
        child: Align(alignment: Alignment.centerLeft, child: _Caption(label)),
      ),
    ),
  );
}
