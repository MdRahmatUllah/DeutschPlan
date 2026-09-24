import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/services/translation/translator.dart';
import 'package:drift/drift.dart';

/// [Translator] through `translation_cache` (`translation.md`): a sentence is
/// translated once per model and language pair, then read back.
class TranslationRepository {
  TranslationRepository(this._db, this._translator, this._now);

  final AppDatabase _db;
  final Translator _translator;
  final DateTime Function() _now;

  /// [text] in [to], from the cache or the model; null when neither has it.
  Future<String?> translate(
    String text, {
    required String from,
    required String to,
  }) async {
    final model = _translator.model;
    final cached =
        await (_db.select(_db.translationCache)..where(
              (t) =>
                  t.srcLang.equals(from) &
                  t.tgtLang.equals(to) &
                  t.srcText.equals(text) &
                  t.model.equals(model),
            ))
            .getSingleOrNull();
    if (cached != null) return cached.result;

    final result = await _translator.translate(text, from: from, to: to);
    if (result == null) return null;
    await _db
        .into(_db.translationCache)
        .insertOnConflictUpdate(
          TranslationCacheCompanion.insert(
            srcLang: from,
            tgtLang: to,
            srcText: text,
            model: model,
            result: result,
            createdAt: _now().toUtc().toIso8601String(),
          ),
        );
    return result;
  }
}
