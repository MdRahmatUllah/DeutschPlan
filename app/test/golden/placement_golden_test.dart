// The ProviderScope below is the only one in the tree — the harness has none —
// so it is a root scope in fact. The lint cannot tell from inside a builder.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/domain/placement.dart';
import 'package:deutschplan/features/onboarding/onboarding_start_page.dart';
import 'package:deutschplan/features/onboarding/placement_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'golden_harness.dart';

/// S3 · the placement check goldens — #93.
///
/// The first question, from a fixed seed and a pool shaped like the real
/// A1.1: `die Wohnung` among three other nouns, as the artboard draws it.
void main() {
  final db = AppDatabase.memory();

  goldenTest(
    'placement',
    builder: (context) => ProviderScope(
      overrides: <Override>[
        languagesProvider.overrideWith(
          () => _FixedLanguages(MeaningLanguage.english),
        ),
        contentDaoProvider.overrideWithValue(_A1Dao(db)),
        courseStepsProvider.overrideWith(
          (ref) async => const <CourseStep>[
            (code: 'A1.1', levelCode: 'A1', wordCount: 637),
            (code: 'A1.2', levelCode: 'A1', wordCount: 679),
          ],
        ),
      ],
      child: PlacementScreen(seed: 2, onDone: (_) {}),
    ),
  );

  // #539: a long compound, whichever the seed picks, breaks at a syllable
  // at 200 % with its "-", as a headword does; the text audit checks it.
  goldenTest(
    'placement_long',
    builder: (context) => ProviderScope(
      overrides: <Override>[
        languagesProvider.overrideWith(
          () => _FixedLanguages(MeaningLanguage.english),
        ),
        contentDaoProvider.overrideWithValue(_A1Dao(db, _A1Dao.long)),
        courseStepsProvider.overrideWith(
          (ref) async => const <CourseStep>[
            (code: 'A1.1', levelCode: 'A1', wordCount: 637),
            (code: 'A1.2', levelCode: 'A1', wordCount: 679),
          ],
        ),
      ],
      child: PlacementScreen(seed: 2, onDone: (_) {}),
    ),
  );
}

class _A1Dao extends ContentDao {
  _A1Dao(super.db, [this.nouns = _nouns]);

  final List<(String, String, String)> nouns;

  static const List<(String, String, String)> long = <(String, String, String)>[
    ('die', 'Geschwindigkeitsbegrenzung', 'speed limit'),
    ('die', 'Haftpflichtversicherung', 'liability insurance'),
    ('die', 'Wohnungsgeberbestätigung', "landlord's confirmation"),
    ('der', 'Einwohnermeldeamt', "residents' registration office"),
  ];

  static const List<(String, String, String)> _nouns =
      <(String, String, String)>[
        ('die', 'Wohnung', 'flat, apartment'),
        ('die', 'Küche', 'kitchen'),
        ('die', 'Straße', 'street'),
        ('der', 'Tisch', 'table'),
      ];

  @override
  Future<List<PlacementWord>> placementPool(String step) async =>
      <PlacementWord>[
        for (final (i, (article, german, english)) in nouns.indexed)
          PlacementWord(
            uid: '$step-$i',
            article: article,
            german: german,
            english: english,
            pos: 'noun',
          ),
      ];
}

class _FixedLanguages extends Languages {
  _FixedLanguages(this.meaning);

  final MeaningLanguage meaning;

  @override
  ({MeaningLanguage meaning, UiLanguage ui}) build() =>
      (meaning: meaning, ui: UiLanguage.english);
}
