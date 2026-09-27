import 'dart:ui' show Tristate;

import 'package:flutter/semantics.dart'
    show DebugSemanticsDumpOrder, SemanticsAction, SemanticsNode;
import 'package:flutter_test/flutter_test.dart';

/// The labels of tappable semantics nodes under another tappable node, from
/// [root] down, or the whole tree (#749, #912). Empty when every button
/// stands alone.
///
/// A `Semantics(button: true)` with no `container` merges its flag, label
/// and tap up into whatever node holds it. When that is a list item holding
/// several cards, the whole list becomes one button: a screen reader reads
/// it first, outlines every card, and presses it on any tap between them.
/// The cards under it are the tappable nodes this returns.
///
/// Nodes merged into their parent are skipped: a reader never sees them,
/// they are part of the parent's one node. Call with semantics enabled
/// (`tester.ensureSemantics()`).
List<String> tapsInsideTaps(WidgetTester tester, [Finder? root]) {
  // A tap, a long press, or a toggle's state: anything a reader acts on.
  bool tappable(SemanticsNode node) {
    final data = node.getSemanticsData();
    return data.hasAction(SemanticsAction.tap) ||
        data.hasAction(SemanticsAction.longPress) ||
        data.flagsCollection.isToggled != Tristate.none;
  }

  final inside = <String>[];
  void walk(SemanticsNode node, bool under) {
    if (node.isMergedIntoParent) return;
    if (under && tappable(node)) inside.add(node.getSemanticsData().label);
    node.visitChildren((child) {
      walk(child, under || tappable(node));
      return true;
    });
  }

  walk(
    root != null
        ? tester.getSemantics(root)
        : tester
              .binding
              .renderViews
              .first
              .owner!
              .semanticsOwner!
              .rootSemanticsNode!,
    false,
  );
  return inside;
}

/// The labels a screen reader reaches under [root], in its reading order
/// (#853): each node's children as it traverses them, merged nodes skipped.
List<String> readingOrder(WidgetTester tester, Finder root) {
  final order = <String>[];
  void walk(SemanticsNode node) {
    if (node.isMergedIntoParent) return;
    final label = node.getSemanticsData().label;
    if (label.isNotEmpty) order.add(label);
    for (final child in node.debugListChildrenInOrder(
      DebugSemanticsDumpOrder.traversalOrder,
    )) {
      walk(child);
    }
  }

  walk(tester.getSemantics(root));
  return order;
}
