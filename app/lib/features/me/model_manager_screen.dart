import 'dart:async';

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/components/dp_pill.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/model_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/features/me/licences_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/l10n/ui_digits.dart';
import 'package:deutschplan/services/device_storage.dart';
import 'package:deutschplan/services/model_downloads.dart';
import 'package:deutschplan/services/tts/supertonic_tts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'model_manager_screen.g.dart';

/// FR-M4-04: Hy-MT's download is offered only in a build made with
/// `--dart-define=ENABLE_HYMT_DOWNLOAD=true`. Off by default: the Tencent HY
/// licence excludes the EU, the UK and South Korea, and a store build for
/// them keeps it off until the legal check is done (`translation.md`).
const bool enableHymtDownload = bool.fromEnvironment('ENABLE_HYMT_DOWNLOAD');

/// What a model's card says (`model-manager.md`, "States per model").
enum ModelCardStatus {
  notDownloaded,
  notEnoughSpace,
  downloading,
  verifying,
  ready,
  updateAvailable,
  failed,
}

/// One model's card: its manifest entry and build, what is on the phone, the
/// download as it moves (null while there is none), and the bytes a new
/// download would lack.
typedef ModelCard = ({
  ModelEntry entry,
  ModelVariant variant,
  ModelState installed,
  DownloadProgress? live,
  int shortfall,
});

/// The card's state: the download's while one is running, and otherwise
/// what is on the phone.
ModelCardStatus cardStatusOf(ModelCard card) {
  switch (card.live?.phase) {
    case DownloadPhase.running ||
        DownloadPhase.paused ||
        DownloadPhase.waitingForWifi:
      return ModelCardStatus.downloading;
    case DownloadPhase.verifying:
      return ModelCardStatus.verifying;
    case DownloadPhase.failed:
      return ModelCardStatus.failed;
    case DownloadPhase.ready || null:
      break;
  }
  return switch (card.installed.status) {
    ModelStatus.ready => ModelCardStatus.ready,
    ModelStatus.updateAvailable => ModelCardStatus.updateAvailable,
    ModelStatus.failed => ModelCardStatus.failed,
    ModelStatus.verifying => ModelCardStatus.verifying,
    ModelStatus.downloading => ModelCardStatus.downloading,
    // FR-M4-04 before space: a download that isn't offered has no space to
    // lack.
    ModelStatus.notDownloaded =>
      card.shortfall > 0 && offered(card.entry.id)
          ? ModelCardStatus.notEnoughSpace
          : ModelCardStatus.notDownloaded,
  };
}

/// Whether this build offers [modelId]'s download (FR-M4-04).
bool offered(String modelId) =>
    modelId != ModelRepository.translationModel || enableHymtDownload;

/// [id]'s card, as its download moves: the files on the phone read again
/// whenever the download manager says something.
@riverpod
Stream<ModelCard> modelCard(Ref ref, String id) async* {
  final models = ref.watch(modelRepositoryProvider);
  final downloads = ref.watch(modelDownloadsProvider);
  final entry = (await models.manifest()).model(id);
  if (entry == null || entry.variants.isEmpty) return;
  // One build a model, as the manifest has it (#409).
  final variant = entry.variants.first;

  Future<ModelCard> card(DownloadProgress? live) async {
    final installed = await models.stateOf(entry, variant);
    // Only a download to come asks the phone for its space.
    final asks = live == null || live.phase == DownloadPhase.ready;
    final needsSpace =
        asks &&
        (installed.status == ModelStatus.notDownloaded ||
            installed.status == ModelStatus.updateAvailable);
    return (
      entry: entry,
      variant: variant,
      installed: installed,
      live: live?.phase == DownloadPhase.ready ? null : live,
      // The manager's own check (#428), margin and all, so the card and
      // `start` never disagree.
      shortfall: needsSpace && offered(id)
          ? await downloads.shortfallFor(id)
          : 0,
    );
  }

  yield await card(null);
  await for (final live in downloads.watch(id)) {
    // Bytes landed or went: the storage card reads the phone again.
    if (live.phase == DownloadPhase.ready ||
        live.phase == DownloadPhase.failed) {
      ref.invalidate(phoneSpaceProvider);
    }
    yield await card(live);
  }
}

/// The phone's free and total space, for the storage card. Null when the
/// phone won't say.
@riverpod
Future<StorageSpace?> phoneSpace(Ref ref) =>
    ref.watch(deviceStorageProvider).space();

/// A size as M4 writes it: whole megabytes below a gigabyte ("399 MB"), and
/// gigabytes to one decimal above, a whole one without it ("1.1 GB",
/// "64 GB"), in the UI language's digits.
String modelSize(AppLocalizations l10n, int bytes) {
  if (bytes < 1000000000) {
    return l10n.modelsSizeMb(l10n.digits((bytes / 1e6).round()));
  }
  final gigabytes = (bytes / 1e9).toStringAsFixed(1);
  return l10n.modelsSizeGb(
    l10n.digits(
      gigabytes.endsWith('.0')
          ? gigabytes.substring(0, gigabytes.length - 2)
          : gigabytes,
    ),
  );
}

/// The licence M8 bundles for [modelId] (FR-M4-04's link opens its text),
/// found by the model's name in M8's list.
Licence? licenceFor(String modelId) {
  final name = switch (modelId) {
    ModelRepository.voiceModel => 'Supertonic 3',
    ModelRepository.translationModel => 'Hy-MT',
    _ => null,
  };
  if (name == null) return null;
  for (final licence in modelLicences) {
    if (licence.name.startsWith(name)) return licence;
  }
  return null;
}

/// M4 · Model manager, *Voice & translation* (`model-manager.md`, the
/// ModelManager artboards): the phone's storage, then a card per model with
/// its state, its download, and what can be done with it.
class ModelManagerScreen extends ConsumerWidget {
  const ModelManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final voice = ref
        .watch(modelCardProvider(ModelRepository.voiceModel))
        .value;
    final translation = ref
        .watch(modelCardProvider(ModelRepository.translationModel))
        .value;
    final space = ref.watch(phoneSpaceProvider).value;
    final onPhone = <ModelCard?>[
      voice,
      translation,
    ].fold<int>(0, (sum, card) => sum + (card?.installed.bytesOnDisk ?? 0));

    final scaffold = AdaptiveScaffold(
      title: l10n.modelsTitle,
      leading: AdaptiveBackButton(
        label: l10n.settingsTitle,
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          _Storage(space: space, models: onPhone),
          const SizedBox(height: 14),
          if (voice != null) ...<Widget>[
            _ModelCardView(voice),
            const SizedBox(height: 10),
          ],
          if (translation != null) ...<Widget>[
            _ModelCardView(translation),
            const SizedBox(height: 10),
          ],
          DpText(
            l10n.modelsFooter,
            role: DpTextRole.caption,
            color: tokens.color.textSecondary,
          ),
        ],
      ),
    );
    return tokens.isGlass
        ? AuroraBackdrop(leading: tokens.color.primary, child: scaffold)
        : scaffold;
  }
}

/// The storage card: the phone's free space, a bar of what is used with the
/// models' share in Lagoon, and the models' size.
class _Storage extends StatelessWidget {
  const _Storage({required this.space, required this.models});

  final StorageSpace? space;
  final int models;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final space = this.space;
    final total = space?.total ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: DpText(
                l10n.modelsStorage,
                role: DpTextRole.label,
                weight: 600,
              ),
            ),
            if (space != null)
              DpText(
                l10n.modelsStorageFree(
                  modelSize(l10n, space.free),
                  modelSize(l10n, total),
                ),
                role: DpTextRole.label,
                weight: 400,
                color: tokens.color.textSecondary,
              ),
          ],
        ),
        if (space != null && total > 0) ...<Widget>[
          const SizedBox(height: 6),
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _Share(
                      flex: total - space.free - models,
                      colour: tokens.color.textSecondary,
                    ),
                    _Share(flex: models, colour: tokens.color.primary),
                    _Share(flex: space.free, colour: tokens.surface.track),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 6),
        DpText(
          space == null || total == 0
              ? l10n.modelsStorageModelsOnly(modelSize(l10n, models))
              : l10n.modelsStorageModels(
                  modelSize(l10n, models),
                  modelSize(l10n, total),
                ),
          role: DpTextRole.caption,
          color: tokens.color.textSecondary,
        ),
      ],
    );
  }
}

/// A part of the storage bar, in proportion to its bytes.
class _Share extends StatelessWidget {
  const _Share({required this.flex, required this.colour});

  final int flex;
  final Color colour;

  @override
  Widget build(BuildContext context) => flex <= 0
      ? const SizedBox.shrink()
      // Kilobytes: a flex is an int, and a phone's bytes overflow nothing
      // but read better as proportions this way.
      : Expanded(
          flex: (flex / 1000).ceil(),
          child: ColoredBox(color: colour),
        );
}

/// One model's card: its name, size and licence, its state, and what can be
/// done with it now.
class _ModelCardView extends ConsumerWidget {
  const _ModelCardView(this.card);

  final ModelCard card;

  bool get _isVoice => card.entry.id == ModelRepository.voiceModel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final status = cardStatusOf(card);
    final size = modelSize(l10n, card.variant.bytes);
    final title = _isVoice
        ? l10n.modelsVoiceTitle
        : l10n.modelsTranslationTitle;
    final licence = licenceFor(card.entry.id);

    final subtitle = DpText(
      _isVoice
          ? l10n.modelsVoiceSubtitle(size, card.entry.licence)
          : l10n.modelsTranslationSubtitle(size),
      role: DpTextRole.caption,
      color: tokens.color.textSecondary,
    );

    return DpSurface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    DpText(title, role: DpTextRole.bodyLarge, weight: 600),
                    const SizedBox(height: 2),
                    if (_isVoice || licence == null)
                      subtitle
                    else
                      // FR-M4-04: the licence link opens the full text.
                      Semantics(
                        button: true,
                        label: l10n.modelsLicenceRead(licence.kind),
                        excludeSemantics: true,
                        onTap: () => unawaited(showLicence(context, licence)),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => unawaited(showLicence(context, licence)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Flexible(child: subtitle),
                              Icon(
                                Icons.arrow_forward,
                                size: 14,
                                color: tokens.color.textSecondary,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(status: status, live: card.live),
            ],
          ),
          ..._body(context, ref, status),
        ],
      ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    WidgetRef ref,
    ModelCardStatus status,
  ) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final id = card.entry.id;
    final downloads = ref.read(modelDownloadsProvider);
    final size = modelSize(l10n, card.variant.bytes);
    final freed = modelSize(l10n, card.installed.bytesOnDisk);

    Widget note(String text) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: DpText(
        text,
        role: DpTextRole.caption,
        color: tokens.color.textSecondary,
      ),
    );

    Future<void> act(Future<void> Function() action) async {
      try {
        await action();
      } on NotEnoughSpace catch (short) {
        // The manager refused (#428): the phone filled up since the card
        // looked. Say by how much.
        if (context.mounted) {
          DpToast.show(
            context,
            l10n.modelsNoSpaceNote(modelSize(l10n, short.bytes)),
          );
        }
      } on Object {
        if (context.mounted) DpToast.show(context, l10n.modelsStartFailed);
      }
      ref
        ..invalidate(modelCardProvider(id))
        ..invalidate(phoneSpaceProvider);
    }

    final deleteButton = _Action(
      label: l10n.modelsDelete(freed),
      onPressed: () => unawaited(_delete(context, ref)),
    );

    switch (status) {
      case ModelCardStatus.ready:
        return <Widget>[
          if (_isVoice) _Voices(card: card),
          _Actions(
            children: <Widget>[
              deleteButton,
              _Action(
                label: l10n.modelsCheckUpdate,
                white: true,
                onPressed: () => unawaited(_check(context, ref)),
              ),
            ],
          ),
        ];
      case ModelCardStatus.updateAvailable:
        final short = card.shortfall > 0;
        return <Widget>[
          if (_isVoice) _Voices(card: card),
          if (short)
            note(l10n.modelsNoSpaceNote(modelSize(l10n, card.shortfall))),
          _Actions(
            children: <Widget>[
              deleteButton,
              _Action(
                label: l10n.modelsUpdate(size),
                white: true,
                // FR-M4 *Not enough space*: an update is a download too.
                onPressed: short
                    ? null
                    : () => unawaited(act(() => downloads.start(id))),
              ),
            ],
          ),
        ];
      case ModelCardStatus.downloading:
        final live = card.live;
        return <Widget>[
          _Progress(card: card),
          _WifiOnly(
            onChanged: (on) async {
              await downloads.setWifiOnly(on: on);
              // The line above says "· Wi-Fi" or not.
              ref.invalidate(modelCardProvider(id));
            },
          ),
          _Actions(
            children: <Widget>[
              _Action(
                label: live?.phase == DownloadPhase.paused
                    ? l10n.modelsResume
                    : l10n.modelsPause,
                onPressed: () => unawaited(
                  act(
                    () => live?.phase == DownloadPhase.paused
                        ? downloads.resume(id)
                        : downloads.pause(id),
                  ),
                ),
              ),
            ],
          ),
        ];
      case ModelCardStatus.verifying:
        return <Widget>[note(l10n.modelsVerifyingNote)];
      case ModelCardStatus.failed:
        return <Widget>[
          note(l10n.modelsFailedNote),
          _Actions(
            children: <Widget>[
              _Action(
                label: l10n.retry,
                // A download that failed is retried; files on the phone that
                // broke are fetched again from the start, space checked.
                onPressed: () => unawaited(
                  act(
                    () => card.live == null
                        ? downloads.start(id)
                        : downloads.retry(id),
                  ),
                ),
              ),
              if (card.installed.bytesOnDisk > 0) deleteButton,
            ],
          ),
        ];
      case ModelCardStatus.notEnoughSpace:
        return <Widget>[
          note(l10n.modelsNoSpaceNote(modelSize(l10n, card.shortfall))),
          _Actions(
            children: <Widget>[
              // FR-M4 *Not enough space*: disabled, and the note says by how
              // much.
              _Action(label: l10n.modelsDownload(size), onPressed: null),
            ],
          ),
        ];
      case ModelCardStatus.notDownloaded:
        final gated = !_isVoice && !enableHymtDownload;
        return <Widget>[
          if (gated) note(l10n.modelsHymtGated),
          _Actions(
            children: <Widget>[
              _Action(
                label: l10n.modelsDownload(size),
                white: true,
                onPressed: gated
                    ? null
                    : () => unawaited(act(() => downloads.start(id))),
              ),
            ],
          ),
        ];
    }
  }

  /// FR-M4-03: after a confirm, the files go and what used them turns off.
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await Adaptive.showConfirm(
      context: context,
      title: l10n.modelsDeleteTitle(
        _isVoice ? l10n.modelsVoiceTitle : l10n.modelsTranslationTitle,
      ),
      message: _isVoice
          ? l10n.modelsDeleteVoiceBody
          : l10n.modelsDeleteTranslationBody,
      confirmLabel: l10n.modelsDeleteConfirm,
      cancelLabel: l10n.modelsDeleteKeep,
      destructive: true,
    );
    if (confirmed != true) return;
    await ref.read(modelRepositoryProvider).delete(card.entry);
    // With `tts_engine` now the phone's, nothing would ask Supertonic again:
    // asked once, it finds its model gone and lets go of its ~400 MB of
    // sessions and its clips.
    if (_isVoice) await ref.read(supertonicTtsProvider).isAvailable();
    ref
      ..invalidate(modelCardProvider(card.entry.id))
      ..invalidate(phoneSpaceProvider);
  }

  /// *Check for update*: the manifest the app carries is read again, and a
  /// model that is still current says so.
  Future<void> _check(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    ref.invalidate(modelCardProvider(card.entry.id));
    final again = await ref.read(modelCardProvider(card.entry.id).future);
    if (!context.mounted) return;
    if (cardStatusOf(again) == ModelCardStatus.ready) {
      DpToast.show(context, l10n.modelsUpToDate);
    }
  }
}

/// The card's status pill, coloured as the artboard colours it.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.live});

  final ModelCardStatus status;
  final DownloadProgress? live;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final paused =
        live?.phase == DownloadPhase.paused ||
        live?.phase == DownloadPhase.waitingForWifi;
    final (label, fill, icon) = switch (status) {
      ModelCardStatus.ready => (
        l10n.modelsStatusReady,
        // Lime, as L1's *Passed* and the artboard's *Ready*.
        tokens.color.easy,
        Icons.check,
      ),
      ModelCardStatus.downloading => (
        paused ? l10n.modelsStatusPaused : l10n.modelsStatusDownloading,
        tokens.color.learning,
        null,
      ),
      ModelCardStatus.verifying => (
        l10n.modelsStatusVerifying,
        tokens.color.learning,
        null,
      ),
      ModelCardStatus.updateAvailable => (
        l10n.modelsStatusUpdate,
        tokens.color.primary,
        null,
      ),
      ModelCardStatus.failed => (
        l10n.modelsStatusFailed,
        tokens.color.again,
        null,
      ),
      ModelCardStatus.notEnoughSpace => (
        l10n.modelsStatusNoSpace,
        tokens.color.again,
        null,
      ),
      ModelCardStatus.notDownloaded => (
        l10n.modelsStatusNotDownloaded,
        tokens.surface.muted,
        null,
      ),
    };
    return DpPill(
      label: label,
      fill: fill,
      icon: icon,
      ink: status == ModelCardStatus.notDownloaded ? tokens.color.ink : null,
    );
  }
}

/// The download's line, its bar, and the note under it.
class _Progress extends ConsumerWidget {
  const _Progress({required this.card});

  final ModelCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final live = card.live;
    final progress = (live?.progress ?? card.installed.progress).clamp(
      0.0,
      1.0,
    );
    final percent = (progress * 100).floor();
    final wifiOnly = ref
        .read(settingsProvider)
        .read(SettingKeys.modelsWifiOnly);
    final done = modelSize(l10n, (card.variant.bytes * progress).round());
    final total = modelSize(l10n, card.variant.bytes);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: DpText(
                  switch (live?.phase) {
                    DownloadPhase.waitingForWifi => l10n.modelsProgressWaiting,
                    DownloadPhase.paused => l10n.modelsProgressPaused(percent),
                    _ => l10n.modelsProgress(percent),
                  },
                  role: DpTextRole.label,
                  weight: 600,
                ),
              ),
              const SizedBox(width: 8),
              DpText(
                wifiOnly
                    ? l10n.modelsProgressBytesWifi(done, total)
                    : l10n.modelsProgressBytes(done, total),
                role: DpTextRole.label,
                weight: 400,
                color: tokens.color.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: 6),
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                height: 10,
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: tokens.surface.track,
                  color: tokens.color.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          DpText(
            wifiOnly ? l10n.modelsProgressNote : l10n.modelsProgressNoteAny,
            role: DpTextRole.caption,
            color: tokens.color.textSecondary,
          ),
        ],
      ),
    );
  }
}

/// The *Wi-Fi only* switch: `models_wifi_only`, and the downloader's rule.
class _WifiOnly extends ConsumerStatefulWidget {
  const _WifiOnly({required this.onChanged});

  final Future<void> Function(bool on) onChanged;

  @override
  ConsumerState<_WifiOnly> createState() => _WifiOnlyState();
}

class _WifiOnlyState extends ConsumerState<_WifiOnly> {
  late bool _on = ref.read(settingsProvider).read(SettingKeys.modelsWifiOnly);

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                DpText(l10n.modelsWifiOnly, role: DpTextRole.body, weight: 500),
                DpText(
                  l10n.modelsWifiOnlyNote,
                  role: DpTextRole.caption,
                  color: tokens.color.textSecondary,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AdaptiveSwitch(
            value: _on,
            semanticLabel: l10n.modelsWifiOnly,
            onChanged: (on) {
              setState(() => _on = on);
              unawaited(widget.onChanged(on));
            },
          ),
        ],
      ),
    );
  }
}

/// FR-M4-05: the voices, the chosen one marked. A tap chooses it and plays
/// its sample in it.
class _Voices extends ConsumerStatefulWidget {
  const _Voices({required this.card});

  final ModelCard card;

  @override
  ConsumerState<_Voices> createState() => _VoicesState();
}

class _VoicesState extends ConsumerState<_Voices> {
  late String _chosen = _current();

  String _current() {
    final chosen = ref.read(settingsProvider).read(SettingKeys.ttsVoice);
    return SupertonicTts.voices.containsKey(chosen)
        ? chosen!
        : SupertonicTts.voices.keys.first;
  }

  /// FR-M4-05's sample, in the voice's own name: Anna's is "Guten Tag! Ich
  /// bin Anna.", and Jonas says he is Jonas.
  static String sample(String voice) => 'Guten Tag! Ich bin $voice.';

  Future<void> _choose(String voice) async {
    setState(() => _chosen = voice);
    final settings = ref.read(settingsProvider);
    // A voice here is Supertonic's: choosing one chooses the engine too, as
    // M3's row reads it ("Supertonic · Anna", `settings.md`). Without this, a
    // voice downloaded again after a delete would never speak.
    await settings.write(SettingKeys.ttsEngine, TtsEngineSetting.supertonic);
    await settings.write(SettingKeys.ttsVoice, voice);
    try {
      await ref.read(supertonicTtsProvider).speak(sample(voice));
    } on Object {
      // The chips show only for a model that is ready; a sample that still
      // fails leaves the choice made, and the next speaker falls back.
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          DpText(
            l10n.modelsVoiceLabel,
            role: DpTextRole.caption,
            color: tokens.color.textSecondary,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final voice in SupertonicTts.voices.keys)
                DpChip(
                  label: voice,
                  kind: DpChipKind.filter,
                  selected: voice == _chosen,
                  icon: Icon(
                    Icons.play_arrow,
                    size: 14,
                    color: tokens.color.ink,
                  ),
                  semanticLabel: l10n.modelsVoicePlay(voice),
                  onTap: () => unawaited(_choose(voice)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A card's buttons, side by side and sharing the width.
class _Actions extends StatelessWidget {
  const _Actions({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final shown = children;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: <Widget>[
          for (var i = 0; i < shown.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: shown[i]),
          ],
        ],
      ),
    );
  }
}

/// A card's 40 dp button: Oat, or white where the artboard draws it white.
class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.onPressed,
    this.white = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool white;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return DpButton(
      label: label,
      onPressed: onPressed,
      kind: DpButtonKind.secondary,
      drawnHeight: 40,
      colour: onPressed != null && white ? tokens.surface.card : null,
    );
  }
}
