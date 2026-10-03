/// On-device translation (`translation.md`), behind the small interface
/// `project-structure.md` asks for: Hy-MT2 through llamadart
/// (`HyMtTranslator`, #154), and [UnavailableTranslator] for a test without
/// a model.
abstract interface class Translator {
  /// Part of `translation_cache`'s key: a better model's answer must not be
  /// read back as an older one's.
  String get model;

  /// [text] from [from] into [to] (`de`, `en`, `bn`), or null when there is
  /// no model to ask. With a [context], [text] is translated as it reads
  /// there: a word in its sentence, in that sense (#1233). Once [abandoned]
  /// completes nobody waits for the answer: a request still waiting is
  /// dropped, one running is stopped, and either answers null (#154).
  Future<String?> translate(
    String text, {
    required String from,
    required String to,
    String? context,
    Future<void>? abandoned,
  });
}

/// No model on the phone: nothing is translated.
class UnavailableTranslator implements Translator {
  const UnavailableTranslator();

  @override
  String get model => 'none';

  @override
  Future<String?> translate(
    String text, {
    required String from,
    required String to,
    String? context,
    Future<void>? abandoned,
  }) async => null;
}
