/// On-device translation (`translation.md`), behind the small interface
/// `project-structure.md` asks for. #154's Hy-MT model fills it; until then
/// [UnavailableTranslator] is all there is, and `mt_enabled` stays off.
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
