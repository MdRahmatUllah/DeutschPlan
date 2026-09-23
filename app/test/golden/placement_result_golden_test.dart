import 'package:deutschplan/domain/placement.dart';
import 'package:deutschplan/features/onboarding/placement_screen.dart';

import 'golden_harness.dart';

/// S3 · the placement result goldens — #94.
///
/// The artboard's own result: 18 of 20, A2.1, and its three areas.
void main() {
  goldenTest(
    'placement_result',
    builder: (context) => PlacementFrame(
      child: PlacementResultView(
        result: const PlacementResult(
          step: 'A2.1',
          correct: 18,
          answered: 20,
          areas: <PlacementArea>[
            (area: 'A1', correct: 9, total: 10),
            (area: 'A2', correct: 4, total: 5),
            (area: PlacementSession.articles, correct: 5, total: 5),
          ],
        ),
        onDone: (_) {},
      ),
    ),
  );
}
