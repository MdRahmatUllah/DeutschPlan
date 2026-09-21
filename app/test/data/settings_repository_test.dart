@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// `docs/02-data/user-database.md` holds the settings table, and the first
/// group below reads it rather than restating it. A default copied into a test
/// by hand tests only that someone copied it twice.
void main() {
  late AppDatabase db;
  late SettingsRepository settings;

  setUp(() async {
    db = AppDatabase.memory();
    settings = SettingsRepository(db);
    await settings.load();
  });

  tearDown(() async {
    await settings.dispose();
    await db.close();
  });

  group('against the settings table in user-database.md', () {
    final documented = _parseDocTable();

    test('the doc table was actually found and parsed', () {
      // Without this, a change to the doc's layout would empty the map and
      // every assertion below would pass by having nothing to check.
      expect(documented, hasLength(greaterThan(25)));
      expect(documented['daily_new'], '7');
    });

    test('every documented key exists, and no undocumented key does', () {
      expect(
        SettingKeys.all.map((k) => k.name).toSet(),
        documented.keys.toSet(),
      );
    });

    test('every key has no duplicate', () {
      final names = SettingKeys.all.map((k) => k.name).toList();
      expect(names.toSet(), hasLength(names.length));
    });

    for (final key in SettingKeys.all) {
      test('${key.name} defaults to what the doc says', () {
        final docValue = documented[key.name];
        final ours = key.encode(key.defaultValue);

        if (docValue == null) {
          // The doc writes an em dash for the two keys with no default.
          expect(
            ours,
            isNull,
            reason:
                '${key.name} has no documented default, so it must have '
                'none here either',
          );
          return;
        }

        // 0.90 and 0.9 are the same default written two ways; anything else
        // must match as text.
        final docNumber = double.tryParse(docValue);
        final ourNumber = ours == null ? null : double.tryParse(ours);
        if (docNumber != null && ourNumber != null) {
          expect(ourNumber, docNumber);
        } else {
          expect(ours, docValue);
        }
      });
    }
  });

  group('reading', () {
    test('an unset key gives the documented default', () {
      expect(settings.read(SettingKeys.dailyNew), 7);
      expect(settings.read(SettingKeys.themeMode), ThemeModeSetting.system);
      expect(settings.read(SettingKeys.learnerName), isNull);
    });

    test(
      'a value stored by an older or broken build gives the default',
      () async {
        // A settings row is not worth refusing to open the app over. Written
        // straight to the table, which is how a bad row would actually arrive —
        // an import, or a key whose type changed between versions.
        await db.customStatement(
          "INSERT INTO settings (key, value) VALUES ('daily_new', 'seven')",
        );
        await db.customStatement(
          "INSERT INTO settings (key, value) VALUES ('theme_mode', 'sepia')",
        );
        await db.customStatement(
          "INSERT INTO settings (key, value) VALUES ('reminder_time', '25:70')",
        );
        await settings.load();

        expect(settings.read(SettingKeys.dailyNew), 7);
        expect(settings.read(SettingKeys.themeMode), ThemeModeSetting.system);
        expect(settings.read(SettingKeys.reminderTime), (hour: 19, minute: 30));
      },
    );
  });

  group('writing', () {
    test('is visible before the database has been touched', () {
      // Not awaited on purpose: settings are read during build, and a switch
      // that lags one frame behind the finger is the thing this avoids.
      final pending = settings.write(SettingKeys.swipeToRate, true);

      expect(settings.read(SettingKeys.swipeToRate), isTrue);
      return pending;
    });

    test('survives a reload, for every key', () async {
      // One pass over the catalogue, so a key added without an encoder that
      // round-trips fails here rather than in whatever screen reads it.
      for (final key in SettingKeys.all) {
        await _writeSomethingOtherThanTheDefault(settings, key);
      }

      final before = <String, Object?>{
        for (final key in SettingKeys.all) key.name: settings.read(key),
      };

      await settings.load();

      for (final key in SettingKeys.all) {
        expect(
          settings.read(key),
          before[key.name],
          reason: '${key.name} did not survive the round trip',
        );
      }
    });

    test(
      'clearing a name removes the row rather than storing an empty one',
      () async {
        await settings.write(SettingKeys.learnerName, 'Rahmat');
        await settings.write(SettingKeys.learnerName, null);

        final rows = await db
            .customSelect(
              "SELECT COUNT(*) AS n FROM settings WHERE key = 'learner_name'",
            )
            .getSingle();
        expect(
          rows.read<int>('n'),
          0,
          reason:
              'an empty string and never having set a name must read back '
              'the same, and they only do if neither stores a row',
        );
        expect(settings.read(SettingKeys.learnerName), isNull);
      },
    );

    test('announces the key, once, and not for a no-op', () async {
      final seen = <SettingKey<Object?>>[];
      final subscription = settings.changes.listen(seen.add);
      addTearDown(subscription.cancel);

      await settings.write(SettingKeys.dailyNew, 12);
      await settings.write(SettingKeys.dailyNew, 12);
      await pumpEventQueue();

      expect(seen, <SettingKey<Object?>>[SettingKeys.dailyNew]);
    });
  });

  test('BR-PLAN-08 keys are plain settings, changed at once', () async {
    // "Changes to daily_new, revise_count, study_days_mask take effect from the
    // next day; today's plan is fixed." The second half belongs to the plan
    // engine, which generates from last_planned_date + 1 and never rewrites
    // today. Here the only requirement is that the new value is readable
    // immediately — a Settings screen that showed the old number would be a
    // different bug from the one BR-PLAN-08 is about.
    for (final key in <IntSetting>[
      SettingKeys.dailyNew,
      SettingKeys.reviseCount,
      SettingKeys.studyDaysMask,
    ]) {
      final next = settings.read(key) + 1;
      final pending = settings.write(key, next);
      expect(settings.read(key), next);
      await pending;
    }
  });
}

/// Writes a value that is not the default, so a round trip that silently drops
/// the row would fail rather than read back the default and look fine.
Future<void> _writeSomethingOtherThanTheDefault(
  SettingsRepository settings,
  SettingKey<Object?> key,
) async {
  switch (key) {
    case IntSetting():
      await settings.write(key, key.defaultValue + 3);
    case DoubleSetting():
      await settings.write(key, key.defaultValue / 2);
    case BoolSetting():
      await settings.write(key, !key.defaultValue);
    case StringSetting():
      await settings.write(key, 'something else');
    case TimeSetting():
      await settings.write(key, (hour: 6, minute: 5));
    case DateSetting():
      await settings.write(key, DateTime(2026, 9, 22));
    case EnumSetting():
      final other = key.values.firstWhere((v) => v != key.defaultValue);
      await settings.write(key, other);
  }
}

/// Reads the `## Settings keys and defaults` table out of the doc.
///
/// Rows list several keys at once — `` `tts_engine` / `tts_voice` /
/// `tts_speed` `` against `supertonic / Anna / 1.0` — so both cells split on
/// the slash and pair up. Parenthesised asides (`127 (Mon–Sun)`,
/// `` `system` (light / dark / glass) ``) are the prose around the default, not
/// part of it, so they go first — otherwise the theme row would split into
/// four.
Map<String, String?> _parseDocTable() {
  final doc = File('../docs/02-data/user-database.md').readAsStringSync();
  final section = doc
      .split('## Settings keys and defaults')
      .last
      .split('\n## ')
      .first;

  final result = <String, String?>{};
  for (final line in const LineSplitter().convert(section)) {
    if (!line.startsWith('| `')) continue;
    final cells = line.split('|').map((c) => c.trim()).toList();
    if (cells.length < 4) continue;

    final keys = cells[1].split('/').map(_clean).toList();
    final defaults = cells[2]
        .replaceAll(RegExp(r'\([^)]*\)'), '')
        .split('/')
        .map(_clean)
        .toList();
    if (keys.length != defaults.length) continue;

    for (var i = 0; i < keys.length; i++) {
      result[keys[i]] = defaults[i] == '—' ? null : defaults[i];
    }
  }
  return result;
}

String _clean(String cell) => cell.replaceAll('`', '').trim();
