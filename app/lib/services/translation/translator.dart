/// On-device translation (`translation.md`), behind the small interface
/// `project-structure.md` asks for: Hy-MT2 through llamadart
/// (`HyMtTranslator`, #154), and [UnavailableTranslator] for a test without
/// a model.
abstract interface class Translator {
  /// Part of `translation_cache`'s key: a better model's answer must not be
  /// read back as an older one's.
  String get model;

  /// [text] from [from] into [to] (`de`, `en`, `bn`), or null when there is
  /// no model to ask.
  Future<String?> translate(
    String text, {
    required String from,
    required String to,
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
  }) async => null;
}
