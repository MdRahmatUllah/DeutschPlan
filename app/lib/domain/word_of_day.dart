import 'dart:math' as math;

import 'package:deutschplan/domain/plan_engine.dart' show PlanDate;

/// FR-X1-03's pick: one of [candidates] (the learned words due within three
/// days), the same one all day, and another tomorrow. Null when there are
/// none.
///
/// Seeded by the date, over the uids in order, so the pick doesn't follow the
/// order the query happens to return. It moves within a day only when the
/// candidates do: a word revised today leaves them.
String? wordOfDay(List<String> candidates, PlanDate today) {
  if (candidates.isEmpty) return null;
  final sorted = <String>[...candidates]..sort();
  final seed = int.parse(today.replaceAll('-', ''));
  return sorted[math.Random(seed).nextInt(sorted.length)];
}
