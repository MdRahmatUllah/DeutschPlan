import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';

/// [text]'s translation from [from] into [to], as the on-device translator
/// gives it, cached (`translation.md`, #154): *Translating…* while it runs,
/// then the line. With no answer, [none], or nothing.
class TranslationLine extends ConsumerWidget {
  const TranslationLine(
    this.text, {
    required this.from,
    required this.to,
    this.none,
    super.key,
  });

  final String text;
  final String from;
  final String to;

  /// What a missing answer says (R1's sheet); T5's sheet says nothing.
  final String? none;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final result = ref.watch(translationOfProvider(text, from, to));
    if (result.isLoading) {
      return SgText(
        l10n.translating,
        role: SgTextRole.caption,
        color: tokens.color.textSecondary,
      );
    }
    final line = result.value;
    if (line == null) {
      final none = this.none;
      return none == null
          ? const SizedBox.shrink()
          : SgText(
              none,
              role: SgTextRole.caption,
              color: tokens.color.textSecondary,
            );
    }
    // A long German compound breaks only where it must (#165).
    return SgText(
      line,
      role: SgTextRole.bodyLarge,
      german: to == 'de',
      breakTooWide: true,
    );
  }
}
