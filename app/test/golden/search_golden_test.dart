import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/features/search/search_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../features/search_fixtures.dart';
import '../services/fake_tts.dart';
import 'golden_harness.dart';

/// R1 · Search — #137. The artboard's "strase": die Straße as the exact
/// match, two that start with it, die Strafe as a typo, and a sentence.
void main() {
  goldenTest(
    'search',
    overrides: [
      searchResultsProvider.overrideWith(
        (ref, query) => Stream.value(artboardSearch()),
      ),
      ttsProvider.overrideWithValue(FakeTts()),
    ],
    builder: (_) => const SearchScreen(),
    act: (tester) async {
      await tester.enterText(find.byType(TextField), 'strase');
      await tester.pump(SearchScreen.debounce);
      await tester.pumpAndSettle();
    },
  );
}
