import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_speaker_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/features/onboarding/onboarding_notifier.dart';
import 'package:deutschplan/features/onboarding/onboarding_shell.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'onboarding_voice_page.g.dart';

/// How big Supertonic is, from the model manifest rather than the card's own
/// "~100 MB" — FR-M4-02's sizes are the ones a download actually moves.
///
/// Rounded to ten: "about 103 MB" is a precision the learner cannot use.
@riverpod
Future<int?> supertonicMegabytes(Ref ref) async {
  final manifest = await ref.watch(modelRepositoryProvider).manifest();
  final variant = manifest.model(OnboardingNotifier.supertonic)?.variants;
  if (variant == null || variant.isEmpty) return null;
  final bytes = variant.first.files.fold<int>(0, (sum, f) => sum + f.bytes);
  return (bytes / 1e7).round() * 10;
}

/// S2 page 5 · Reminder and voice. `OnboardingVoice-android.html`.
///
/// The reminder (off, 19:30), a preview of the German the phone can already
/// speak, and the offer of a better voice. *Start learning* finishes setup.
class OnboardingVoicePage extends ConsumerStatefulWidget {
  const OnboardingVoicePage({
    super.key,
    this.onFinish,
    this.onBack,
    this.onSkip,
  });

  /// *Start learning* — FR-S2-03's commit, which is #92's.
  final VoidCallback? onFinish;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;

  @override
  ConsumerState<OnboardingVoicePage> createState() =>
      _OnboardingVoicePageState();
}

class _OnboardingVoicePageState extends ConsumerState<OnboardingVoicePage> {
  /// What the last tap on the speaker found. Screen state, not a value: it is
  /// about this phone, and asking again is one tap.
  bool _voiceMissing = false;
  bool _downloadFailed = false;

  OnboardingNotifier get _notifier => ref.read(onboardingProvider.notifier);

  Future<void> _preview(String phrase) async {
    final spoke = await ref.read(systemTtsProvider).speak(phrase);
    if (mounted) setState(() => _voiceMissing = !spoke);
  }

  Future<void> _pickTime(Clock current) async {
    final picked = await Adaptive.showTimePickerFor(
      context: context,
      initial: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked != null) {
      _notifier.setReminderTime((hour: picked.hour, minute: picked.minute));
    }
  }

  Future<void> _download() async {
    final started = await _notifier.downloadVoice();
    if (mounted) setState(() => _downloadFailed = !started);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final draft = ref.watch(onboardingProvider);
    final megabytes = ref.watch(supertonicMegabytesProvider).value;

    // The platform's own format — "19:30" or "7:30 PM" — because the picker
    // this opens uses it too, and the two disagreeing would look like a bug.
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(
        hour: draft.reminderTime.hour,
        minute: draft.reminderTime.minute,
      ),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

    final reminderNote = draft.reminderBlocked
        ? l10n.onboardingReminderBlocked
        : draft.reminderOn
        ? l10n.onboardingReminderOn(time)
        : l10n.onboardingReminderOff;

    final sample = l10n.onboardingVoiceSample;

    return OnboardingShell(
      page: OnboardingPage.reminderAndVoice,
      headline: l10n.onboardingVoiceHeadline,
      primaryLabel: l10n.onboardingStartLearning,
      onPrimary: widget.onFinish,
      onBack: widget.onBack,
      onSkip: widget.onSkip,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DpSurface(
            kind: DpSurfaceKind.bar,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _Titled(
                    title: l10n.onboardingReminder,
                    note: reminderNote,
                  ),
                ),
                const SizedBox(width: 12),
                _TimeButton(
                  time: time,
                  on: draft.reminderOn,
                  label: l10n.onboardingReminderTime(time),
                  onTap: () => _pickTime(draft.reminderTime),
                ),
                const SizedBox(width: 12),
                AdaptiveSwitch(
                  value: draft.reminderOn,
                  onChanged: (on) => _notifier.setReminder(on: on),
                  semanticLabel: l10n.onboardingReminder,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          DpSurface(
            kind: DpSurfaceKind.bar,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                DpSpeakerButton(
                  size: 48,
                  state: _voiceMissing
                      ? DpSpeakerState.unavailable
                      : DpSpeakerState.idle,
                  semanticLabel: l10n.onboardingVoicePlay,
                  // The system voice, so it works before any model exists.
                  onPressed: () => _preview(sample),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Titled(
                    title: l10n.onboardingVoiceHear(sample),
                    note: _voiceMissing
                        ? l10n.onboardingVoiceMissing
                        : l10n.onboardingVoiceSystem,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SupertonicCard(
            megabytes: megabytes,
            offer: draft.voice,
            failed: _downloadFailed,
            onDownload: _download,
            onLater: () => _notifier.deferVoice(),
            tokens: tokens,
          ),
        ],
      ),
    );
  }
}

/// A label and the grey line under it, as every row on this page has.
class _Titled extends StatelessWidget {
  const _Titled({required this.title, required this.note});

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      DpText(title, role: DpTextRole.body, weight: 600),
      const SizedBox(height: 1),
      DpText(
        note,
        role: DpTextRole.caption,
        color: context.tokens.color.textSecondary,
      ),
    ],
  );
}

/// "19:30", which opens the time picker — Material's dialog on Android, the
/// Cupertino wheel on iOS, through `Adaptive.showTimePickerFor`.
class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.time,
    required this.on,
    required this.label,
    required this.onTap,
  });

  final String time;
  final bool on;
  final String label;
  final VoidCallback onTap;

  static const double minTapTarget = 48;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minTapTarget),
          child: Center(
            widthFactor: 1,
            child: DpText(
              time,
              role: DpTextRole.bodyLarge,
              weight: 600,
              // Grey while the reminder is off, as drawn: a time that will not
              // fire should not look set.
              color: on ? tokens.color.ink : tokens.color.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// The Supertonic offer: a Sun card on paper, a Sun-tinted pane under glass.
class _SupertonicCard extends StatelessWidget {
  const _SupertonicCard({
    required this.megabytes,
    required this.offer,
    required this.failed,
    required this.onDownload,
    required this.onLater,
    required this.tokens,
  });

  final int? megabytes;
  final VoiceOffer offer;
  final bool failed;
  final VoidCallback onDownload;
  final VoidCallback onLater;
  final DpTokens tokens;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final glass = tokens.isGlass;
    // Dark ink on Sun in both solid modes; the page ink on a glass pane.
    final ink = glass ? tokens.color.ink : tokens.color.onAccent;

    final status = switch (offer) {
      VoiceOffer.offered => failed ? l10n.onboardingSupertonicFailed : null,
      VoiceOffer.started => l10n.onboardingSupertonicStarted,
      VoiceOffer.deferred => l10n.onboardingSupertonicDeferred,
    };

    return DpSurface(
      // Solid Sun with the chosen edge — 2 px ink and the hard shadow — on
      // paper; the glass artboards tint a pane instead, with no edge.
      kind: DpSurfaceKind.tint(tokens.color.accent, opacity: glass ? 0.22 : 1),
      selected: !glass,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DpText(
            l10n.onboardingSupertonicTitle,
            role: DpTextRole.body,
            weight: 600,
            color: ink,
          ),
          if (megabytes != null) ...<Widget>[
            const SizedBox(height: 10),
            DpText(
              l10n.onboardingSupertonicBody(megabytes!),
              role: DpTextRole.label,
              weight: 400,
              color: ink,
            ),
          ],
          if (offer == VoiceOffer.offered) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: DpButton(
                    label: l10n.onboardingSupertonicDownload,
                    onPressed: onDownload,
                    kind: DpButtonKind.secondary,
                    // White on paper, as drawn; Lagoon under glass.
                    colour: glass ? tokens.color.primary : tokens.surface.card,
                    onColour: glass ? tokens.color.onPrimary : tokens.color.ink,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DpButton(
                    label: l10n.onboardingSupertonicLater,
                    onPressed: onLater,
                    kind: DpButtonKind.secondary,
                    colour: glass ? null : tokens.color.accent,
                    onColour: glass ? null : tokens.color.onAccent,
                  ),
                ),
              ],
            ),
          ],
          if (status != null) ...<Widget>[
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: DpText(
                status,
                role: DpTextRole.caption,
                weight: 600,
                color: ink,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
