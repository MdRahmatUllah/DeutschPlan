import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/components/sg_button.dart';
import 'package:sogda/core/components/sg_chip.dart';
import 'package:sogda/core/components/sg_feedback.dart';
import 'package:sogda/core/components/sg_progress_ring.dart';
import 'package:sogda/core/components/sg_rating_bar.dart';
import 'package:sogda/core/components/sg_speaker_button.dart';
import 'package:sogda/core/theme/sg_surface.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/features/me/me_screen.dart' show MeHeader;

import 'golden_harness.dart';

/// The component gallery, rendered in all six mode/device combinations.
///
/// This is the parity artefact #41 asks for: one page carrying every shared
/// component, to be diffed against `Foundations.html` in each design set. It is
/// also the harness's own proof — if the fonts, tokens or surfaces regress,
/// these six files change.
void main() {
  goldenTest('foundations', builder: (context) => const _FoundationsGallery());

  // #745: the focus ring a keyboard or a D-pad shows, on the first control
  // Tab reaches, in each mode. The gallery above is its text audit.
  goldenTest(
    'foundations_focus',
    devices: const <GoldenDevice>[GoldenDevice.phone],
    textAudit: false,
    act: (tester) => tester.sendKeyEvent(LogicalKeyboardKey.tab),
    builder: (context) => Scaffold(
      backgroundColor: context.tokens.surface.paper,
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(context.tokens.spacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SgButton(label: 'Start today · 20 cards', onPressed: () {}),
              SizedBox(height: context.tokens.spacing.md),
              SgChip(label: 'A2.1', onTap: () {}),
            ],
          ),
        ),
      ),
    ),
  );

  // #1049: a switch takes the focus itself; the ring hugs its track, and
  // neither Material's halo nor iOS's own border is drawn beside it.
  for (final chrome in AdaptiveChrome.values) {
    goldenTest(
      chrome == AdaptiveChrome.material
          ? 'foundations_focus_switch'
          : 'foundations_focus_switch_ios',
      devices: const <GoldenDevice>[GoldenDevice.phone],
      chrome: chrome,
      textAudit: false,
      act: (tester) => tester.sendKeyEvent(LogicalKeyboardKey.tab),
      builder: (context) => Scaffold(
        backgroundColor: context.tokens.surface.paper,
        // As a screen has it: in a row the screen reader hears as the switch.
        body: Center(
          child: Semantics(
            container: true,
            child: Padding(
              padding: EdgeInsets.all(context.tokens.spacing.lg),
              child: SizedBox(
                height: 56,
                child: Row(
                  children: <Widget>[
                    const Expanded(
                      child: SgText(
                        'Continue into the next step',
                        role: SgTextRole.body,
                      ),
                    ),
                    AdaptiveSwitch(
                      value: true,
                      onChanged: (_) {},
                      semanticLabel: 'Continue into the next step',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // #1064: the ring on a coloured header, in the header's ink: Me's first
  // Tab stop, *Add your name*, on the blue.
  goldenTest(
    'foundations_focus_header',
    devices: const <GoldenDevice>[GoldenDevice.phone],
    textAudit: false,
    act: (tester) => tester.sendKeyEvent(LogicalKeyboardKey.tab),
    builder: (context) => Scaffold(
      backgroundColor: context.tokens.surface.paper,
      body: Align(
        alignment: Alignment.topCenter,
        child: MeHeader(
          name: null,
          streak: 3,
          since: null,
          daysStudied: 0,
          onEditName: () {},
        ),
      ),
    ),
  );
}

class _FoundationsGallery extends StatelessWidget {
  const _FoundationsGallery();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Scaffold(
      backgroundColor: tokens.surface.paper,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(tokens.spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Section(
                label: 'Chips',
                child: Wrap(
                  spacing: tokens.spacing.sm,
                  runSpacing: tokens.spacing.sm,
                  children: <Widget>[
                    const SgChip(label: 'A2.1'),
                    const SgChip(label: 'A2.1', selected: true),
                    SgChip(
                      label: 'To do',
                      kind: SgChipKind.status,
                      statusColour: tokens.surface.muted,
                    ),
                    SgChip(
                      label: 'Learning',
                      kind: SgChipKind.status,
                      statusColour: tokens.color.learning,
                    ),
                    SgChip(
                      label: 'Done',
                      kind: SgChipKind.status,
                      statusColour: tokens.color.easy,
                    ),
                    const SgChip(label: '12', kind: SgChipKind.streak),
                    const SgChip(
                      label: 'All',
                      kind: SgChipKind.filter,
                      selected: true,
                    ),
                    const SgChip(label: 'Learning', kind: SgChipKind.filter),
                    const SgChip(label: 'Duden', kind: SgChipKind.webLink),
                  ],
                ),
              ),
              _Section(
                label: 'Word card',
                child: SgSurface(
                  padding: EdgeInsets.all(tokens.spacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const SgHeadword('Rechnung', article: 'die'),
                      SizedBox(height: tokens.spacing.sm),
                      const SgText(
                        'Nomen · die Rechnung, -en · '
                        '/রেশনুং/',
                        role: SgTextRole.caption,
                      ),
                      SizedBox(height: tokens.spacing.md),
                      const SgText(
                        'bill, invoice / বিল, চালান',
                        role: SgTextRole.bodyLarge,
                      ),
                      SizedBox(height: tokens.spacing.md),
                      Row(
                        children: <Widget>[
                          SgSpeakerButton(
                            onPressed: () {},
                            semanticLabel: 'Pronounce die Rechnung',
                          ),
                          SizedBox(width: tokens.spacing.md),
                          // The artboard shows idle beside playing.
                          SgSpeakerButton(
                            onPressed: () {},
                            semanticLabel: 'Playing',
                            state: SgSpeakerState.playing,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              _Section(
                label: 'Rating bar',
                child: SgRatingBar(
                  onRated: (_) {},
                  intervals: const <SgRating, String>{
                    SgRating.again: '1 d',
                    SgRating.hard: '3 d',
                    SgRating.good: '8 d',
                    SgRating.easy: '21 d',
                  },
                ),
              ),
              _Section(
                label: 'Progress',
                child: Row(
                  children: <Widget>[
                    const SgProgressRing(
                      completed: 12,
                      total: 20,
                      caption: '6 min left',
                    ),
                    SizedBox(width: tokens.spacing.lg),
                    const Expanded(
                      child: SgSegmentedBar(done: 184, learning: 60, todo: 296),
                    ),
                  ],
                ),
              ),
              _Section(
                label: 'Buttons',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SgButton(label: 'Start today · 20 cards', onPressed: () {}),
                    SizedBox(height: tokens.spacing.md),
                    SgButton(
                      label: 'Review backlog · 14',
                      kind: SgButtonKind.secondary,
                      onPressed: () {},
                    ),
                    SizedBox(height: tokens.spacing.xs),
                    SgButton(
                      label: 'Done for now',
                      kind: SgButtonKind.text,
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
              _Section(
                label: 'Verdicts',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const <Widget>[
                    SgVerdictRow(
                      verdict: SgVerdict.correct,
                      message: 'Correct',
                    ),
                    SgVerdictRow(
                      verdict: SgVerdict.almost,
                      message: 'Almost — watch the spelling',
                    ),
                    SgVerdictRow(
                      verdict: SgVerdict.wrongArticle,
                      message: 'die, not der',
                    ),
                  ],
                ),
              ),
              _Section(
                label: 'Callout',
                child: SgCallout.text('bekommen = to get, not "to become"'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SgText(
            label.toUpperCase(),
            role: SgTextRole.caption,
            weight: 700,
            color: tokens.color.textSecondary,
          ),
          SizedBox(height: tokens.spacing.sm),
          child,
        ],
      ),
    );
  }
}
