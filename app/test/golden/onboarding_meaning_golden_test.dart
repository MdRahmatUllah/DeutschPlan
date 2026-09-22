// The ProviderScope below is the only one in the tree — the harness has none —
// so it is a root scope in fact. The lint cannot tell from inside a builder.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/features/onboarding/onboarding_meaning_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'golden_harness.dart';

/// S2 page 2 · Meaning language goldens — #88.
///
/// *Both* picked, as the artboard draws it, and the sample as content.db has
/// it — the artboard shortens the Bangla to its first word.
void main() {
  goldenTest(
    'onboarding_meaning',
    builder: (context) => ProviderScope(
      overrides: <Override>[
        languagesProvider.overrideWith(_BothPicked.new),
        meaningSampleProvider.overrideWith(
          (ref) async => const WordWithState(
            word: Word(
              uid: meaningSampleUid,
              sublevelCode: 'A1.1',
              levelCode: 'A1',
              seq: 1,
              seqInSublevel: 1,
              article: 'die',
              german: 'Wohnung',
              english: 'flat / apartment',
              bangla: 'ফ্ল্যাট / অ্যাপার্টমেন্ট',
              searchKey: 'wohnung',
              searchKeyAlt: 'wohnung',
            ),
            state: null,
            status: WordStatus.todo,
          ),
        ),
      ],
      child: OnboardingMeaningPage(onContinue: () {}, onBack: () {}),
    ),
  );
}

class _BothPicked extends Languages {
  @override
  ({MeaningLanguage meaning, UiLanguage ui}) build() =>
      (meaning: MeaningLanguage.both, ui: UiLanguage.english);
}
