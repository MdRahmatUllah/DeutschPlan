import 'package:background_downloader/background_downloader.dart';
import 'package:deutschplan/data/repositories/model_repository.dart';

/// Starting a model download, and nothing more yet.
///
/// FR-S2-06: *Download now* "MUST start the Supertonic download in the
/// background and continue onboarding". This queues the files with the
/// platform's own downloader, which keeps going with the app closed. #156
/// is the rest of the manager — resuming, Wi-Fi-only, checking and
/// activating the files once they are all there.
abstract interface class ModelDownloads {
  /// Queues every file of [modelId]'s first variant into its staging
  /// directory, and returns once they are queued — not once they arrive.
  Future<void> start(String modelId);
}

class BackgroundModelDownloads implements ModelDownloads {
  BackgroundModelDownloads(this._models, [FileDownloader? downloader])
    : _downloader = downloader ?? FileDownloader();

  final ModelRepository _models;
  final FileDownloader _downloader;

  @override
  Future<void> start(String modelId) async {
    final model = (await _models.manifest()).model(modelId);
    if (model == null || model.variants.isEmpty) {
      throw ArgumentError.value(modelId, 'modelId', 'is not in the manifest');
    }
    await _models.beginDownload(modelId);

    await _downloader.enqueueAll(<Task>[
      for (final file in model.variants.first.files)
        DownloadTask(
          url: file.url.toString(),
          filename: file.name,
          // Relative to app support, where `ModelRepository` keeps its
          // staging directories, so the platform resolves the same place.
          baseDirectory: BaseDirectory.applicationSupport,
          directory: ModelRepository.stagingPath(modelId),
          group: modelId,
          updates: Updates.statusAndProgress,
          allowPause: true,
          retries: 3,
        ),
    ]);
  }
}
