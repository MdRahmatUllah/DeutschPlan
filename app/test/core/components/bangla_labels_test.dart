import 'dart:ui' show LocaleStringAttribute, Tristate;

import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/components/sg_button.dart';
import 'package:sogda/core/components/sg_chip.dart';
import 'package:sogda/core/components/sg_slider.dart';
import 'package:sogda/core/components/sg_speaker_button.dart';
import 'package:sogda/core/components/sg_stepper.dart';
import 'package:sogda/core/theme/app_theme.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/main.dart'
    show appLocalizationsDelegates, supportedLocales;

import '../text_clipping.dart';

/// #743: a control's Bangla label carries its bn-BD tag, as text on screen
/// does. The labels were plain strings, and TalkBack on an English phone read
/// them with its English voice, garbling or skipping them.
void main() {
  const bn = 'শুরু করুন';

  List<(int, int)> bnRanges(SemanticsNode node) => <(int, int)>[
    for (final attribute in node.attributedLabel.attributes)
      if (attribute is LocaleStringAttribute &&
          attribute.locale == SgScript.bnBD)
        (attribute.range.start, attribute.range.end),
  ];

  group('the label', () {
    test('a Bangla run is tagged bn-BD over exactly its range', () {
      final mixed = SgScript.attributedLabel('Speak · বলুন')!;
      final tagged = mixed.attributes.whereType<LocaleStringAttribute>();

      expect(mixed.string, 'Speak · বলুন');
      expect(tagged, hasLength(1));
      expect(
        mixed.string.substring(
          tagged.single.range.start,
          tagged.single.range.end,
        ),
        'বলুন',
      );
    });

    test('English carries no tag, and null stays null', () {
      expect(SgScript.attributedLabel('Start')!.attributes, isEmpty);
      expect(SgScript.attributedLabel(null), isNull);
    });
  });

  for (final (name, control) in <(String, Widget)>[
    ('SgButton', SgButton(label: bn, onPressed: () {})),
    ('SgChip', SgChip(label: bn, onTap: () {})),
    ('SgSpeakerButton', SgSpeakerButton(onPressed: () {}, semanticLabel: bn)),
    (
      'AdaptiveSwitch',
      AdaptiveSwitch(value: true, onChanged: (_) {}, semanticLabel: bn),
    ),
    (
      'SgStepper',
      SgStepper(
        value: 5,
        min: 1,
        max: 10,
        onChanged: (_) {},
        decreaseLabel: bn,
        increaseLabel: 'More',
      ),
    ),
  ]) {
    testWidgets('#743 $name tags a Bangla label bn-BD', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          home: Scaffold(body: Center(child: control)),
        ),
      );

      final node = tester.getSemantics(find.bySemanticsLabel(RegExp(bn)).first);
      expect(bnRanges(node), isNotEmpty, reason: '${node.label} untagged');
      handle.dispose();
    });
  }

  testWidgets('#877 a tab of the bar reads its Bangla tagged bn-BD, and still '
      'selects and taps as a tab', (tester) async {
    final handle = tester.ensureSemantics();
    final tapped = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: supportedLocales,
        home: Scaffold(
          bottomNavigationBar: AdaptiveNavBar(
            destinations: const <AdaptiveNavDestination>[
              AdaptiveNavDestination(
                icon: Icons.today_outlined,
                selectedIcon: Icons.today,
                label: 'আজ',
              ),
              AdaptiveNavDestination(
                icon: Icons.school_outlined,
                selectedIcon: Icons.school,
                label: 'শিখুন',
              ),
            ],
            currentIndex: 0,
            onSelected: tapped.add,
          ),
        ),
      ),
    );

    final today = tester.getSemantics(find.bySemanticsLabel(RegExp('^আজ')));
    // Material's tab node takes ours in: read what it sends.
    final data = today.getSemanticsData();
    expect(
      data.attributedLabel.attributes.whereType<LocaleStringAttribute>().where(
        (tag) => tag.locale == SgScript.bnBD && tag.range.start == 0,
      ),
      isNotEmpty,
    );
    expect(data.label, contains('1'), reason: "Material's tab of n");
    expect(data.flagsCollection.isSelected, Tristate.isTrue);
    final learn = tester.getSemantics(find.bySemanticsLabel(RegExp('^শিখুন')));
    expect(
      learn.getSemanticsData().flagsCollection.isSelected,
      isNot(Tristate.isTrue),
    );
    tester.semantics.tap(find.semantics.byLabel(RegExp('^শিখুন')));
    expect(tapped, <int>[1]);
    handle.dispose();
  });

  testWidgets(
    '#877 SgSlider tags its Bangla label and its Bangla-digit value',
    (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('bn'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: SgSlider(
                  value: 5,
                  min: 1,
                  max: 10,
                  label: bn,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      final node = tester.getSemantics(find.bySemanticsLabel(bn));
      expect(bnRanges(node), isNotEmpty, reason: 'the label');
      final value = node.getSemanticsData().attributedValue;
      expect(value.string, isNot(contains('5')), reason: 'Bangla digits');
      expect(
        value.attributes.whereType<LocaleStringAttribute>().where(
          (tag) => tag.locale == SgScript.bnBD,
        ),
        isNotEmpty,
      );
      handle.dispose();
    },
  );

  group('#698 Material chrome sets its Bangla labels a role up', () {
    Future<void> pump(WidgetTester tester, Widget body, {Widget? bar}) =>
        tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: supportedLocales,
            home: Scaffold(body: body, bottomNavigationBar: bar),
          ),
        );

    /// The size [text]'s Bangla is drawn at, or its whole text's.
    double sizeOf(WidgetTester tester, String text) {
      final rich = tester.widget<RichText>(
        find
            .byWidgetPredicate(
              (widget) =>
                  widget is RichText && widget.text.toPlainText() == text,
            )
            .first,
      );
      final bangla = SgScript.hasBengali(text);
      double? found;
      void visit(InlineSpan span, double? inherited) {
        final size = span.style?.fontSize ?? inherited;
        if (span is! TextSpan) return;
        final own = span.text;
        if (found == null &&
            own != null &&
            (!bangla || SgScript.hasBengali(own))) {
          found = size;
        }
        for (final child in span.children ?? const <InlineSpan>[]) {
          visit(child, size);
        }
      }

      visit(rich.text, null);
      return found!;
    }

    testWidgets('a segment, and the Latin beside it as it was', (tester) async {
      await pump(
        tester,
        AdaptiveSegmented<int>(
          segments: const <int, String>{1: 'শব্দ', 2: 'Words'},
          value: 1,
          onChanged: (_) {},
        ),
      );
      expect(sizeOf(tester, 'শব্দ'), 15, reason: "the body's, a role up");
      expect(sizeOf(tester, 'Words'), 13, reason: "the label role's");
    });

    testWidgets('a tab', (tester) async {
      await pump(
        tester,
        AdaptiveTabBar<int>(
          tabs: const <int, String>{1: 'শব্দ', 2: 'Words'},
          value: 1,
          onChanged: (_) {},
        ),
      );
      expect(sizeOf(tester, 'শব্দ'), 15);
      expect(sizeOf(tester, 'Words'), 14, reason: "the artboard's 14");
    });

    testWidgets('a nav destination', (tester) async {
      AdaptiveNavBar bar(String first, String second) => AdaptiveNavBar(
        destinations: <AdaptiveNavDestination>[
          AdaptiveNavDestination(
            icon: Icons.today_outlined,
            selectedIcon: Icons.today,
            label: first,
          ),
          AdaptiveNavDestination(
            icon: Icons.school_outlined,
            selectedIcon: Icons.school,
            label: second,
          ),
        ],
        currentIndex: 0,
        onSelected: (_) {},
      );
      await pump(tester, const SizedBox(), bar: bar('আজ', 'শিখুন'));
      expect(sizeOf(tester, 'আজ'), 13, reason: "the label role's");
      expect(sizeOf(tester, 'শিখুন'), 13);

      await pump(tester, const SizedBox(), bar: bar('Today', 'Learn'));
      expect(sizeOf(tester, 'Today'), 12);

      // And nothing cut at 200 %: no golden draws the shell's bar.
      textAt(tester, 2);
      await pump(tester, const SizedBox(), bar: bar('অনুশীলন', 'অগ্রগতি'));
      expectNothingClipped(tester);
    });

    testWidgets("a dialog's actions", (tester) async {
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Adaptive.showConfirm(
              context: context,
              title: 'মুছবেন?',
              message: 'Sure?',
              confirmLabel: 'মুছুন',
              cancelLabel: 'Cancel',
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(sizeOf(tester, 'মুছুন'), 15);
      expect(sizeOf(tester, 'Cancel'), 13);
    });
  });
}
