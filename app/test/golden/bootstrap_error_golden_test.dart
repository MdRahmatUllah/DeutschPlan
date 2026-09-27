import 'package:sogda/bootstrap.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/features/bootstrap/bootstrap_error_screen.dart';

import 'golden_harness.dart';

/// S1 · bootstrap error goldens — #86.
///
/// The content step with a database that opened, because that is the state
/// carrying both actions — a golden of the one-button variant would not show
/// the export affordance the criterion is about.
void main() {
  goldenTest(
    'bootstrap_error',
    builder: (context) => BootstrapErrorScreen(
      failure: BootstrapFailure(
        step: BootstrapStep.content,
        error: 'content.db could not be installed',
        stackTrace: StackTrace.empty,
        db: AppDatabase.memory(),
      ),
      onRetry: () {},
      onExport: () async => true,
    ),
  );
}
