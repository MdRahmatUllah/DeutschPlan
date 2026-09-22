import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

/// S2's five pages, and the frame they share. `docs/04-screens/onboarding.md`.
///
/// > Coloured header block per page (Lagoon, Sun, Raspberry, Cobalt, Emerald)
/// > with the headline; "Step n of 5" dots; one control group; primary
/// > *Continue* pinned bottom; *Back* text button from page 2; *Skip*
/// > top-right from page 3.
enum OnboardingPage {
  welcome(1),
  meaningLanguage(2),
  startingPoint(3),
  dailyPace(4),
  reminderAndVoice(5);

  const OnboardingPage(this.step);

  /// 1…5, as the dots and "Step n of 5" count it.
  final int step;

  static const int count = 5;

  /// The route's `:page` parameter.
  String get slug => '$step';

  static OnboardingPage? parse(String slug) {
    final step = int.tryParse(slug);
    return step == null || step < 1 || step > count
        ? null
        : OnboardingPage.values[step - 1];
  }

  /// *Back* appears from page 2 — there is nowhere to go back to from page 1.
  bool get hasBack => step > 1;

  /// *Skip* appears from page 3. Pages 1 and 2 have nothing to default:
  /// page 1 writes no setting at all, and the meaning language is the one
  /// choice the learner should make deliberately rather than inherit.
  bool get hasSkip => step >= 3;

  OnboardingPage? get previous =>
      hasBack ? OnboardingPage.values[step - 2] : null;

  OnboardingPage? get next => step < count ? OnboardingPage.values[step] : null;
}

/// The header colour each page carries, from the spec's list.
///
/// Read off the palette rather than written as hex, so the block follows the
/// theme into dark and glass the way every other surface does.
extension OnboardingPageColour on OnboardingPage {
  Color headerColour(DpTokens tokens) => switch (this) {
    OnboardingPage.welcome => tokens.color.primary, // Lagoon
    OnboardingPage.meaningLanguage => tokens.color.accent, // Sun
    OnboardingPage.startingPoint => tokens.color.die, // Raspberry
    OnboardingPage.dailyPace => tokens.color.der, // Cobalt
    OnboardingPage.reminderAndVoice => tokens.color.das, // Emerald
  };
}

/// The frame: coloured header, dots, the page's controls, and the actions.
///
/// Every page of S2 is this widget with a different [child] — the shell is
/// where "Step n of 5", the header colour, *Back*, *Skip* and *Continue* live,
/// so five screens cannot drift into five slightly different frames.
class OnboardingShell extends StatelessWidget {
  const OnboardingShell({
    required this.page,
    required this.headline,
    required this.child,
    required this.primaryLabel,
    super.key,
    this.onPrimary,
    this.onBack,
    this.onSkip,
    this.headerArt,
  });

  final OnboardingPage page;
  final String headline;

  /// The page's one control group.
  final Widget child;

  /// *Continue* on most pages; page 1 says "Let's start" and page 5 "Start
  /// learning", which is why the label is the caller's.
  final String primaryLabel;
  final VoidCallback? onPrimary;

  final VoidCallback? onBack;
  final VoidCallback? onSkip;

  /// The decorative art inset into the bottom of the header block. Page 1's
  /// rising chart; the other pages have none.
  final Widget? headerArt;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Header(page: page, headline: headline, art: headerArt, onSkip: onSkip),
        _StepDots(page: page),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: child,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              DpButton(label: primaryLabel, onPressed: onPrimary),
              if (page.hasBack) ...<Widget>[
                const SizedBox(height: 8),
                // A link at the start edge, as the artboard draws it — not a
                // second full-width button competing with *Continue*.
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DpButton(
                    label: l10n.back,
                    onPressed: onBack,
                    kind: DpButtonKind.text,
                    expand: false,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );

    return AdaptiveScaffold(
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
      body: tokens.isGlass
          ? AuroraBackdrop(
              leading: page.headerColour(tokens),
              child: SafeArea(top: false, child: body),
            )
          : SafeArea(top: false, child: body),
    );
  }
}

/// The coloured block: step label, headline, and the page's art.
class _Header extends StatelessWidget {
  const _Header({
    required this.page,
    required this.headline,
    required this.art,
    required this.onSkip,
  });

  final OnboardingPage page;
  final String headline;
  final Widget? art;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final stepOf = l10n.onboardingStepOf(page.step, OnboardingPage.count);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          // The artboard's 54 above allows for the status bar. The shell
          // does not take the top inset — the header colour is meant to run
          // under the bar — so the block adds it to its own 20 here. The
          // bottom inset is omitted and carried by whichever of the two
          // branches below follows.
          padding: EdgeInsets.fromLTRB(
            24,
            20 + MediaQuery.paddingOf(context).top,
            24,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: DpText(
                      // Uppercase and tracked, as the artboard sets it; read
                      // aloud in sentence case, so TalkBack does not spell it.
                      // `toUpperCase` leaves Bangla alone, which has no case.
                      stepOf.toUpperCase(),
                      semanticsLabel: stepOf,
                      role: DpTextRole.caption,
                      weight: 700,
                      letterSpacing: 0.6,
                      // The header colours are all bright fills, so the ink
                      // on them is the same ink the artboard uses on each.
                      color: tokens.color.onPrimary,
                    ),
                  ),
                  // Only with somewhere to go: a Skip that cannot skip is worse
                  // than none, and finishing is #92's.
                  if (page.hasSkip && onSkip != null)
                    DpButton(
                      label: l10n.skip,
                      onPressed: onSkip,
                      kind: DpButtonKind.text,
                      expand: false,
                      // Ink, as the artboard draws it: the header is a bright
                      // fill, and link teal on Raspberry or Cobalt would all
                      // but vanish.
                      colour: tokens.color.onPrimary,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              DpText(
                headline,
                role: DpTextRole.headline,
                color: tokens.color.onPrimary,
              ),
            ],
          ),
        ),

        // Outside the padding on purpose. The artboard gives the art
        // `margin: 8px -24px -24px` — it bleeds past the block's side
        // padding and sits flush with its bottom edge, so the line runs the
        // full width of the screen rather than starting 24 dp in.
        if (art != null)
          Padding(padding: const EdgeInsets.only(top: 8), child: art),
        if (art == null) const SizedBox(height: 24),
      ],
    );

    // Under glass the block is a pane tinted with the page colour rather than
    // a solid fill — the glass artboards lay the colour at 22 % over frosted
    // white, so the aurora still shows through the top of the screen.
    return tokens.isGlass
        ? DpSurface(
            kind: DpSurfaceKind.tint(page.headerColour(tokens)),
            radius: 0,
            child: content,
          )
        : ColoredBox(color: page.headerColour(tokens), child: content);
  }
}

/// "Step n of 5", drawn: done pages filled ink, the current one a wide Sun
/// pill, the ones ahead outlined.
class _StepDots extends StatelessWidget {
  const _StepDots({required this.page});

  final OnboardingPage page;

  static const double size = 8;
  static const double currentWidth = 24;
  static const double border = 1.5;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Semantics(
        // One label for the row, because a screen reader announcing five
        // anonymous dots says nothing a learner can use. No
        // `excludeSemantics` — the pips are bare `Container`s and contribute
        // nothing of their own to exclude.
        label: l10n.onboardingStepOf(page.step, OnboardingPage.count),
        child: Row(
          children: <Widget>[
            for (final other in OnboardingPage.values)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Container(
                  width: other == page ? currentWidth : size,
                  height: size,
                  decoration: BoxDecoration(
                    // Done pages are filled ink, the current one is the Sun
                    // pill, and the ones ahead are outlines with no fill at
                    // all — not a transparent one, which would be a raw colour.
                    color: other.step < page.step
                        ? tokens.color.ink
                        : other == page
                        ? tokens.color.accent
                        : null,
                    borderRadius: BorderRadius.circular(size / 2),
                    border: Border.all(color: tokens.color.ink, width: border),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
