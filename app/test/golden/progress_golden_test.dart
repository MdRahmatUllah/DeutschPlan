// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart' show find;
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/domain/progress_stats.dart' show ProgressRange;
import 'package:sogda/features/me/progress_screen.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';

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
  // #1078: in Polish, as a Polish phone's first run shows it.
  goldenTest(
    'progress_pl',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    textAudit: false,
    locale: const Locale('pl'),
    builder: screen,
  );
  // #1079: in Russian: Cyrillic drawn, not boxes.
  goldenTest(
    'progress_ru',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    textAudit: false,
    locale: const Locale('ru'),
    builder: screen,
  );
  // #1060: the Month range, its last label ("28 Sep") inside the card.
  goldenTest(
    'progress_month',
    devices: const <GoldenDevice>[GoldenDevice.phone],
    builder: (context) => ProviderScope(
      overrides: <Override>[
        progressViewProvider.overrideWith(
          (ref, range) async => range == ProgressRange.month
              ? monthProgress()
              : artboardProgress(),
        ),
        stepProgressProvider.overrideWith(
          (ref) => Stream.value(artboardProgressSteps()),
        ),
      ],
      child: const ProgressScreen(),
    ),
    act: (tester) async {
      // In the audit's Bangla too.
      final l10n = AppLocalizations.of(
        tester.element(find.byType(ProgressScreen)),
      );
      await tester.tap(find.text(l10n.progressMonth));
      await tester.pumpAndSettle();
    },
  );
  goldenTest(
    'progress_ios',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
    builder: screen,
  );
}
