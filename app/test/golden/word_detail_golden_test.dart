import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/aurora_backdrop.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/data/repositories/course_meanings.dart';
import 'package:sogda/data/repositories/meaning_choice.dart';
import 'package:sogda/features/words/word_detail_screen.dart';

import '../features/word_fixtures.dart';
import '../services/fake_tts.dart';
import 'golden_harness.dart';

/// W1 · WordDetail — #140. The artboard's die Straße: the sheet at its large
/// detent on a phone, the right-hand pane on a tablet, and the deep link's
/// full page.
void main() {
  List<Override> overrides() => <Override>[
    ...wordStub(),
    fakeVoice(FakeTts()),
    // The artboards' Monday: "Next review in 8 days".
    todayProvider.overrideWithValue('2026-09-21'),
  ];

  goldenTest(
    'word_detail',
    overrides: overrides(),
    builder: (_) => const _Opener(),
  );
  // #1078: in Polish, as a Polish phone's first run shows it.
  goldenTest(
    'word_detail_pl',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    textAudit: false,
    locale: const Locale('pl'),
    overrides: overrides(),
    builder: (_) => const _Opener(),
  );
  // #1079: in Russian: Cyrillic drawn, not boxes.
  goldenTest(
    'word_detail_ru',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    textAudit: false,
    locale: const Locale('ru'),
    overrides: overrides(),
    builder: (_) => const _Opener(),
  );

  // #1119: Russian first and English second, from a course that ships
  // Russian: its meaning, its guide and its examples.
  goldenTest(
    'word_detail_ru_meanings',
    overrides: <Override>[
      wordHistoryProvider.overrideWith(
        (ref, uid) => Stream.value(artboardHistory),
      ),
      fakeVoice(FakeTts()),
      todayProvider.overrideWithValue('2026-09-21'),
      wordDetailProvider.overrideWith(
        (ref, uid) => Stream.value(
          artboardWordDetail(
            uid: uid,
            meanings: const Meanings(
              MeaningChoice('ru', 'en'),
              CourseMeanings(<String, Map<String, WordMeaningText>>{
                'uid-strasse': <String, WordMeaningText>{
                  'ru': (meaning: 'улица', pronunciation: 'штрАсэ'),
                },
              }),
            ),
            pron: 'штрАсэ',
            examples: const <({String german, String? translation})>[
              (
                german: 'Die Straße ist wegen Bauarbeiten gesperrt.',
                translation: 'Улица перекрыта из-за ремонтных работ.',
              ),
              (
                german: 'Wir wohnen in einer ruhigen Straße.',
                translation: 'Мы живём на тихой улице.',
              ),
            ],
          ),
        ),
      ),
    ],
    builder: (_) => const _Opener(),
  );

  // Cupertino presents the sheet with its own popup.
  goldenTest(
    'word_detail_ios',
    modes: <GoldenMode>[GoldenMode.light],
    devices: <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
    overrides: overrides(),
    builder: (_) => const _Opener(),
  );

  // BR-CONTENT-02: a meaning a course update changed this week.
  goldenTest(
    'word_detail_updated',
    devices: <GoldenDevice>[GoldenDevice.phone],
    overrides: <Override>[
      ...overrides(),
      recentlyUpdatedProvider.overrideWith(
        (ref) async => <String>{'uid-strasse'},
      ),
    ],
    builder: (_) => const _Opener(),
  );

  goldenTest(
    'word_detail_page',
    devices: <GoldenDevice>[GoldenDevice.phone],
    overrides: overrides(),
    builder: (_) => const WordDetailScreen(uid: 'uid-strasse'),
  );
}

/// A blank screen that opens W1 as soon as it is drawn, as a list row's tap
/// would.
class _Opener extends StatefulWidget {
  const _Opener();

  @override
  State<_Opener> createState() => _OpenerState();
}

class _OpenerState extends State<_Opener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => showWordDetail(context, 'uid-strasse'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scaffold = AdaptiveScaffold(
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
      body: const SizedBox.expand(),
    );
    return tokens.isGlass
        ? AuroraBackdrop(leading: tokens.color.die, child: scaffold)
        : scaffold;
  }
}
