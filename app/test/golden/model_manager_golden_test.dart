// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/data/repositories/model_repository.dart';
import 'package:deutschplan/features/me/model_manager_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../features/model_manager_fixtures.dart';
import 'golden_harness.dart';

/// M4 · Model manager — #155, as the ModelManager artboards draw it: the voice
/// ready, the translation model downloading at 42 %.
void main() {
  Widget m4(BuildContext context) => ProviderScope(
    overrides: modelManagerStub(),
    child: const ModelManagerScreen(),
  );

  goldenTest('model_manager', builder: m4);
  goldenTest(
    'model_manager_ios',
    builder: m4,
    devices: <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
  );
  // The states the artboard doesn't draw: a voice that failed, and a
  // translation model the phone lacks the space for.
  goldenTest(
    'model_manager_states',
    builder: (context) => ProviderScope(
      overrides: modelManagerStub(
        voice: cardOf(voiceEntry, installed: ModelStatus.failed),
        translation: cardOf(translationEntry, shortfall: 1400000000),
      ),
      child: const ModelManagerScreen(),
    ),
    devices: <GoldenDevice>[GoldenDevice.phone],
  );
}
