// The ProviderScope below is the only one in the tree — the harness has none —
// so it is a root scope in fact. The lint cannot tell from inside a builder.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/features/onboarding/onboarding_pace_page.dart';
import 'package:deutschplan/features/onboarding/onboarding_start_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'golden_harness.dart';

/// S2 page 4 · Daily pace goldens — #90.
///
/// The defaults — 7 a day, 10 revisions, every day — as the artboard draws
/// them. The estimate uses A1.1's shipped 637 words rather than the
/// artboard's 480, so it reads 91 days where the artboard says 69.
void main() {
  goldenTest(
    'onboarding_pace',
    builder: (context) => ProviderScope(
      overrides: <Override>[
        courseStepsProvider.overrideWith((ref) async => _shipped),
      ],
      child: OnboardingPacePage(onContinue: () {}, onBack: () {}),
    ),
  );
}

const List<CourseStep> _shipped = <CourseStep>[
  (code: 'A1.1', levelCode: 'A1', wordCount: 637),
  (code: 'A1.2', levelCode: 'A1', wordCount: 679),
  (code: 'A2.1', levelCode: 'A2', wordCount: 540),
  (code: 'A2.2', levelCode: 'A2', wordCount: 498),
  (code: 'B1.1', levelCode: 'B1', wordCount: 194),
  (code: 'B1.2', levelCode: 'B1', wordCount: 185),
  (code: 'B2.1', levelCode: 'B2', wordCount: 594),
  (code: 'B2.2', levelCode: 'B2', wordCount: 625),
  (code: 'C1.1', levelCode: 'C1', wordCount: 494),
  (code: 'C1.2', levelCode: 'C1', wordCount: 469),
  (code: 'C2.1', levelCode: 'C2', wordCount: 342),
  (code: 'C2.2', levelCode: 'C2', wordCount: 337),
];
