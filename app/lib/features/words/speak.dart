import 'package:sogda/core/components/sg_feedback.dart';
import 'package:sogda/core/components/sg_speaker_button.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/router/cross_tab.dart';
import 'package:sogda/router/routes.dart';
import 'package:sogda/services/tts/tts_engine.dart';
import 'package:sogda/services/tts/tts_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// A speaker's tap: says [text] through `ttsProvider` — the one player, which
/// stops whatever was sounding — at the learner's `tts_speed` times [pace]
/// (0.75 on the long-press, FR-T2-09).
///
/// The first time this session the phone's voice speaks for a missing or
/// failing Supertonic, a toast says so, with a link to Settings from a tab
/// (accessibility-performance.md). With no German voice at all it says how to
/// install one instead, and asks `ttsAvailableProvider` again so the speaker
/// turns slashed. Either toast is [lift]ed clear of a thumb zone. False when
/// nothing was said.
Future<bool> say(
  WidgetRef ref,
  BuildContext context,
  String text, {
  double pace = 1,
  double lift = 0,
}) async {
  final outcome = await ref.read(ttsProvider).speak(text, pace: pace);
  if (!context.mounted) return outcome != TtsOutcome.silent;
  final l10n = AppLocalizations.of(context);
  switch (outcome) {
    case TtsOutcome.spoke:
      return true;
    case TtsOutcome.fellBack:
      // The link only from a tab. `jumpToTab` replaces the stack, and from a
      // study session, an exam or placement the learner's work would go with
      // it; there the toast just says what happened.
      // The top of the stack: a pushed `/study` over Today counts as `/study`.
      final location = GoRouter.maybeOf(context)?.state.uri.path;
      final link = location != null && isTabDestination(location);
      SgToast.show(
        context,
        l10n.speakerFallback,
        lift: lift,
        actionLabel: link ? l10n.speakerFallbackSettings : null,
        // The root's context: the speaker may be gone before the tap.
        onAction: () =>
            rootNavigatorKey.currentContext?.jumpToTab(const SettingsRoute()),
      );
      ref.read(ttsProvider).toldFallback();
      return true;
    case TtsOutcome.silent:
      ref.invalidate(ttsAvailableProvider);
      SgToast.show(context, l10n.speakerNoVoice, lift: lift);
      return false;
  }
}

/// Whether it is known that the phone has no German voice (V01): every
/// speaker is slashed then, the small play buttons too (#452), and a tap says
/// how to install one.
bool noVoice(WidgetRef ref) => ref.watch(ttsAvailableProvider).value == false;

/// Whether a play nobody asked for may start: a card's autoplay, a word read
/// out as it opens. Not once the phone is known to have no German voice: the
/// "no voice" toast would then come with every card, and each time replace
/// the rating's 4 s Undo (FR-T2-02, #646). A tap still explains, every time.
///
/// Read, not watched, as it is asked from callbacks: the screen keeps
/// [ttsAvailableProvider] alive, its speakers watching it through [noVoice].
bool mayAutoplay(WidgetRef ref) =>
    ref.read(ttsAvailableProvider).value != false;

/// The speaker's look for [text]: slashed once it is known there is no German
/// voice; playing while [text] sounds, and loading while it is synthesised
/// past `tts.md`'s 150 ms; idle otherwise.
SgSpeakerState speakerState(WidgetRef ref, String text) {
  if (noVoice(ref)) return SgSpeakerState.unavailable;
  final state = ref.watch(
    ttsPlaybackProvider.select((playback) {
      final now = playback.value;
      return now != null && now.text == text ? now.state : TtsState.idle;
    }),
  );
  return switch (state) {
    TtsState.idle => SgSpeakerState.idle,
    TtsState.loading => SgSpeakerState.loading,
    TtsState.playing => SgSpeakerState.playing,
  };
}
