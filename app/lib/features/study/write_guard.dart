import 'dart:async';

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/features/me/export_import_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// `accessibility-performance.md`: "DB write error: Retry + Export; last
/// saved card is never lost" (#174).
///
/// Runs [write]. If it throws, the shared error panel comes up in a sheet:
/// *Retry* runs it again, *Export progress* shares a backup from where the
/// learner is. Each answer is one transaction, so a failed one wrote nothing
/// and every answer before it is saved. [write] answers whether it wrote
/// (a double tap's second call does not); the result is that answer, or
/// false when the sheet was closed instead.
Future<bool> guardWrite(
  BuildContext context,
  Future<bool> Function() write,
) async {
  while (true) {
    try {
      return await write();
    } on Object catch (error) {
      // Drift runs in a background isolate in the app: a failed write comes
      // back as a DriftRemoteException, not a SqliteException.
      debugPrint('write: $error');
      if (!context.mounted) return false;
      final retry = await Adaptive.showSheet<bool>(
        context: context,
        builder: (_) => const _WriteFailed(),
      );
      if (retry != true || !context.mounted) return false;
    }
  }
}

class _WriteFailed extends ConsumerStatefulWidget {
  const _WriteFailed();

  @override
  ConsumerState<_WriteFailed> createState() => _WriteFailedState();
}

class _WriteFailedState extends ConsumerState<_WriteFailed> {
  bool _busy = false;

  /// FR-M6-01's file, shared in place: a full-screen session is not left for
  /// M6. No `last_export` is written — the database is what is failing.
  Future<void> _export() async {
    final l10n = AppLocalizations.of(context);
    final backups = ref.read(backupRepositoryProvider);
    final content = ref.read(contentDaoProvider);
    final files = ref.read(backupFilesProvider);
    final now = ref.read(clockProvider)();
    setState(() => _busy = true);
    try {
      final json = await backups.exportJson(
        contentVersion: await content.version(),
      );
      await files.share(ExportImportScreen.fileName(now), json);
    } on Object catch (error) {
      debugPrint('export: $error');
      if (mounted) DpToast.show(context, l10n.exportImportExportFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: DpErrorPanel(
        message: l10n.saveAnswerFailed,
        retryLabel: l10n.retry,
        onRetry: () => Navigator.of(context).pop(true),
        action: DpButton(
          label: l10n.exportProgress,
          kind: DpButtonKind.secondary,
          onPressed: _busy ? null : () => unawaited(_export()),
        ),
      ),
    );
  }
}
