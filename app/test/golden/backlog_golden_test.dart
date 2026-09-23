// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/features/backlog/backlog_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_harness.dart';

/// T4 · Backlog — #108. The artboard: fourteen words from Tuesday and
/// Wednesday, *Study all*, the pause switch, and Wednesday's rows on top.
void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  setUpAll(() async {
    db = AppDatabase.memory();
    settings = SettingsRepository(db);
    await settings.load();
  });
  tearDownAll(() async {
    await settings.dispose();
    await db.close();
  });

  goldenTest(
    'backlog',
    builder: (context) => ProviderScope(
      overrides: [
        settingsProvider.overrideWithValue(settings),
        backlogProvider.overrideWith(_Artboard.new),
      ],
      child: const BacklogScreen(),
    ),
  );
}

class _Artboard extends Backlog {
  static const List<(String, String?, String, String)> _words =
      <(String, String?, String, String)>[
        ('2026-09-16', 'die', 'Miete', 'rent'),
        ('2026-09-16', 'der', 'Nachbar', 'neighbour'),
        ('2026-09-16', 'die', 'Heizung', 'heating'),
        ('2026-09-16', 'die', 'Kaution', 'deposit'),
        ('2026-09-16', 'das', 'Zimmer', 'room'),
        ('2026-09-16', 'die', 'Küche', 'kitchen'),
        ('2026-09-16', 'der', 'Balkon', 'balcony'),
        ('2026-09-15', 'der', 'Keller', 'cellar, basement'),
        ('2026-09-15', 'der', 'Vermieter', 'landlord'),
        ('2026-09-15', 'die', 'Wohnung', 'flat'),
        ('2026-09-15', 'das', 'Bad', 'bathroom'),
        ('2026-09-15', 'der', 'Flur', 'hallway'),
        ('2026-09-15', 'die', 'Treppe', 'stairs'),
        ('2026-09-15', 'der', 'Aufzug', 'lift'),
      ];

  @override
  Stream<List<BacklogWord>> build() => Stream.value(<BacklogWord>[
    for (final (i, (date, article, german, english)) in _words.indexed)
      (
        planDate: date,
        meaning: english,
        word: WordWithState(
          word: Word(
            uid: 'w$i',
            sublevelCode: 'A2.1',
            levelCode: 'A2',
            seq: i,
            seqInSublevel: i,
            article: article,
            german: german,
            english: english,
            searchKey: german.toLowerCase(),
            searchKeyAlt: german.toLowerCase(),
          ),
          state: null,
          status: WordStatus.todo,
        ),
      ),
  ]);
}
