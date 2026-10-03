import 'dart:async';

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
import 'package:sogda/data/repositories/document_repository.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/router/cross_tab.dart';
import 'package:sogda/router/routes.dart';

part 'my_documents_screen.g.dart';

/// D3's list (FR-D3-01): every kept document, newest first.
@riverpod
Stream<List<DocumentEntry>> myDocuments(Ref ref) =>
    ref.watch(documentRepositoryProvider).watchAll();

/// D3's storage line: the bytes the kept photos take, read again whenever
/// the list changes (a delete takes its photos).
@riverpod
Future<int> documentImageBytes(Ref ref) {
  ref.watch(myDocumentsProvider);
  return ref.watch(documentRepositoryProvider).imageBytes();
}

/// D3 · My documents (#1295, `my-documents.md`): the kept documents, to
/// reopen in D2, rename or delete; *New document* opens D1.
class MyDocumentsScreen extends ConsumerWidget {
  const MyDocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final documents = ref.watch(myDocumentsProvider).value;
    final scaffold = AdaptiveScaffold(
      title: l10n.myDocumentsTitle,
      // Back to R1: D3 sits in the search's stack.
      leading: AdaptiveBackButton(
        label: l10n.tabSearch,
        colour: context.isCupertino ? null : tokens.color.ink,
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
      body: switch (documents) {
        null => const SizedBox.shrink(),
        [] => const _Empty(),
        final entries => _List(entries: entries),
      },
    );
    return tokens.isGlass
        ? AuroraBackdrop(leading: tokens.color.die, child: scaffold)
        : scaffold;
  }
}

class _List extends ConsumerWidget {
  const _List({required this.entries});

  final List<DocumentEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final bytes = ref.watch(documentImageBytesProvider).value ?? 0;
    const mb = 1024 * 1024;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: <Widget>[
        SgButton(
          label: l10n.myDocumentsNew,
          onPressed: () => DocImportRoute.open(context),
        ),
        const SizedBox(height: 14),
        SgSurface(
          kind: SgSurfaceKind.bar,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: <Widget>[
              for (final (i, entry) in entries.indexed) ...<Widget>[
                if (i > 0) Container(height: 1, color: tokens.surface.outline),
                _Row(entry: entry),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SgText(
                bytes == 0
                    ? l10n.myDocumentsStorageNone(entries.length)
                    : l10n.myDocumentsStorage(
                        entries.length,
                        (bytes / mb).ceil(),
                      ),
                role: SgTextRole.caption,
                color: tokens.color.textSecondary,
              ),
            ),
            SgButton(
              label: l10n.meSettings,
              kind: SgButtonKind.text,
              expand: false,
              compact: true,
              onPressed: () => context.jumpToTab(const SettingsRoute()),
            ),
          ],
        ),
      ],
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.entry});

  final DocumentEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final document = entry.document;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final (icon, source) = switch (document.source) {
      'photo' => (
        Icons.photo_camera_outlined,
        l10n.myDocumentsPhotos(document.pageCount),
      ),
      'pdf' => (
        Icons.picture_as_pdf_outlined,
        l10n.myDocumentsPdf(document.pageCount),
      ),
      _ => (Icons.content_paste, l10n.myDocumentsText),
    };
    final detail = <String>[
      // «2 Oct», as the artboard and M6 write a day.
      DateFormat(
        'd MMM',
        locale,
      ).format(DateTime.parse(document.createdAt).toLocal()),
      source,
      // At none, what the learner did, never what it holds (#1358).
      if (entry.added > 0)
        l10n.myDocumentsAdded(entry.added)
      else
        l10n.myDocumentsNoneAdded,
    ].join(' · ');
    final menu = l10n.myDocumentsOptions(document.title);

    return Row(
      children: <Widget>[
        Expanded(
          child: Semantics(
            container: true,
            button: true,
            child: SgTappable(
              onTap: () => DocWordsRoute.open(context, document.id),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: tokens.surface.muted,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, size: 22, color: tokens.color.ink),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            SgText(
                              document.title,
                              role: SgTextRole.body,
                              weight: 600,
                            ),
                            SgText(
                              detail,
                              role: SgTextRole.caption,
                              color: tokens.color.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Semantics(
          // Its own node: with one row it took the whole card's bounds and
          // read before the row (agent-3, #1299).
          container: true,
          button: true,
          label: menu,
          excludeSemantics: true,
          onTap: () => unawaited(_menu(context, ref)),
          child: AdaptiveTooltip(
            message: menu,
            child: SgTappable(
              radius: BorderRadius.circular(24),
              onTap: () => unawaited(_menu(context, ref)),
              child: SizedBox.square(
                dimension: 48,
                child: Icon(Icons.more_vert, color: tokens.color.ink),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _menu(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final document = entry.document;
    final choice = await Adaptive.showSheet<_Choice>(
      context: context,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SgText(document.title, role: SgTextRole.title),
            const SizedBox(height: 8),
            for (final (choice, label) in <(_Choice, String)>[
              (_Choice.rename, l10n.myDocumentsRename),
              (_Choice.delete, l10n.myDocumentsDelete),
            ])
              SgButton(
                label: label,
                kind: SgButtonKind.text,
                onPressed: () => Navigator.of(sheet).pop(choice),
              ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    final documents = ref.read(documentRepositoryProvider);
    switch (choice) {
      case _Choice.rename:
        final title = (await Adaptive.showSheet<String>(
          context: context,
          builder: (_) => _RenameSheet(initial: document.title),
        ))?.trim();
        if (title == null || title.isEmpty || title == document.title) return;
        await documents.rename(document.id, title);
      // FR-D3-02: asked first; the words added and their sentences stay.
      case _Choice.delete:
        final sure = await Adaptive.showConfirm(
          context: context,
          title: l10n.myDocumentsDeleteTitle(document.title),
          message: l10n.myDocumentsDeleteBody,
          confirmLabel: l10n.myDocumentsDelete,
          cancelLabel: l10n.myDocumentsDeleteKeep,
          destructive: true,
        );
        if (sure != true) return;
        await documents.delete(document.id);
        if (context.mounted) {
          SgToast.show(context, l10n.myDocumentsDeleted(document.title));
        }
      case null:
        return;
    }
  }
}

enum _Choice { rename, delete }

/// The title, in a sheet: popped with what was typed on *Save*, with nothing
/// when the sheet is dismissed. Me's name sheet, for a document.
class _RenameSheet extends StatefulWidget {
  const _RenameSheet({required this.initial});

  final String initial;

  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
  late final TextEditingController _title = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_title.text);

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final edge = OutlineInputBorder(
      borderRadius: BorderRadius.circular(tokens.shape.button),
      borderSide: BorderSide(color: tokens.color.ink, width: 2),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SgText(l10n.myDocumentsRename, role: SgTextRole.title),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            autofocus: true,
            // ponytail: 80 characters, D1's title cut (documentTitle) is 60.
            maxLength: 80,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            style: SgText.styleFor(tokens, SgTextRole.bodyLarge),
            decoration: InputDecoration(
              labelText: l10n.myDocumentsRename,
              counterText: '',
              filled: true,
              fillColor: tokens.surface.cardStrong,
              border: edge,
              enabledBorder: edge,
              focusedBorder: edge,
            ),
          ),
          const SizedBox(height: 12),
          SgButton(label: l10n.meNameSave, onPressed: _save),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: <Widget>[
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: tokens.surface.muted,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.description_outlined,
              size: 34,
              color: tokens.color.ink,
            ),
          ),
        ),
        const SizedBox(height: 18),
        SgText(
          l10n.myDocumentsEmptyTitle,
          role: SgTextRole.title,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        SgText(
          l10n.myDocumentsEmptyBody,
          role: SgTextRole.body,
          textAlign: TextAlign.center,
          color: tokens.color.textSecondary,
        ),
        const SizedBox(height: 18),
        SgButton(
          label: l10n.myDocumentsNew,
          onPressed: () => DocImportRoute.open(context),
        ),
      ],
    );
  }
}
