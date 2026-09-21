import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:material_ui/material_ui.dart';

/// What the speaker is doing.
///
/// `docs/03-domain/tts.md`: "`TtsService`… exposes `state` (idle / loading /
/// playing) for the speaker button's three-bar animation. Loading indicator
/// only if synthesis > 150 ms."
enum DpSpeakerState { idle, loading, playing, unavailable }

/// The pronounce button.
///
/// From the Foundations artboard: 56 dp, circular, Lagoon, 2 px ink border and
/// the hard offset shadow. Playing swaps the horn for three bars; unavailable
/// shows a slashed icon, which `accessibility-performance.md` asks for when no
/// German system voice is installed.
class DpSpeakerButton extends StatelessWidget {
  const DpSpeakerButton({
    required this.onPressed,
    required this.semanticLabel,
    super.key,
    this.state = DpSpeakerState.idle,
    this.onLongPress,
    this.size = 56,
  });

  final VoidCallback? onPressed;

  /// Required: a bare icon button is invisible to a screen reader, and this one
  /// appears on every card, every example and every search row.
  final String semanticLabel;

  final DpSpeakerState state;

  /// Long-press plays at 0.75× — `tts.md`.
  final VoidCallback? onLongPress;

  final double size;

  bool get _enabled => onPressed != null && state != DpSpeakerState.unavailable;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Semantics(
      button: true,
      enabled: _enabled,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: _enabled ? onPressed : null,
          onLongPress: _enabled ? onLongPress : null,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: state == DpSpeakerState.unavailable
                  ? tokens.surface.muted
                  : tokens.color.primary,
              shape: BoxShape.circle,
              border: Border.all(color: tokens.color.ink, width: 2),
              boxShadow: tokens.isGlass
                  ? const <BoxShadow>[]
                  : <BoxShadow>[
                      BoxShadow(
                        color: tokens.surface.shadow,
                        offset: tokens.surface.shadowOffset,
                      ),
                    ],
            ),
            child: Center(child: _content(tokens)),
          ),
        ),
      ),
    );
  }

  Widget _content(DpTokens tokens) => switch (state) {
    DpSpeakerState.playing => _PlayingBars(
      colour: tokens.color.ink,
      size: size,
    ),
    // A spinner, not the bars: tts.md only shows this past 150 ms, so it means
    // "the model is thinking", which is a different thing from "sound is out".
    DpSpeakerState.loading => SizedBox(
      width: size * 0.35,
      height: size * 0.35,
      child: CircularProgressIndicator(strokeWidth: 2, color: tokens.color.ink),
    ),
    DpSpeakerState.unavailable => Icon(
      Icons.volume_off,
      size: size * 0.46,
      color: tokens.color.textSecondary,
    ),
    DpSpeakerState.idle => Icon(
      Icons.volume_up,
      size: size * 0.46,
      color: tokens.color.ink,
    ),
  };
}

/// The three bars the artboard draws while audio plays: 4 dp wide, heights
/// 10 / 22 / 14, radius 2.
class _PlayingBars extends StatelessWidget {
  const _PlayingBars({required this.colour, required this.size});

  final Color colour;
  final double size;

  @override
  Widget build(BuildContext context) {
    // The artboard heights are relative to a 56 dp button.
    final scale = size / 56;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        for (final (index, height) in <(int, double)>[
          (0, 10),
          (1, 22),
          (2, 14),
        ]) ...<Widget>[
          if (index > 0) SizedBox(width: 3 * scale),
          Container(
            width: 4 * scale,
            height: height * scale,
            decoration: BoxDecoration(
              color: colour,
              borderRadius: BorderRadius.circular(2 * scale),
            ),
          ),
        ],
      ],
    );
  }
}
