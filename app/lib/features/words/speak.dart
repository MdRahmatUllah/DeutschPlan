import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/components/dp_speaker_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// A speaker's tap: says [text] through `ttsProvider` at the learner's
/// `tts_speed` times [pace] (0.75 on the long-press, FR-T2-09).
///
/// With no German voice it says how to install one instead, [lift]ed clear of
/// a thumb zone, and asks `ttsAvailableProvider` again so the speaker turns
/// slashed (accessibility-performance.md). False when nothing was said.
Future<bool> say(
  WidgetRef ref,
  BuildContext context,
  String text, {
  double pace = 1,
  double lift = 0,
}) async {
  final speed = ref.read(settingsProvider).read(SettingKeys.ttsSpeed);
  final spoke = await ref.read(ttsProvider).speak(text, speed: speed * pace);
  if (spoke || !context.mounted) return spoke;
  ref.invalidate(ttsAvailableProvider);
  DpToast.show(
    context,
    AppLocalizations.of(context).speakerNoVoice,
    lift: lift,
  );
  return false;
}

/// The speaker's look for what the phone can say: slashed once it is known
/// there is no German voice, idle until then.
DpSpeakerState speakerState(WidgetRef ref) =>
    ref.watch(ttsAvailableProvider).value == false
    ? DpSpeakerState.unavailable
    : DpSpeakerState.idle;
