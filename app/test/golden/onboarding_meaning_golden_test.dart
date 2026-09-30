// The ProviderScope below is the only one in the tree — the harness has none —
// so it is a root scope in fact. The lint cannot tell from inside a builder.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart' show BuildContext, Locale, Widget;
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/repositories/meaning_choice.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/word_repository.dart';
import 'package:sogda/features/onboarding/onboarding_meaning_page.dart';

import 'golden_harness.dart';

/// S2 page 2 · Meaning language goldens — #88.
///
/// *Both* picked, as the artboard draws it, and the sample as content.db has
/// it — the artboard shortens the Bangla to its first word.
void main() {
  Widget page(BuildContext context) => ProviderScope(
    overrides: <Override>[
      languagesProvider.overrideWith(_BothPicked.new),
      meaningSampleProvider.overrideWith(
        (ref) async => const WordWithState(
          word: Word(
            kind: 'vocab',
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
  );
  goldenTest('onboarding_meaning', builder: page);
  // #1078: in Polish, as a Polish phone's first run shows it.
  goldenTest(
    'onboarding_meaning_pl',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    textAudit: false,
    locale: const Locale('pl'),
    builder: page,
  );
  // #1079: in Russian: Cyrillic drawn, not boxes.
  goldenTest(
    'onboarding_meaning_ru',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    textAudit: false,
    locale: const Locale('ru'),
    builder: page,
  );
}

class _BothPicked extends Languages {
  @override
  ({MeaningChoice meaning, UiLanguage ui}) build() =>
      (meaning: const MeaningChoice('en', 'bn'), ui: UiLanguage.english);
}
