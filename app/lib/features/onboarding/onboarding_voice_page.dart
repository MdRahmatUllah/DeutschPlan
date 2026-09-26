import 'dart:async';

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_speaker_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/model_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/features/onboarding/onboarding_notifier.dart';
import 'package:deutschplan/features/onboarding/onboarding_shell.dart';
import 'package:deutschplan/features/onboarding/setup_flow.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/services/model_downloads.dart';
import 'package:deutschplan/services/notification_permission.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'onboarding_voice_page.g.dart';

/// How big Supertonic is, from the model manifest — FR-M4-02's sizes are the
/// ones a download actually moves (about 400 MB since #245, not the ~100 MB
/// the first spec guessed).
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

/// Supertonic on this phone, for page 5's card (#428): its download's phase
/// (null while there is none), how far it has come, and how many bytes a new
/// download would lack.
typedef SupertonicOnPhone = ({
  DownloadPhase? phase,
  double progress,
  int shortfall,
});

/// The voice's real state, so *Restart setup* never offers what the phone
/// has: installed and checked is *Ready*; otherwise the download manager's
/// word, as it moves; with nothing in flight, the space check.
@riverpod
Stream<SupertonicOnPhone> supertonicOnPhone(Ref ref) async* {
  const id = OnboardingNotifier.supertonic;
  final models = ref.watch(modelRepositoryProvider);
  final downloads = ref.watch(modelDownloadsProvider);
  final model = (await models.manifest()).model(id);
  if (model == null || model.variants.isEmpty) return;
  // An update waiting is still a voice that works: page 5 leaves it to M4.
  final installed = await models.stateOf(model, model.variants.first);
  if (installed.status case ModelStatus.ready || ModelStatus.updateAvailable) {
    yield (phase: DownloadPhase.ready, progress: 1, shortfall: 0);
    return;
  }
  // Listening before asking the phone: an attempt in flight answers at once,
  // and a space check made against its own partial bytes must not flash
  // *Needs N MB more space* first.
  final heard = StreamController<SupertonicOnPhone>();
  ref.onDispose(heard.close);
  var answered = false;
  final updates = downloads.watch(id).listen((p) {
    answered = true;
    heard.add((phase: p.phase, progress: p.progress, shortfall: 0));
  });
  ref.onDispose(updates.cancel);
  final short = await downloads.shortfallFor(id);
  if (!answered) yield (phase: null, progress: 0, shortfall: short);
  yield* heard.stream;
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

  /// What the phone lacked when *Retry* last asked (#428); 0 once it didn't.
  int _retryShortfall = 0;

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
    if (!mounted) return;
    setState(() => _downloadFailed = !started);
    // The space may have gone since the page looked (NotEnoughSpace): look
    // again, so the card says how much.
    if (!started) ref.invalidate(supertonicOnPhoneProvider);
  }

  Future<void> _retry() async {
    var short = 0;
    await askToNotifyDownload(ref.read(notificationPermissionProvider));
    try {
      await ref
          .read(modelDownloadsProvider)
          .retry(OnboardingNotifier.supertonic);
    } on NotEnoughSpace catch (refused) {
      // The disk that failed a file is still full: say by how much.
      short = refused.bytes;
    } on Object {
      // Still failed, which the card already says; Retry stays.
    }
    if (mounted) setState(() => _retryShortfall = short);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final draft = ref.watch(onboardingProvider);
    final setup = ref.watch(setupFlowProvider);
    final megabytes = ref.watch(supertonicMegabytesProvider).value;
    final onPhone = ref.watch(supertonicOnPhoneProvider);

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

    final titled = _Titled(title: l10n.onboardingReminder, note: reminderNote);
    final timeButton = _TimeButton(
      time: time,
      on: draft.reminderOn,
      label: l10n.onboardingReminderTime(time),
      onTap: () => _pickTime(draft.reminderTime),
    );
    final reminderSwitch = AdaptiveSwitch(
      value: draft.reminderOn,
      onChanged: (on) => _notifier.setReminder(on: on),
      semanticLabel: l10n.onboardingReminder,
    );
    return OnboardingShell(
      page: OnboardingPage.reminderAndVoice,
      headline: l10n.onboardingVoiceHeadline,
      primaryLabel: l10n.onboardingStartLearning,
      onPrimary: widget.onFinish,
      onBack: widget.onBack,
      onSkip: widget.onSkip,
      busy: setup == SetupStatus.finishing,
      error: setup == SetupStatus.failed ? l10n.onboardingFinishFailed : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DpSurface(
            kind: DpSurfaceKind.bar,
            padding: const EdgeInsets.all(16),
            // Past 130 % text the time and the switch go under the title,
            // which they squeezed until "reminder" broke mid-word (#165).
            child: DpScript.large(context)
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      titled,
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          timeButton,
                          const Spacer(),
                          reminderSwitch,
                        ],
                      ),
                    ],
                  )
                : Row(
                    children: <Widget>[
                      Expanded(child: titled),
                      const SizedBox(width: 12),
                      timeButton,
                      const SizedBox(width: 12),
                      reminderSwitch,
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
            onPhone: onPhone.value,
            // A phone that couldn't be asked mustn't lock the offer: `start`
            // still checks the space.
            asked: onPhone.hasValue || onPhone.hasError,
            retryShortfall: _retryShortfall,
            offer: draft.voice,
            failed: _downloadFailed,
            onDownload: _download,
            onRetry: _retry,
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
    required this.onPhone,
    required this.asked,
    required this.retryShortfall,
    required this.offer,
    required this.failed,
    required this.onDownload,
    required this.onRetry,
    required this.onLater,
    required this.tokens,
  });

  final int? megabytes;

  final SupertonicOnPhone? onPhone;

  /// False until the phone has answered: *Download now* waits disabled, so
  /// an installed voice can't be fetched again in the moment before *Ready*.
  final bool asked;

  /// The bytes *Retry* found missing, and 0 when it didn't refuse.
  final int retryShortfall;
  final VoiceOffer offer;
  final bool failed;
  final VoidCallback onDownload;
  final VoidCallback onRetry;
  final VoidCallback onLater;
  final DpTokens tokens;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final glass = tokens.isGlass;
    // Dark ink on Sun in both solid modes; the page ink on a glass pane.
    final ink = glass ? tokens.color.ink : tokens.color.onAccent;

    final phase = onPhone?.phase;
    final percent = ((onPhone?.progress ?? 0) * 100).floor();
    final short = onPhone?.shortfall ?? 0;
    // Rounded up: "171 MB" freed must be enough.
    String needs(int bytes) =>
        l10n.onboardingSupertonicShortfall((bytes / 1e6).ceil());

    final status = switch (phase) {
      DownloadPhase.ready => l10n.onboardingSupertonicReady,
      // ponytail: checking the files takes seconds and reads as 100 %.
      DownloadPhase.running ||
      DownloadPhase.verifying => l10n.onboardingSupertonicDownloading(percent),
      DownloadPhase.waitingForWifi => l10n.onboardingSupertonicWaiting,
      DownloadPhase.paused => l10n.onboardingSupertonicPaused(percent),
      DownloadPhase.failed when retryShortfall > 0 => needs(retryShortfall),
      DownloadPhase.failed => l10n.onboardingSupertonicDownloadFailed,
      null => switch (offer) {
        VoiceOffer.offered when short > 0 => needs(short),
        VoiceOffer.offered => failed ? l10n.onboardingSupertonicFailed : null,
        VoiceOffer.started => l10n.onboardingSupertonicDownloading(0),
        VoiceOffer.deferred => l10n.onboardingSupertonicDeferred,
      },
    };

    // White on paper, as drawn; Lagoon under glass.
    final actionColour = glass ? tokens.color.primary : tokens.surface.card;
    final onActionColour = glass ? tokens.color.onPrimary : tokens.color.ink;
    // FR-M4 *Not enough space*: disabled, and the line below says by how
    // much. Disabled looks it: no colour of ours, so the button greys out.
    final canDownload = asked && short == 0;

    final download = DpButton(
      label: l10n.onboardingSupertonicDownload,
      onPressed: canDownload ? onDownload : null,
      kind: DpButtonKind.secondary,
      colour: canDownload ? actionColour : null,
      onColour: canDownload ? onActionColour : null,
    );
    final later = DpButton(
      label: l10n.onboardingSupertonicLater,
      onPressed: onLater,
      kind: DpButtonKind.secondary,
      colour: glass ? null : tokens.color.accent,
      onColour: glass ? null : tokens.color.onAccent,
    );
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
          if (phase == DownloadPhase.failed) ...<Widget>[
            const SizedBox(height: 10),
            DpButton(
              label: l10n.retry,
              onPressed: onRetry,
              kind: DpButtonKind.secondary,
              colour: actionColour,
              onColour: onActionColour,
            ),
          ],
          if (phase == null && offer == VoiceOffer.offered) ...<Widget>[
            const SizedBox(height: 10),
            // Past 130 % text they stack: side by side, "Download" broke
            // mid-word at 200 % (#165).
            if (DpScript.large(context)) ...<Widget>[
              download,
              const SizedBox(height: 8),
              later,
            ] else
              Row(
                children: <Widget>[
                  Expanded(child: download),
                  const SizedBox(width: 8),
                  Expanded(child: later),
                ],
              ),
            // #501: why Download now asks for notifications, while it can.
            if (canDownload) ...<Widget>[
              const SizedBox(height: 8),
              DpText(
                l10n.modelsNotifyWhy,
                role: DpTextRole.caption,
                color: ink,
              ),
            ],
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
