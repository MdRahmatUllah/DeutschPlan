import 'dart:async';

import 'package:flutter/services.dart' show Clipboard;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/components/sg_button.dart';
import 'package:sogda/core/components/sg_feedback.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/aurora_backdrop.dart';
import 'package:sogda/core/theme/sg_surface.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/domain/documents/clean.dart';
import 'package:sogda/domain/documents/tokens.dart';
import 'package:sogda/features/search/search_header.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/router/routes.dart';

/// D1, Learn from a document (`docs/04-screens/planned/doc-import.md`):
/// text in, pasted or shared from another app (#1227). Photos and PDFs join
/// its choices in #1228 and #1229.
class DocImportScreen extends ConsumerStatefulWidget {
  const DocImportScreen({super.key, this.arrival});

  /// Set when "Share → Sogda" opened it: the share's number, a new one for
  /// each, so a second share onto an open D1 is read too.
  final String? arrival;

  @override
  ConsumerState<DocImportScreen> createState() => _DocImportScreenState();
}

enum _Stage { choose, paste, processing, notGerman, failed }

class _DocImportScreenState extends ConsumerState<DocImportScreen> {
  final TextEditingController _paste = TextEditingController();
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    // Copied in another app and back: Paste follows the clipboard.
    onShow: () => unawaited(_checkClipboard()),
  );

  _Stage _stage = _Stage.choose;

  /// Null until asked: *Paste text* shows as on rather than flashing off.
  bool? _clipboardHasText;

  /// What's being read: `paste` or `share` (`documents.source`).
  String _source = 'paste';
  String _body = '';

  /// Bumped by *Cancel*: a check still running then saves nothing.
  int _run = 0;

  @override
  void initState() {
    super.initState();
    _lifecycle;
    _paste.addListener(_onPasteChanged);
    unawaited(_checkClipboard());
    if (widget.arrival != null) unawaited(_takeShare());
  }

  @override
  void didUpdateWidget(DocImportScreen old) {
    super.didUpdateWidget(old);
    if (widget.arrival != null && widget.arrival != old.arrival) {
      unawaited(_takeShare());
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _paste.dispose();
    super.dispose();
  }

  void _onPasteChanged() => setState(() {});

  Future<void> _checkClipboard() async {
    bool has;
    try {
      has = await Clipboard.hasStrings();
    } on Exception {
      // A phone that won't say keeps Paste on: the paste itself tells.
      has = true;
    }
    if (mounted) setState(() => _clipboardHasText = has);
  }

  /// FR-D1-01: the shared text, straight into processing. None (a restored
  /// launch, or a second read of the same share) leaves D1 as it is.
  Future<void> _takeShare() async {
    final text = await ref.read(sharedTextProvider).take();
    if (!mounted || text == null || text.trim().isEmpty) return;
    unawaited(_read(text, source: 'share'));
  }

  /// *Paste text*: the clipboard, in an editable box first.
  Future<void> _openPaste() async {
    String text;
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    } on Exception {
      text = '';
    }
    if (!mounted) return;
    if (text.trim().isEmpty) {
      setState(() => _clipboardHasText = false);
      return;
    }
    _paste.text = text;
    setState(() => _stage = _Stage.paste);
  }

  /// FR-D1-02, FR-D1-04: [raw] cleaned and cut to the limit, then checked
  /// for German before anything is saved.
  Future<void> _read(String raw, {required String source}) async {
    final run = ++_run;
    final limited = limitText(cleanPages(<String>[raw]));
    setState(() {
      _source = source;
      _body = limited.text;
      _stage = _Stage.processing;
    });
    final l10n = AppLocalizations.of(context);
    if (limited.cut) SgToast.show(context, l10n.docImportCut(docMaxChars));
    try {
      final share = await ref
          .read(documentRepositoryProvider)
          .germanShareOf(limited.text);
      if (!mounted || run != _run) return;
      if (share < germanThreshold) {
        setState(() => _stage = _Stage.notGerman);
        return;
      }
      await _save(run);
    } on Object {
      if (mounted && run == _run) setState(() => _stage = _Stage.failed);
    }
  }

  /// FR-D1-06: the text saved, then D2 opens on it and finds its words.
  Future<void> _save(int run) async {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final today = ref.read(clockProvider)();
    final id = await ref
        .read(documentRepositoryProvider)
        .create(
          title:
              documentTitle(_body) ??
              l10n.docImportUntitled(DateFormat.MMMd(locale).format(today)),
          source: _source,
          body: _body,
        );
    if (!mounted || run != _run) return;
    DocWordsRoute.instead(context, id);
  }

  /// FR-D1-05: back to the choices, with nothing saved.
  void _cancel() => setState(() {
    _run++;
    _stage = _Stage.choose;
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final intro = switch (_stage) {
      _Stage.processing || _Stage.notGerman || _Stage.failed =>
        _source == 'share' ? l10n.docImportShared : l10n.docImportPasted,
      _ => l10n.docImportIntro,
    };
    final body = switch (_stage) {
      _Stage.choose => _Choices(
        clipboardHasText: _clipboardHasText ?? true,
        onPaste: () => unawaited(_openPaste()),
      ),
      _Stage.paste => _PasteBox(
        controller: _paste,
        onRead: _paste.text.trim().isEmpty
            ? null
            : () => unawaited(_read(_paste.text, source: 'paste')),
      ),
      _Stage.processing => _Processing(onCancel: _cancel),
      _Stage.notGerman => _NotGerman(
        onContinue: () => unawaited(_save(_run)),
        onCancel: _cancel,
      ),
      _Stage.failed => SgErrorPanel(
        message: l10n.docImportFailed,
        retryLabel: l10n.retry,
        onRetry: () => unawaited(_read(_body, source: _source)),
      ),
    };
    final scaffold = AdaptiveScaffold(
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
      statusBarColour: tokens.color.die,
      body: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          SearchHeader(title: l10n.docImportTitle, intro: intro),
          Padding(padding: const EdgeInsets.all(16), child: body),
        ],
      ),
    );
    return PopScope(
      // Back from the box returns to the choices, as from processing.
      canPop: _stage == _Stage.choose,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: tokens.isGlass
          ? AuroraBackdrop(leading: tokens.color.die, child: scaffold)
          : scaffold,
    );
  }
}

/// The ways in. Text only for now; photos and PDFs are #1228 and #1229.
class _Choices extends StatelessWidget {
  const _Choices({required this.clipboardHasText, required this.onPaste});

  final bool clipboardHasText;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Choice(
          icon: Icons.content_paste,
          title: l10n.docImportPaste,
          detail: clipboardHasText
              ? l10n.docImportPasteDetail
              : l10n.docImportPasteEmpty,
          onTap: clipboardHasText ? onPaste : null,
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                Icons.lock_outline,
                size: 18,
                color: tokens.color.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SgText(
                l10n.docImportPrivacy,
                role: SgTextRole.caption,
                color: tokens.color.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One of D1's large choices: an icon tile, what it is, and where from.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;

  /// Null when it's off: the detail says why.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final on = onTap != null;
    return Semantics(
      container: true,
      button: true,
      enabled: on,
      child: SgSurface(
        kind: SgSurfaceKind.bar,
        onTap: onTap,
        radius: 16,
        padding: const EdgeInsets.all(14),
        child: Opacity(
          opacity: on ? 1 : 0.55,
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tokens.surface.muted,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 22, color: tokens.color.ink),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SgText(title, role: SgTextRole.body, weight: 700),
                    SgText(
                      detail,
                      role: SgTextRole.caption,
                      color: tokens.color.textSecondary,
                    ),
                  ],
                ),
              ),
              if (on)
                Icon(
                  Icons.chevron_right,
                  size: 22,
                  color: tokens.color.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The pasted text, editable, before it's read (`doc-import.md`).
class _PasteBox extends StatelessWidget {
  const _PasteBox({required this.controller, required this.onRead});

  final TextEditingController controller;
  final VoidCallback? onRead;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final edge = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: tokens.color.ink, width: 1.5),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          label: l10n.docImportTextLabel,
          child: TextField(
            controller: controller,
            minLines: 8,
            maxLines: 14,
            // German: the keyboard mustn't correct it into English.
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.multiline,
            style: SgText.styleFor(
              tokens,
              SgTextRole.body,
            ).copyWith(color: tokens.color.ink),
            decoration: InputDecoration(
              filled: true,
              fillColor: tokens.surface.cardStrong,
              contentPadding: const EdgeInsets.all(14),
              border: edge,
              enabledBorder: edge,
              focusedBorder: edge.copyWith(
                borderSide: BorderSide(color: tokens.color.ink, width: 2),
              ),
            ),
          ),
        ),
        if (controller.text.length > docMaxChars) ...<Widget>[
          const SizedBox(height: 8),
          SgText(
            l10n.docImportCut(docMaxChars),
            role: SgTextRole.caption,
            color: tokens.color.textSecondary,
          ),
        ],
        const SizedBox(height: 16),
        SgButton(label: l10n.docImportFind, onPressed: onRead),
      ],
    );
  }
}

/// "Finding your words…", with *Cancel* (FR-D1-05).
class _Processing extends StatelessWidget {
  const _Processing({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SgSurface(
          kind: SgSurfaceKind.bar,
          radius: 16,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Semantics(
                header: true,
                child: SgText(
                  l10n.docImportReading.toUpperCase(),
                  role: SgTextRole.caption,
                  weight: 700,
                  letterSpacing: 0.6,
                  color: tokens.color.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              Semantics(
                liveRegion: true,
                child: SgText(
                  l10n.docImportFinding,
                  role: SgTextRole.body,
                  weight: 600,
                ),
              ),
              const SizedBox(height: 8),
              ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: SizedBox(
                    height: 10,
                    child: LinearProgressIndicator(
                      // Still under reduced motion: a bar that sweeps is
                      // only motion.
                      value: MediaQuery.disableAnimationsOf(context)
                          ? 0.5
                          : null,
                      backgroundColor: tokens.surface.track,
                      color: tokens.color.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SgText(
          l10n.docImportOffline,
          role: SgTextRole.caption,
          color: tokens.color.textSecondary,
        ),
        const SizedBox(height: 24),
        SgButton(
          label: l10n.docImportCancel,
          kind: SgButtonKind.secondary,
          onPressed: onCancel,
        ),
      ],
    );
  }
}

/// FR-D1-04: a text that doesn't look German, before anything is saved.
class _NotGerman extends StatelessWidget {
  const _NotGerman({required this.onContinue, required this.onCancel});

  final VoidCallback onContinue;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SgCallout.text(
          l10n.docImportNotGermanBody,
          title: l10n.docImportNotGerman,
        ),
        const SizedBox(height: 24),
        SgButton(
          label: l10n.docImportContinueAnyway,
          kind: SgButtonKind.secondary,
          onPressed: onContinue,
        ),
        const SizedBox(height: 8),
        SgButton(
          label: l10n.docImportCancel,
          kind: SgButtonKind.text,
          onPressed: onCancel,
        ),
      ],
    );
  }
}
