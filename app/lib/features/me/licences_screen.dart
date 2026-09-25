import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:flutter/foundation.dart' show LicenseRegistry;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'licences_screen.g.dart';

/// One licence M8 lists: what it covers, the licence's name, and its text —
/// a bundled asset's, or a package's from the registry.
typedef Licence = ({String name, String kind, String? asset, String? text});

/// FR-M8-01: the on-device models' licences, bundled in full, as their
/// makers publish them (`Supertone/supertonic-3`, `tencent/HY-MT1.5-1.8B`).
const List<Licence> modelLicences = <Licence>[
  (
    name: 'Supertonic 3',
    kind: 'OpenRAIL-M',
    asset: 'assets/licences/Supertonic3-OpenRAIL-M.txt',
    text: null,
  ),
  (
    name: 'Hy-MT 1.5 (1.8B)',
    kind: 'Tencent HY Community License',
    asset: 'assets/licences/HY-MT1.5-Tencent-HY.txt',
    text: null,
  ),
];

/// FR-M8-01: the bundled fonts' licence, in full.
const List<Licence> fontLicences = <Licence>[
  (
    name: 'Inter',
    kind: 'SIL Open Font License 1.1',
    asset: 'assets/licences/Inter-OFL.txt',
    text: null,
  ),
  (
    name: 'Noto Sans Bengali',
    kind: 'SIL Open Font License 1.1',
    asset: 'assets/licences/NotoSansBengali-OFL.txt',
    text: null,
  ),
];

/// The app's packages and their licences, from Flutter's registry: each
/// package once, in name order whatever the case ("abseil-cpp", "OpenSSL",
/// "sqflite"), its texts joined.
@riverpod
Future<List<Licence>> packageLicences(Ref ref) async {
  final texts = <String, List<String>>{};
  await for (final entry in LicenseRegistry.licenses) {
    final text = entry.paragraphs.map((paragraph) => paragraph.text).join('\n');
    for (final package in entry.packages) {
      (texts[package] ??= <String>[]).add(text);
    }
  }
  return <Licence>[
    for (final name
        in texts.keys.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())))
      (
        name: name,
        kind: licenceKind(texts[name]!.first) ?? '',
        asset: null,
        text: texts[name]!.join('\n\n'),
      ),
  ];
}

/// A bundled licence's text.
@riverpod
Future<String> licenceText(Ref ref, String asset) =>
    rootBundle.loadString(asset);

/// The licence [text] is, when it is one of the common ones, for the line
/// under a package: the registry gives the text, not its name.
String? licenceKind(String text) {
  bool has(String words) => text.contains(words);
  if (has('Apache License')) return 'Apache-2.0';
  if (has('Permission is hereby granted, free of charge')) return 'MIT';
  if (has('Redistribution and use in source and binary forms')) {
    return has('Neither the name') || has('names of its contributors')
        ? 'BSD-3-Clause'
        : 'BSD-2-Clause';
  }
  if (has('Mozilla Public License')) return 'MPL-2.0';
  if (has('SIL OPEN FONT LICENSE')) return 'OFL-1.1';
  if (has('Permission to use, copy, modify, and/or distribute')) return 'ISC';
  return null;
}

/// M8 · Licences (`about-licences.md`, the Licences artboards): the models,
/// the fonts and the packages, each opening its text in full.
class LicencesScreen extends ConsumerWidget {
  const LicencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final packages = ref.watch(packageLicencesProvider).value ?? <Licence>[];
    // A section's title, then its licences.
    final rows = <Object>[
      l10n.licencesModels,
      ...modelLicences,
      l10n.licencesFonts,
      ...fontLicences,
      l10n.licencesPackages,
      ...packages,
    ];

    final scaffold = AdaptiveScaffold(
      title: l10n.licencesTitle,
      leading: AdaptiveBackButton(
        label: l10n.aboutTitle,
        colour: context.isCupertino ? null : tokens.color.ink,
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
      // Built as it scrolls: the registry lists some 200 packages.
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: rows.length,
        itemBuilder: (context, i) => switch (rows[i]) {
          final String title => _Section(title),
          final Licence licence => _Row(licence),
          _ => const SizedBox.shrink(),
        },
      ),
    );
    return tokens.isGlass
        ? AuroraBackdrop(leading: tokens.color.accent, child: scaffold)
        : scaffold;
  }
}

/// A section's caption, in capitals as the artboard draws them.
class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: DpText(
          title.toUpperCase(),
          semanticsLabel: title,
          role: DpTextRole.caption,
          weight: 700,
          letterSpacing: 0.6,
          color: tokens.color.textSecondary,
        ),
      ),
    );
  }
}

/// One licence: its name and kind, opening its text.
class _Row extends StatelessWidget {
  const _Row(this.licence);

  final Licence licence;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final kind = licence.kind.isEmpty ? l10n.licencesOther : licence.kind;
    return Semantics(
      container: true,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Adaptive.showSheet<void>(
          context: context,
          builder: (sheet) => _Text(licence: licence, kind: kind),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: tokens.surface.outline)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        DpText(licence.name, role: DpTextRole.body),
                        DpText(
                          kind,
                          role: DpTextRole.caption,
                          color: tokens.color.textSecondary,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: tokens.color.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// FR-M8-01: a licence's text in full, in a sheet that scrolls.
class _Text extends ConsumerWidget {
  const _Text({required this.licence, required this.kind});

  final Licence licence;
  final String kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final asset = licence.asset;
    final text = asset == null
        ? licence.text
        : ref.watch(licenceTextProvider(asset)).value;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Semantics(
              header: true,
              child: DpText(licence.name, role: DpTextRole.title),
            ),
            DpText(
              kind,
              role: DpTextRole.caption,
              color: tokens.color.textSecondary,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: DpText(text ?? '', role: DpTextRole.caption),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
