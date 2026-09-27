import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

// A quiz's names and colours, for L2's last quiz card, L7, L8 and L9: the
// quiz's own, not the Learn tab's (#702).

/// "16", or "15.5": a quiz scores in halves (BR-ANS-04).
String quizPoints(double points) => points == points.roundToDouble()
    ? '${points.round()}'
    : points.toStringAsFixed(1);

/// A quiz result's colour (`quiz.md`): Lime from 80 %, Sun from 50 %, Coral
/// under.
Color quizColour(SgPalette palette, double share) => share >= 0.8
    ? palette.easy
    : share >= 0.5
    ? palette.learning
    : palette.again;

/// A quiz named by its length, as L2's tiles name them.
String quizKindName(AppLocalizations l10n, int length) => switch (length) {
  10 => l10n.quizQuick,
  20 => l10n.quizStandard,
  30 => l10n.quizLong,
  _ => l10n.quizCustom,
};

/// A quiz direction as the app names it: "DE → EN", "Articles".
String quizDirectionName(AppLocalizations l10n, String direction) =>
    switch (direction) {
      'deEn' => 'DE → EN',
      'deBn' => 'DE → বাংলা',
      'enDe' => 'EN → DE',
      'articles' => l10n.quizDirectionArticles,
      'listening' => l10n.quizDirectionListening,
      'forms' => l10n.quizForms,
      'compare' => l10n.quizDirectionCompare,
      _ => l10n.quizDirectionMixed,
    };
