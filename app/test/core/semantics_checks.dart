import 'dart:ui' show Tristate;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart' show RenderBox, RenderObject;
import 'package:flutter/semantics.dart'
    show DebugSemanticsDumpOrder, SemanticsAction, SemanticsNode;
import 'package:flutter/widgets.dart' show Wrap;
import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/core/adaptive/adaptive.dart';

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

/// #952: [wrap]'s tappables, as it draws them and as a screen reader reads
/// them, and how many runs they take. Each `AdaptiveTapTarget` under it is
/// one, but not one inside another (a chip's own button); one a reader can't
/// reach (under a sheet's barrier, offstage, merged) is left out. The Wrap
/// draws them in its children's order: run by run, left to right. A reader
/// reads them so unless two runs' grown targets overlap: Flutter then groups
/// the runs into one row and sorts it by x, column by column
/// (`AdaptiveTapTarget.runSpacing`). Call with semantics enabled.
({List<String> drawn, List<String> read, int runs}) wrapOrder(
  WidgetTester tester,
  Finder wrap,
) {
  final position = <int, int>{};
  void walk(SemanticsNode node) {
    position[node.id] = position.length;
    for (final child in node.debugListChildrenInOrder(
      DebugSemanticsDumpOrder.traversalOrder,
    )) {
      walk(child);
    }
  }

  walk(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  final boxes = <RenderBox>[
    for (final element
        in find
            .descendant(of: wrap, matching: find.byType(AdaptiveTapTarget))
            .evaluate())
      element.renderObject! as RenderBox,
  ];
  bool within(RenderObject inner) {
    for (RenderObject? at = inner.parent; at != null; at = at.parent) {
      if (boxes.contains(at)) return true;
    }
    return false;
  }

  final targets = <(RenderBox, SemanticsNode)>[
    for (final box in boxes)
      if (!within(box))
        if (box.debugSemantics case final node?
            when position.containsKey(node.id) && !node.isMergedIntoParent)
          (box, node),
  ];
  var runs = targets.isEmpty ? 0 : 1;
  for (var i = 1; i < targets.length; i++) {
    final left = targets[i].$1.localToGlobal(Offset.zero).dx;
    if (left <= targets[i - 1].$1.localToGlobal(Offset.zero).dx) runs++;
  }
  String label((RenderBox, SemanticsNode) target) =>
      target.$2.getSemanticsData().label;
  return (
    drawn: targets.map(label).toList(),
    read:
        (targets.toList()..sort(
              (a, b) => position[a.$2.id]!.compareTo(position[b.$2.id]!),
            ))
            .map(label)
            .toList(),
    runs: runs,
  );
}

/// #952: every `Wrap` of tappables on screen reads as it draws them.
void expectWrapsReadAsDrawn(WidgetTester tester) {
  final misread = <String>[
    for (final element in find.byType(Wrap).evaluate())
      if (wrapOrder(tester, find.byElementPredicate((e) => e == element))
          case (:final drawn, :final read, runs: _)
          when !listEquals(drawn, read))
        '$drawn read as $read',
  ];
  expect(misread, isEmpty, reason: 'a Wrap read column by column (#952)');
}

/// #952: the `Wrap` around [child] wraps, two or more to a run somewhere,
/// and a screen reader reads its tappables as it draws them.
void expectWrapReadsAsDrawn(WidgetTester tester, Finder child) {
  final order = wrapOrder(
    tester,
    find.ancestor(of: child, matching: find.byType(Wrap)).first,
  );
  expect(
    order.runs,
    inExclusiveRange(1, order.drawn.length),
    reason: 'a layout that wraps, two or more to a run',
  );
  expect(order.read, order.drawn);
}
