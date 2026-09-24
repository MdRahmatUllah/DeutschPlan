// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/features/me/progress_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';

import '../features/progress_fixtures.dart';
import 'golden_harness.dart';

/// M2 · Progress detail — #145. The Progress artboard's week: 85 cards,
/// 88 % against 90 %, three steps begun, 6 h 48 and a 12-day streak of 19.
void main() {
  Widget screen(BuildContext context) => ProviderScope(
    overrides: <Override>[
      progressViewProvider.overrideWith(
        (ref, range) async => artboardProgress(),
      ),
      stepProgressProvider.overrideWith(
        (ref) => Stream.value(artboardProgressSteps()),
      ),
    ],
    child: const ProgressScreen(),
  );

  goldenTest('progress', builder: screen);
  goldenTest(
    'progress_ios',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
    builder: screen,
  );
}
