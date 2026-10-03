import 'dart:async';

import 'package:flutter/services.dart' show Clipboard;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/components/sg_button.dart';
import 'package:sogda/core/components/sg_feedback.dart';
import 'package:sogda/core/components/sg_pill.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/aurora_backdrop.dart';
import 'package:sogda/core/theme/sg_surface.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/domain/documents/clean.dart';
import 'package:sogda/domain/documents/ocr.dart';
import 'package:sogda/domain/documents/tokens.dart';
import 'package:sogda/features/search/search_header.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/router/routes.dart';
import 'package:sogda/services/pdf_text.dart';

/// D1, Learn from a document (`docs/04-screens/doc-import.md`):
/// text in, pasted or shared from another app (#1227), or photographed and
/// read on the phone (#1229), or a PDF's text layer (#1228).
class DocImportScreen extends ConsumerStatefulWidget {
  const DocImportScreen({super.key, this.arrival});

  /// Set when "Share → Sogda" opened it: the share's number, a new one for
  /// each, so a second share onto an open D1 is read too.
  final String? arrival;

  @override
  ConsumerState<DocImportScreen> createState() => _DocImportScreenState();
}

enum _Stage {
  choose,
  paste,
  camera,
  reading,
  check,
  processing,
  notGerman,
  noText,
  scan,
  locked,
  failed,
}

/// FR-D1-02: the most pages D1 reads.
const int docMaxPages = 30;

class _DocImportScreenState extends ConsumerState<DocImportScreen> {
  final TextEditingController _paste = TextEditingController();

  /// *Check the text*'s page, its unsure words marked (FR-D1-03).
  final _MarkedText _check = _MarkedText();
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    // Copied in another app and back: Paste follows the clipboard.
    onShow: () => unawaited(_checkClipboard()),
  );

  _Stage _stage = _Stage.choose;

  /// Null until asked: *Paste text* shows as on rather than flashing off.
  bool? _clipboardHasText;

  /// What's being read: `paste`, `share`, `photo` or `pdf`
  /// (`documents.source`).
  String _source = 'paste';
  String _body = '';

  /// The PDF chosen (#1228): its file, its name for the intro, how many of
  /// its pages are being read, and how many were.
  String _pdfPath = '';

  /// What this reading cut (FR-D1-02), for D2 to say (#1320): the text past
  /// its 20,000 characters, or the photos or PDF past their 30 pages.
  bool _textCut = false;
  bool _pagesCut = false;
  String _pdfName = '';
  int _readingOf = 0;
  int _pdfPages = 0;

  /// The PDF reader, read on first use and kept for [dispose], where `ref`
  /// can't be read: a copy to drop there means it was read already.
  late final PdfText _pdf = ref.read(pdfTextProvider);

  /// The photos, in page order, as they were taken or chosen (#1229).
  List<String> _photos = const <String>[];

  /// Each photo as OCR read it, and its text as the learner left it.
  final List<OcrPage> _pages = <OcrPage>[];
  final List<String> _texts = <String>[];

  /// The page being read, from 1, for «Reading page 2 of 4…».
  int _readingPage = 0;

  /// The page *Check the text* shows.
  int _checkPage = 0;

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
    // Left from an error panel: the copy a Retry would have read goes too.
    _dropPdf();
    _lifecycle.dispose();
    _paste.dispose();
    _check.dispose();
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
    // Shared photos (#1332): their copies, read as chosen ones are.
    final images = await ref.read(sharedTextProvider).takeImages();
    if (!mounted) return;
    if (images != null && images.pages.isNotEmpty) {
      _dropPdf();
      _readChosen(images.pages, images.of);
      return;
    }
    // A shared PDF (#1228): its copy, read as a chosen one is.
    final pdf = await ref.read(sharedTextProvider).takePdf();
    if (!mounted) return;
    if (pdf != null) {
      _dropPdf();
      _pdfPath = pdf;
      _pdfName = pdf.split(RegExp(r'[/\\]')).last;
      unawaited(_readPdf());
      return;
    }
    final text = await ref.read(sharedTextProvider).take();
    if (!mounted || text == null || text.trim().isEmpty) return;
    unawaited(_read(<String>[text], source: 'share'));
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

  /// *Take photos*: the camera, a page at a time, up to [docMaxPages].
  Future<void> _takePage() async {
    final photo = await ref.read(pagePhotosProvider).take();
    if (!mounted) return;
    if (photo != null && _photos.length < docMaxPages) {
      _photos = <String>[..._photos, photo];
    }
    setState(() => _stage = _photos.isEmpty ? _Stage.choose : _Stage.camera);
  }

  /// *Choose images*: several from the phone, then straight to reading.
  Future<void> _chooseImages() async {
    final chosen = await ref.read(pagePhotosProvider).choose();
    if (!mounted || chosen.isEmpty) return;
    _readChosen(chosen, chosen.length);
  }

  /// [photos], the first [docMaxPages] of the [of] chosen or shared, read.
  void _readChosen(List<String> photos, int of) {
    _photos = photos.take(docMaxPages).toList();
    _pagesCut = of > docMaxPages;
    if (_pagesCut) {
      SgToast.show(
        context,
        AppLocalizations.of(context).docImportTooManyPages(docMaxPages),
      );
    }
    unawaited(_readPhotos());
  }

  /// *Choose a PDF*: the file picker, then its text layer.
  Future<void> _choosePdf() async {
    final path = await _pdf.choose();
    if (!mounted || path == null) return;
    _pdfPath = path;
    _pdfName = path.split(RegExp(r'[/\\]')).last;
    unawaited(_readPdf());
  }

  /// FR-D1-01: the PDF's text layer, page by page, up to 30 (BR-DOC-02),
  /// on the phone (#1228). A scan goes to the photos; *Cancel* stops between
  /// two pages (FR-D1-05).
  Future<void> _readPdf() async {
    final run = ++_run;
    setState(() {
      _source = 'pdf';
      _body = '';
      _readingPage = 0;
      _readingOf = 0;
      _stage = _Stage.reading;
    });
    try {
      final read = await readPdf(
        _pdf,
        _pdfPath,
        onOpen: (pages) {
          // A stale run's late answer says nothing about this one (agent-1).
          if (!mounted || run != _run) return;
          _pagesCut = pages > maxPdfPages;
          if (pages > maxPdfPages) {
            SgToast.show(
              context,
              AppLocalizations.of(context).docImportTooManyPages(maxPdfPages),
            );
          }
        },
        onPage: (page, of) {
          if (mounted && run == _run) {
            setState(() {
              _readingPage = page;
              _readingOf = of;
            });
          }
        },
        cancelled: () => !mounted || run != _run,
      );
      if (read == null || !mounted || run != _run) return;
      // Its text is out (or there's none): the copy isn't needed again.
      _dropPdf();
      if (read.scan) {
        setState(() => _stage = _Stage.scan);
        return;
      }
      _pdfPages = read.pages.length;
      unawaited(_read(read.pages, source: 'pdf'));
    } on PdfLocked {
      if (!mounted || run != _run) return;
      _dropPdf();
      setState(() => _stage = _Stage.locked);
    } on Object {
      if (mounted && run == _run) setState(() => _stage = _Stage.failed);
    }
  }

  /// FR-D1-01: each photo read on the phone, in turn (BR-DOC-01).
  Future<void> _readPhotos() async {
    final run = ++_run;
    _pages.clear();
    _texts.clear();
    setState(() {
      _source = 'photo';
      _stage = _Stage.reading;
    });
    try {
      for (final (i, photo) in _photos.indexed) {
        setState(() => _readingPage = i + 1);
        final page = await ref.read(pagePhotosProvider).read(photo);
        if (!mounted || run != _run) return;
        _pages.add(page);
        _texts.add(page.text);
      }
    } on Object {
      if (mounted && run == _run) setState(() => _stage = _Stage.failed);
      return;
    }
    _nextCheck(0);
  }

  /// FR-D1-03: the next page from [from] read below the line opens *Check
  /// the text*. With none left, the pages are processed as the learner left
  /// them.
  void _nextCheck(int from) {
    for (var i = from; i < _pages.length; i++) {
      if (!needsCheck(<OcrPage>[_pages[i]])) continue;
      _check.show(_texts[i], unsureWords(<OcrPage>[_pages[i]]));
      setState(() {
        _checkPage = i;
        _stage = _Stage.check;
      });
      return;
    }
    if (_texts.every((text) => text.trim().isEmpty)) {
      setState(() => _stage = _Stage.noText);
      return;
    }
    unawaited(_read(_texts, source: 'photo'));
  }

  /// *Continue*: the page as corrected.
  void _confirmPage() {
    _texts[_checkPage] = _check.text;
    _nextCheck(_checkPage + 1);
  }

  /// *Take again*: the hard page photographed again, then read.
  Future<void> _retake() async {
    final i = _checkPage;
    final photo = await ref.read(pagePhotosProvider).take();
    if (!mounted || photo == null) return;
    final run = ++_run;
    unawaited(ref.read(pagePhotosProvider).discard(<String>[_photos[i]]));
    setState(() {
      _photos = <String>[..._photos]..[i] = photo;
      _readingPage = i + 1;
      _stage = _Stage.reading;
    });
    try {
      final page = await ref.read(pagePhotosProvider).read(photo);
      if (!mounted || run != _run) return;
      _pages[i] = page;
      _texts[i] = page.text;
    } on Object {
      if (mounted && run == _run) setState(() => _stage = _Stage.failed);
      return;
    }
    _nextCheck(i);
  }

  /// FR-D1-02, FR-D1-04: [pages] cleaned into one text and cut to the
  /// limit, then checked for German before anything is saved.
  Future<void> _read(List<String> pages, {required String source}) async {
    final run = ++_run;
    final limited = limitText(cleanPages(pages));
    _textCut = limited.cut;
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
          pageCount: switch (_source) {
            'photo' => _photos.length,
            'pdf' => _pdfPages,
            _ => 1,
          },
        );
    // BR-DOC-05: the photos stay with it while *Save original images* is
    // on. Best effort: the document is saved either way.
    if (_source == 'photo' &&
        ref.read(settingsProvider).read(SettingKeys.docSaveImages)) {
      try {
        await ref.read(documentRepositoryProvider).saveImages(id, _photos);
      } on Object catch (error) {
        debugPrint('D1: photos not kept: $error');
      }
    }
    // The copies image_picker made, metadata and all, aren't kept twice.
    if (_source == 'photo') {
      unawaited(ref.read(pagePhotosProvider).discard(_photos));
    }
    if (!mounted || run != _run) return;
    // #1320: D2 says what was cut; this screen's note goes with it.
    DocWordsRoute.instead(
      context,
      id,
      cut: _textCut
          ? 'text'
          : (_source == 'photo' || _source == 'pdf') && _pagesCut
          ? 'pages'
          : null,
    );
  }

  /// BR-DOC-05: the PDF's copy (the picker's, or a share's in
  /// `cache/shared`) goes once D1 is done with it. A failed read keeps it
  /// for *Retry*, until another file, *Cancel* or leaving D1.
  void _dropPdf() {
    if (_pdfPath.isEmpty) return;
    unawaited(_pdf.discard(_pdfPath));
    _pdfPath = '';
  }

  /// FR-D1-05: back to the choices, with nothing saved.
  void _cancel() {
    if (_photos.isNotEmpty) {
      unawaited(ref.read(pagePhotosProvider).discard(_photos));
    }
    _dropPdf();
    setState(() {
      _run++;
      _photos = const <String>[];
      _stage = _Stage.choose;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final intro = switch (_stage) {
      _Stage.check => l10n.docImportCheckIntro(_checkPage + 1),
      _Stage.scan || _Stage.locked => _pdfName,
      _Stage.reading when _source == 'pdf' => _pdfName,
      _Stage.camera ||
      _Stage.reading ||
      _Stage.noText => l10n.docImportPhotos(_photos.length),
      _Stage.processing ||
      _Stage.notGerman ||
      _Stage.failed => switch (_source) {
        'share' => l10n.docImportShared,
        'photo' => l10n.docImportPhotos(_photos.length),
        'pdf' => _pdfName,
        _ => l10n.docImportPasted,
      },
      _ => l10n.docImportIntro,
    };
    final body = switch (_stage) {
      _Stage.choose => _Choices(
        clipboardHasText: _clipboardHasText ?? true,
        onPaste: () => unawaited(_openPaste()),
        onTakePhotos: () => unawaited(_takePage()),
        onChooseImages: () => unawaited(_chooseImages()),
        onChoosePdf: () => unawaited(_choosePdf()),
      ),
      _Stage.camera => _Camera(
        pages: _photos.length,
        onAddPage: _photos.length < docMaxPages
            ? () => unawaited(_takePage())
            : null,
        onDone: () => unawaited(_readPhotos()),
      ),
      _Stage.reading => _Processing(
        reading: (
          page: _readingPage,
          of: _source == 'pdf' ? _readingOf : _photos.length,
        ),
        onCancel: _cancel,
      ),
      _Stage.check => _Check(
        controller: _check,
        onContinue: _confirmPage,
        onTakeAgain: () => unawaited(_retake()),
      ),
      _Stage.noText => SgErrorPanel(
        message: l10n.docImportNoText,
        retryLabel: l10n.docImportTakeAgain,
        onRetry: _cancel,
      ),
      // A PDF with no text layer: its pages are pictures, for the photo path.
      _Stage.scan => SgErrorPanel(
        message: l10n.docImportPdfScan,
        retryLabel: l10n.docImportChooseImages,
        onRetry: () => unawaited(_chooseImages()),
      ),
      _Stage.locked => SgErrorPanel(
        message: l10n.docImportPdfLocked,
        retryLabel: l10n.docImportChoosePdf,
        onRetry: () => unawaited(_choosePdf()),
      ),
      _Stage.paste => _PasteBox(
        controller: _paste,
        onRead: _paste.text.trim().isEmpty
            ? null
            : () => unawaited(_read(<String>[_paste.text], source: 'paste')),
      ),
      _Stage.processing => _Processing(onCancel: _cancel),
      _Stage.notGerman => _NotGerman(
        onContinue: () => unawaited(_save(_run)),
        onCancel: _cancel,
      ),
      _Stage.failed => SgErrorPanel(
        message: l10n.docImportFailed,
        retryLabel: l10n.retry,
        onRetry: () => unawaited(
          _source == 'photo' && _texts.length < _photos.length
              ? _readPhotos()
              // The PDF failed while it was read: read it again.
              : _source == 'pdf' && _body.isEmpty
              ? _readPdf()
              : _read(<String>[_body], source: _source),
        ),
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
          SearchHeader(
            title: _stage == _Stage.check
                ? l10n.docImportCheckTitle
                : l10n.docImportTitle,
            intro: intro,
          ),
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

/// The ways in: photos (#1229), a PDF (#1228) and text (#1227), in the
/// artboard's order.
class _Choices extends StatelessWidget {
  const _Choices({
    required this.clipboardHasText,
    required this.onPaste,
    required this.onTakePhotos,
    required this.onChooseImages,
    required this.onChoosePdf,
  });

  final bool clipboardHasText;
  final VoidCallback onPaste;
  final VoidCallback onTakePhotos;
  final VoidCallback onChooseImages;
  final VoidCallback onChoosePdf;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Choice(
          icon: Icons.photo_camera_outlined,
          title: l10n.docImportTakePhotos,
          detail: l10n.docImportTakePhotosDetail,
          onTap: onTakePhotos,
        ),
        const SizedBox(height: 12),
        _Choice(
          icon: Icons.image_outlined,
          title: l10n.docImportChooseImages,
          detail: l10n.docImportChooseImagesDetail,
          onTap: onChooseImages,
        ),
        const SizedBox(height: 12),
        _Choice(
          icon: Icons.picture_as_pdf_outlined,
          title: l10n.docImportChoosePdf,
          detail: l10n.docImportChoosePdfDetail(maxPdfPages),
          onTap: onChoosePdf,
        ),
        const SizedBox(height: 12),
        _Choice(
          icon: Icons.content_paste,
          title: l10n.docImportPaste,
          detail: clipboardHasText
              ? l10n.docImportPasteDetail
              : l10n.docImportPasteEmpty,
          onTap: clipboardHasText ? onPaste : null,
        ),
        const SizedBox(height: 14),
        // A node of its own, so it's read after the choices, where it's
        // drawn, not as their container's label (#1343).
        Semantics(
          container: true,
          child: Row(
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
            // Six lines that scroll: at 200 % text the whole box still fits
            // between the status bar and the keyboard.
            minLines: 6,
            maxLines: 6,
            scrollPadding: _belowStatusBar(context),
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

/// "Reading page 2 of 4…" or "Finding your words…", with *Cancel*
/// (FR-D1-05).
class _Processing extends StatelessWidget {
  const _Processing({required this.onCancel, this.reading});

  final VoidCallback onCancel;

  /// The photo being read, of how many; null once the words are being found.
  final ({int page, int of})? reading;

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
                  switch (reading) {
                    (:final page, :final of) => l10n.docImportReadingPage(
                      page,
                      of,
                    ),
                    null => l10n.docImportFinding,
                  },
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
                      value: switch (reading) {
                        (:final page, :final of) => (page - 1) / of,
                        null when MediaQuery.disableAnimationsOf(context) =>
                          0.5,
                        null => null,
                      },
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

/// *Take photos*' pages so far, with *Add a page* and *Done*.
class _Camera extends StatelessWidget {
  const _Camera({
    required this.pages,
    required this.onAddPage,
    required this.onDone,
  });

  final int pages;

  /// Null at [docMaxPages].
  final VoidCallback? onAddPage;
  final VoidCallback onDone;

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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(
            children: <Widget>[
              for (var page = 1; page <= pages; page++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.check, size: 20, color: tokens.color.ink),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SgText(
                          l10n.docImportPage(page),
                          role: SgTextRole.body,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (onAddPage == null) ...<Widget>[
          const SizedBox(height: 8),
          SgText(
            l10n.docImportTooManyPages(docMaxPages),
            role: SgTextRole.caption,
            color: tokens.color.textSecondary,
          ),
        ],
        const SizedBox(height: 24),
        SgButton(label: l10n.docImportDone, onPressed: onDone),
        const SizedBox(height: 8),
        SgButton(
          label: l10n.docImportAddPage,
          kind: SgButtonKind.secondary,
          onPressed: onAddPage,
        ),
      ],
    );
  }
}

/// FR-D1-03, *Check the text*: a page read with little confidence, its
/// unsure words marked, editable; what the learner leaves is what's read.
class _Check extends StatelessWidget {
  const _Check({
    required this.controller,
    required this.onContinue,
    required this.onTakeAgain,
  });

  final _MarkedText controller;
  final VoidCallback onContinue;
  final VoidCallback onTakeAgain;

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
        // The pill goes under the heading when both don't fit (200 %).
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: <Widget>[
            ExcludeSemantics(
              child: SgText(
                l10n.docImportTheText.toUpperCase(),
                role: SgTextRole.caption,
                weight: 700,
                letterSpacing: 0.6,
                color: tokens.color.textSecondary,
              ),
            ),
            // As the learner fixes them.
            ListenableBuilder(
              listenable: controller,
              builder: (context, _) => controller.unsure == 0
                  ? const SizedBox.shrink()
                  : SgPill(
                      label: l10n.docImportCheckCount(controller.unsure),
                      fill: tokens.color.hard.withValues(alpha: 0.3),
                      small: true,
                    ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Semantics(
          label: l10n.docImportTextLabel,
          child: TextField(
            controller: controller,
            minLines: 4,
            maxLines: 6,
            scrollPadding: _belowStatusBar(context),
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
        const SizedBox(height: 8),
        SgText(
          l10n.docImportCheckNote,
          role: SgTextRole.caption,
          color: tokens.color.textSecondary,
        ),
        const SizedBox(height: 24),
        SgButton(label: l10n.docImportContinue, onPressed: onContinue),
        const SizedBox(height: 8),
        SgButton(
          label: l10n.docImportTakeAgain,
          kind: SgButtonKind.secondary,
          onPressed: onTakeAgain,
        ),
      ],
    );
  }
}

/// A page's text with the words OCR was unsure of marked, as the
/// DocImportCorrect artboard has them; a word the learner edits is no
/// longer marked.
class _MarkedText extends TextEditingController {
  Set<String> _marked = const <String>{};

  /// How many of the marked words the text still holds.
  int get unsure =>
      RegExp(r'\S+')
          .allMatches(text)
          .where((m) => _marked.contains(m[0]))
          .length;

  void show(String page, Set<String> marked) {
    _marked = marked;
    text = page;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    required bool withComposing,
    TextStyle? style,
  }) {
    // While a keyboard composes, its own underline wins.
    if (_marked.isEmpty || (withComposing && value.composing.isValid)) {
      return super.buildTextSpan(
        context: context,
        withComposing: withComposing,
        style: style,
      );
    }
    final tokens = context.tokens;
    final mark = TextStyle(
      backgroundColor: tokens.color.hard.withValues(alpha: 0.3),
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dotted,
      decorationColor: tokens.color.almostText,
    );
    final spans = <TextSpan>[];
    text.splitMapJoin(
      RegExp(r'\S+'),
      onMatch: (m) {
        spans.add(
          TextSpan(text: m[0], style: _marked.contains(m[0]) ? mark : null),
        );
        return '';
      },
      onNonMatch: (gap) {
        spans.add(TextSpan(text: gap));
        return '';
      },
    );
    return TextSpan(style: style, children: spans);
  }
}

/// A box revealed for the keyboard comes to rest below the status bar: D1's
/// list runs under it (`SearchHeader`), as R2's does (#590).
EdgeInsets _belowStatusBar(BuildContext context) =>
    EdgeInsets.fromLTRB(20, 20 + MediaQuery.paddingOf(context).top, 20, 20);
