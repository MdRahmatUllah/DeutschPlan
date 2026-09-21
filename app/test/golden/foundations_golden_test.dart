import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/components/dp_progress_ring.dart';
import 'package:deutschplan/core/components/dp_rating_bar.dart';
import 'package:deutschplan/core/components/dp_speaker_button.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:material_ui/material_ui.dart';

import 'golden_harness.dart';

/// The component gallery, rendered in all six mode/device combinations.
///
/// This is the parity artefact #41 asks for: one page carrying every shared
/// component, to be diffed against `Foundations.html` in each design set. It is
/// also the harness's own proof — if the fonts, tokens or surfaces regress,
/// these six files change.
void main() {
  goldenTest('foundations', builder: (context) => const _FoundationsGallery());
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
                    const DpChip(label: 'A2.1'),
                    const DpChip(label: 'A2.1', selected: true),
                    DpChip(
                      label: 'To do',
                      kind: DpChipKind.status,
                      statusColour: tokens.surface.muted,
                    ),
                    DpChip(
                      label: 'Learning',
                      kind: DpChipKind.status,
                      statusColour: tokens.color.learning,
                    ),
                    DpChip(
                      label: 'Done',
                      kind: DpChipKind.status,
                      statusColour: tokens.color.easy,
                    ),
                    const DpChip(label: '12', kind: DpChipKind.streak),
                    const DpChip(
                      label: 'All',
                      kind: DpChipKind.filter,
                      selected: true,
                    ),
                    const DpChip(label: 'Learning', kind: DpChipKind.filter),
                    const DpChip(label: 'Duden', kind: DpChipKind.webLink),
                  ],
                ),
              ),
              _Section(
                label: 'Word card',
                child: DpSurface(
                  padding: EdgeInsets.all(tokens.spacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const DpHeadword('Rechnung', article: 'die'),
                      SizedBox(height: tokens.spacing.sm),
                      const DpText(
                        'Nomen · die Rechnung, -en · '
                        '/রেশনুং/',
                        role: DpTextRole.caption,
                      ),
                      SizedBox(height: tokens.spacing.md),
                      const DpText(
                        'bill, invoice / বিল, চালান',
                        role: DpTextRole.bodyLarge,
                      ),
                      SizedBox(height: tokens.spacing.md),
                      Row(
                        children: <Widget>[
                          DpSpeakerButton(
                            onPressed: () {},
                            semanticLabel: 'Pronounce die Rechnung',
                          ),
                          SizedBox(width: tokens.spacing.md),
                          // The artboard shows idle beside playing.
                          DpSpeakerButton(
                            onPressed: () {},
                            semanticLabel: 'Playing',
                            state: DpSpeakerState.playing,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              _Section(
                label: 'Rating bar',
                child: DpRatingBar(
                  onRated: (_) {},
                  intervals: const <DpRating, String>{
                    DpRating.again: '1 d',
                    DpRating.hard: '3 d',
                    DpRating.good: '8 d',
                    DpRating.easy: '21 d',
                  },
                ),
              ),
              _Section(
                label: 'Progress',
                child: Row(
                  children: <Widget>[
                    const DpProgressRing(
                      completed: 12,
                      total: 20,
                      caption: '6 min left',
                    ),
                    SizedBox(width: tokens.spacing.lg),
                    const Expanded(
                      child: DpSegmentedBar(done: 184, learning: 60, todo: 296),
                    ),
                  ],
                ),
              ),
              _Section(
                label: 'Buttons',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    DpButton(label: 'Start today · 20 cards', onPressed: () {}),
                    SizedBox(height: tokens.spacing.md),
                    DpButton(
                      label: 'Review backlog · 14',
                      kind: DpButtonKind.secondary,
                      onPressed: () {},
                    ),
                    SizedBox(height: tokens.spacing.xs),
                    DpButton(
                      label: 'Done for now',
                      kind: DpButtonKind.text,
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
                    DpVerdictRow(
                      verdict: DpVerdict.correct,
                      message: 'Correct',
                    ),
                    DpVerdictRow(
                      verdict: DpVerdict.almost,
                      message: 'Almost — watch the spelling',
                    ),
                    DpVerdictRow(
                      verdict: DpVerdict.wrongArticle,
                      message: 'die, not der',
                    ),
                  ],
                ),
              ),
              _Section(
                label: 'Callout',
                child: DpCallout.text('bekommen = to get, not "to become"'),
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
          DpText(
            label.toUpperCase(),
            role: DpTextRole.caption,
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
