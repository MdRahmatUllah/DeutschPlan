import 'dart:async';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';

/// Every preference, read synchronously and written through to `settings`.
///
/// The whole table is loaded once by [load] and kept in memory. That is what
/// makes [read] synchronous, which matters because settings are read during
/// `build` — a theme, a language, whether to autoplay — and an async read there
/// means a frame of the wrong thing first.
///
/// It is affordable: the doc lists thirty-one keys, and nothing else writes to
/// the table, so the cache cannot go stale behind our back.
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  final Map<String, String> _values = <String, String>{};
  final StreamController<SettingKey<Object?>> _changes =
      StreamController<SettingKey<Object?>>.broadcast();

  bool _loaded = false;

  /// Fires after each [write] that changed something. `bootstrap()` (#66) wires
  /// this to the providers; until then a listener can watch it directly.
  Stream<SettingKey<Object?>> get changes => _changes.stream;

  /// Reads the table into memory. Call once, before the first [read].
  Future<void> load() async {
    final rows = await _db.select(_db.settings).get();
    _values
      ..clear()
      ..addEntries(rows.map((r) => MapEntry(r.key, r.value)));
    _loaded = true;
  }

  /// The current value, or the documented default when nothing is stored.
  T read<T>(SettingKey<T> key) {
    assert(
      _loaded,
      'call load() before reading — otherwise every read is the '
      'default and the learner sees their settings reset for one frame',
    );
    final raw = _values[key.name];
    return raw == null ? key.defaultValue : key.decode(raw);
  }

  /// Updates the cache immediately, then persists.
  ///
  /// The order is the point: the caller and everything reading through [read]
  /// see the new value before the database has been touched, so a switch does
  /// not lag a frame behind the finger. BR-PLAN-08's other half — that
  /// `daily_new`, `revise_count` and `study_days_mask` only reach the plan from
  /// tomorrow — is the plan engine's, which generates from
  /// `last_planned_date + 1` and never rewrites today.
  Future<void> write<T>(SettingKey<T> key, T value) {
    final encoded = key.encode(value);

    if (encoded == null) {
      // Absent and "cleared" must read back the same, so clearing deletes the
      // row rather than storing an empty string.
      final had = _values.remove(key.name) != null;
      if (!had) return Future<void>.value();
      _changes.add(key);
      return (_db.delete(
        _db.settings,
      )..where((t) => t.key.equals(key.name))).go();
    }

    if (_values[key.name] == encoded) return Future<void>.value();
    _values[key.name] = encoded;
    _changes.add(key);

    return _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(key: key.name, value: encoded),
        );
  }

  /// Puts a key back to its documented default. Used by Reset (M7).
  Future<void> clear<T>(SettingKey<T> key) => write(key, key.defaultValue);

  Future<void> dispose() => _changes.close();
}
