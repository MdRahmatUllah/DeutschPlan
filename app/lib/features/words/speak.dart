import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/components/dp_speaker_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/router/cross_tab.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:deutschplan/services/tts/tts_engine.dart';
import 'package:deutschplan/services/tts/tts_service.dart';
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
      DpToast.show(
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
      DpToast.show(context, l10n.speakerNoVoice, lift: lift);
      return false;
  }
}

/// The speaker's look for [text]: slashed once it is known there is no German
/// voice; playing while [text] sounds, and loading while it is synthesised
/// past `tts.md`'s 150 ms; idle otherwise.
DpSpeakerState speakerState(WidgetRef ref, String text) {
  if (ref.watch(ttsAvailableProvider).value == false) {
    return DpSpeakerState.unavailable;
  }
  final state = ref.watch(
    ttsPlaybackProvider.select((playback) {
      final now = playback.value;
      return now != null && now.text == text ? now.state : TtsState.idle;
    }),
  );
  return switch (state) {
    TtsState.idle => DpSpeakerState.idle,
    TtsState.loading => DpSpeakerState.loading,
    TtsState.playing => DpSpeakerState.playing,
  };
}
