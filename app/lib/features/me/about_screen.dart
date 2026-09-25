import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'about_screen.g.dart';

/// The app's version and build (FR-M9-01).
typedef AppVersion = ({String version, String build});

@riverpod
Future<AppVersion> appVersion(Ref ref) async {
  final info = await PackageInfo.fromPlatform();
  return (version: info.version, build: info.buildNumber);
}

/// The course's version, build day and size (FR-M9-01).
@riverpod
Future<ContentFacts> contentFacts(Ref ref) =>
    ref.watch(contentDaoProvider).facts();

/// Where *Contact* goes: the project's new-issue page, as a card's report
/// does. The app has no server or address of its own.
// ponytail: the report's destination (#100); an address, once there is one,
// is an owner's call (`team.py decision`).
final Uri contactUri = Uri.https(
  'github.com',
  '/MdRahmatUllah/DeutschPlan/issues/new',
);

/// `meta.content_version` ("202609251045") as About shows it: "2026.09".
String contentRelease(String version) => version.length >= 6
    ? '${version.substring(0, 4)}.${version.substring(4, 6)}'
    : version;

/// M9 · About & privacy (`about-licences.md`, the About artboards): the app
/// and course versions, the privacy statement, and the ways on — licences,
/// contact, the course.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final version = ref.watch(appVersionProvider).value;
    final facts = ref.watch(contentFactsProvider).value;
    final built = facts?.builtAt;

    final scaffold = AdaptiveScaffold(
      title: l10n.aboutTitle,
      leading: AdaptiveBackButton(
        label: l10n.tabMe,
        colour: context.isCupertino ? null : tokens.color.ink,
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          Row(
            children: <Widget>[
              const _Mark(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    DpText(l10n.appTitle, role: DpTextRole.title),
                    if (version != null && facts != null)
                      DpText(
                        built == null
                            ? l10n.aboutVersionUndated(
                                version.version,
                                version.build,
                                contentRelease(facts.version),
                              )
                            : l10n.aboutVersion(
                                version.version,
                                version.build,
                                contentRelease(facts.version),
                                // "21 Sep 2026", as M1 writes a day.
                                DateFormat(
                                  'd MMM y',
                                  locale,
                                ).format(built.toLocal()),
                              ),
                        role: DpTextRole.caption,
                        color: tokens.color.textSecondary,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DpSurface(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                DpText(
                  l10n.aboutPrivacy.toUpperCase(),
                  semanticsLabel: l10n.aboutPrivacy,
                  role: DpTextRole.caption,
                  weight: 700,
                  letterSpacing: 0.6,
                  color: tokens.color.textSecondary,
                ),
                const SizedBox(height: 8),
                DpText(l10n.aboutPrivacyText, role: DpTextRole.body),
              ],
            ),
          ),
          const SizedBox(height: 16),
          DpSurface(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: <Widget>[
                _Link(
                  title: l10n.aboutLicences,
                  note: l10n.aboutLicencesNote,
                  onTap: () => LicencesRoute.open(context),
                ),
                _Link(
                  title: l10n.aboutContact,
                  note: l10n.aboutContactNote,
                  onTap: () => ref.read(openWebProvider)(contactUri),
                ),
                _Link(
                  title: l10n.aboutContent,
                  note: facts == null
                      ? ''
                      : l10n.aboutContentCounts(
                          facts.words,
                          facts.grammar,
                          facts.sentences,
                        ),
                  last: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return tokens.isGlass
        ? AuroraBackdrop(leading: tokens.color.accent, child: scaffold)
        : scaffold;
  }
}

/// The "D" on Sun with the ink edge: the app's mark, as the artboard draws
/// it beside the name.
class _Mark extends StatelessWidget {
  const _Mark();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: 60,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.color.accent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tokens.color.ink, width: 2),
          ),
          child: Center(
            // The mark, not text: it keeps its size at 200 %.
            child: MediaQuery.withNoTextScaling(
              child: DpText(
                'D',
                role: DpTextRole.title,
                weight: 800,
                color: tokens.color.onAccent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of About's card: its name and a line under it, with a chevron when
/// it leads on.
class _Link extends StatelessWidget {
  const _Link({
    required this.title,
    required this.note,
    this.onTap,
    this.last = false,
  });

  final String title;
  final String note;
  final VoidCallback? onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      container: true,
      button: onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: last
                ? null
                : Border(bottom: BorderSide(color: tokens.surface.outline)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        DpText(title, role: DpTextRole.body, weight: 600),
                        if (note.isNotEmpty)
                          DpText(
                            note,
                            role: DpTextRole.caption,
                            color: tokens.color.textSecondary,
                          ),
                      ],
                    ),
                  ),
                  if (onTap != null)
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
