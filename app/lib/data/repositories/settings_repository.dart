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

  /// `null` until [load] has run. Nullable rather than empty so a read before
  /// load fails instead of quietly answering with defaults.
  Map<String, String>? _values;
  final StreamController<SettingKey<Object?>> _changes =
      StreamController<SettingKey<Object?>>.broadcast();

  /// Fires after each [write] that changed something. `bootstrap()` (#66) wires
  /// this to the providers; until then a listener can watch it directly.
  Stream<SettingKey<Object?>> get changes => _changes.stream;

  /// Reads the table into memory. Call once, before the first [read].
  Future<void> load() async {
    final rows = await _db.select(_db.settings).get();
    _values = <String, String>{for (final row in rows) row.key: row.value};
  }

  /// The current value, or the documented default when nothing is stored.
  T read<T>(SettingKey<T> key) {
    // Not an assert: those are stripped from release builds, and the failure
    // this guards against is silent there — every read answering with the
    // default, which looks to the learner like their settings reset rather
    // than like a bug anyone can report.
    final raw = _loadedValues[key.name];
    return raw == null ? key.defaultValue : key.decode(raw);
  }

  Map<String, String> get _loadedValues =>
      _values ??
      (throw StateError(
        'SettingsRepository.load() has not run. Reading now would answer '
        'with every default and look like the learner lost their settings.',
      ));

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
      final had = _loadedValues.remove(key.name) != null;
      if (!had) return Future<void>.value();
      _changes.add(key);
      return (_db.delete(
        _db.settings,
      )..where((t) => t.key.equals(key.name))).go();
    }

    if (_loadedValues[key.name] == encoded) return Future<void>.value();
    _loadedValues[key.name] = encoded;
    _changes.add(key);

    return _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(key: key.name, value: encoded),
        );
  }

  /// Runs [query] with the current value of [key], and runs it again with the
  /// new value whenever [key] changes.
  ///
  /// A drift query takes its variables when the stream is built, so a stream
  /// built once keeps the value it was built with for as long as it is open.
  /// A threshold the learner moves mid-session — `done_stability_days` is the
  /// one BR-STATUS-02 cares about — has to rebuild the query, not just
  /// re-emit it. The old subscription is dropped as soon as the new one is
  /// made, so nothing arrives from the stale query.
  Stream<R> switchOn<T, R>(SettingKey<T> key, Stream<R> Function(T) query) {
    StreamSubscription<R>? inner;
    StreamSubscription<SettingKey<Object?>>? outer;
    late StreamController<R> controller;

    void run() {
      inner?.cancel();
      inner = query(read(key))
          .listen(controller.add, onError: controller.addError);
    }

    controller = StreamController<R>(
      onListen: () {
        run();
        outer = _changes.stream
            .where((changed) => changed == key)
            .listen((_) => run());
      },
      onCancel: () async {
        await outer?.cancel();
        await inner?.cancel();
      },
    );
    return controller.stream;
  }

  /// Puts a key back to its documented default. Used by Reset (M7).
  Future<void> clear<T>(SettingKey<T> key) => write(key, key.defaultValue);

  Future<void> dispose() => _changes.close();
}
