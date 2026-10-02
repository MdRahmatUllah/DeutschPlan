import 'dart:io';

import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/app_theme.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/features/me/about_screen.dart';
import 'package:sogda/features/me/licences_screen.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/main.dart'
    show appLocalizationsDelegates, supportedLocales;

import 'about_fixtures.dart';

/// M9 · About & privacy and M8 · Licences — #150.
void main() {
  late AppLocalizations l10n;
  late List<Uri> opened;
  late String went;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  setUp(() {
    opened = <Uri>[];
    went = '';
  });

  Future<void> pump(
    WidgetTester tester, {
    String at = '/me/about',
    List<Override> more = const <Override>[],
    bool dated = true,
    bool facts = true,
    bool browser = true,
  }) async {
    tester.view
      ..physicalSize = const Size(1200, 4000)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...aboutStub(dated: dated, facts: facts),
          openWebProvider.overrideWithValue((page) async {
            opened.add(page);
            return browser;
          }),
          ...more,
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          routerConfig: GoRouter(
            initialLocation: at,
            routes: <RouteBase>[
              GoRoute(
                path: '/me/about',
                builder: (_, _) => const AboutScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'licences',
                    builder: (_, state) {
                      went = state.uri.toString();
                      return const LicencesScreen();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('FR-M9-01 the version and build, the course version and day, '
      'and its size', (tester) async {
    await pump(tester);
    expect(
      find.text(l10n.aboutVersion('1.0.0', '41', '2026.09', '21 Sep 2026')),
      findsOneWidget,
    );
    expect(
      find.text(l10n.aboutContentCounts(5594, 182, 11188)),
      findsOneWidget,
    );
    expect(
      find.text('5,594 words · 182 grammar topics · 11,188 sentences'),
      findsOneWidget,
      reason: 'the counts are grouped',
    );
    expect(find.text(l10n.aboutPrivacyText), findsOneWidget);
  });

  testWidgets('FR-M9-01 a course that does not say when it was built: no '
      'date, and no dot left over', (tester) async {
    await pump(tester, dated: false);
    expect(
      find.text(l10n.aboutVersionUndated('1.0.0', '41', '2026.09')),
      findsOneWidget,
    );
  });

  testWidgets("#692 ME-13 the course's facts unread: the app's own version "
      'still shows', (tester) async {
    await pump(tester, facts: false);
    expect(find.text(l10n.aboutVersionAppOnly('1.0.0', '41')), findsOneWidget);
  });

  testWidgets('#692 ME-13 Contact on a phone with no browser says so', (
    tester,
  ) async {
    await pump(tester, browser: false);
    await tester.tap(find.text(l10n.aboutContact));
    await tester.pump();
    expect(find.text(l10n.webOpenFailed), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets("#692 ME-13 a link the phone can't open is false, not a throw", (
    tester,
  ) async {
    // No url_launcher plugin in a test: launchUrl throws, as it does on a
    // phone with no browser.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final opened = await tester.runAsync(
      () => container.read(openWebProvider)(Uri.https('example.com')),
    );
    expect(opened, isFalse);
  });

  test('FR-M9-01 the course version as About shows it', () {
    expect(contentRelease('202609251045'), '2026.09');
    expect(contentRelease('2026'), '2026', reason: 'too short to cut');
  });

  testWidgets('M9 the licences row opens M8, and Contact the project page', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text(l10n.aboutContact));
    await tester.pumpAndSettle();
    // Where a card's report goes (#100): the app has no address of its own.
    expect(opened.map((uri) => uri.toString()), <String>[
      'https://github.com/MdRahmatUllah/DeutschPlan/issues/new',
    ]);

    await tester.tap(find.text(l10n.aboutLicences));
    await tester.pumpAndSettle();
    expect(went, '/me/about/licences');
    expect(find.text(l10n.licencesTitle), findsOneWidget);
  });

  test("FR-M8-01 #610 the models', fonts' and native libraries' licences are "
      'bundled whole', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    for (final licence in <Licence>[
      ...modelLicences,
      ...fontLicences,
      ...nativeLicences,
    ]) {
      // ML Kit's terms are web pages, written in the app with their links
      // (#1229); the rest are bundled texts.
      final asset = licence.asset;
      if (asset == null) {
        expect(licence.text, contains('https://'), reason: licence.name);
        continue;
      }
      expect(
        await container.read(licenceTextProvider(asset).future),
        File(asset).readAsStringSync(),
        reason: licence.name,
      );
    }
    expect(
      File('assets/licences/Hy-MT2-Apache-2.0.txt').readAsStringSync(),
      contains(
        'Hy-MT2-1.8B-GGUF is licensed under the Apache License, Version 2.0.',
      ),
    );
    // #610: ONNX Runtime ships in every APK (libonnxruntime.so).
    expect(
      File(nativeLicences.first.asset!).readAsStringSync(),
      contains('Copyright (c) Microsoft Corporation'),
      reason: nativeLicences.first.name,
    );
    expect(
      File('assets/licences/AndroidX-Apache-2.0.txt').readAsStringSync(),
      contains('Apache License'),
    );
    // #848: desugar_jdk_libs is compiled into the release DEX.
    expect(
      File(nativeLicences.last.asset!).readAsStringSync(),
      allOf(
        startsWith('The GNU General Public License (GPL)'),
        contains('"CLASSPATH" EXCEPTION TO THE GPL'),
      ),
      reason: nativeLicences.last.name,
    );
    // #172: the SDK whose text front end supertonic_text.dart ports.
    expect(
      File('assets/licences/Supertonic-SDK-MIT.txt').readAsStringSync(),
      startsWith('MIT License'),
    );
  });

  testWidgets('FR-M8-01 #610 the native libraries have their own section', (
    tester,
  ) async {
    await pump(tester, at: '/me/about/licences');
    await tester.scrollUntilVisible(
      find.text(nativeLicences.last.name),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(l10n.licencesNative.toUpperCase()), findsOneWidget);
    for (final licence in nativeLicences) {
      expect(find.text(licence.name), findsOneWidget, reason: licence.name);
    }
  });

  testWidgets('FR-M8-01 the models and fonts, each licence shown in full', (
    tester,
  ) async {
    await pump(
      tester,
      at: '/me/about/licences',
      // The bundle is read for real in the test above; here, the text.
      more: <Override>[
        licenceTextProvider.overrideWith(
          (ref, asset) async => File(asset).readAsStringSync(),
        ),
      ],
    );
    for (final licence in <Licence>[...modelLicences, ...fontLicences]) {
      await tester.tap(find.text(licence.name));
      await tester.pumpAndSettle();
      await _expectWhole(tester, licence);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('FR-M8-01 #849 a long licence is built as it scrolls, and '
      'still shows its first and last lines', (tester) async {
    await pump(
      tester,
      at: '/me/about/licences',
      more: <Override>[
        licenceTextProvider.overrideWith(
          (ref, asset) async => File(asset).readAsStringSync(),
        ),
      ],
    );
    // A short licence still hugs its text: MIT's 21 lines, in a sheet that
    // may grow to 1,700 px here.
    await tester.tap(find.text('Supertonic SDK'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(ListView).last).height, lessThan(800));
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    final notices = nativeLicences.singleWhere(
      (licence) => licence.asset?.endsWith('ThirdPartyNotices.txt') ?? false,
    );
    await tester.scrollUntilVisible(
      find.text(notices.name),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text(notices.name));
    await tester.pumpAndSettle();

    // 327 KB of text, and only a screenful of it laid out: what a frame
    // costs no longer grows with the licence.
    final lines = _lines(notices);
    expect(lines.length, greaterThan(6000));
    final laidOut = find
        .descendant(
          of: find.byType(ListView).last,
          matching: find.byType(SgText),
        )
        .evaluate()
        .map((element) => (element.widget as SgText).data.length)
        .fold(0, (sum, length) => sum + length);
    expect(laidOut, inExclusiveRange(0, 20000));
    await _expectWhole(tester, notices);
  });

  testWidgets("M8's packages, each with its licence's name", (tester) async {
    await pump(tester, at: '/me/about/licences');
    for (final package in artboardPackages) {
      expect(find.text(package.name), findsOneWidget);
    }
    expect(find.text('BSD-2-Clause'), findsOneWidget);
    // The three MIT packages, and above them the Supertonic SDK (#172) and
    // ONNX Runtime (#610).
    expect(find.text('MIT'), findsNWidgets(5));
  });

  test('M8 the packages come from Flutter\'s licence registry', () async {
    LicenseRegistry.addLicense(
      () => Stream<LicenseEntryWithLineBreaks>.fromIterable(
        <LicenseEntryWithLineBreaks>[
          LicenseEntryWithLineBreaks(<String>['zeta_pkg'], mit),
          LicenseEntryWithLineBreaks(<String>['OpenSSL'], 'Apache License'),
          LicenseEntryWithLineBreaks(<String>['abseil'], 'Apache License'),
        ],
      ),
    );
    addTearDown(LicenseRegistry.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final packages = await container.read(packageLicencesProvider.future);
    final zeta = packages.singleWhere((licence) => licence.name == 'zeta_pkg');
    expect(zeta.kind, 'MIT');
    expect(zeta.text, contains('free of charge'));
    expect(packages.map((licence) => licence.name), <String>[
      'abseil',
      'OpenSSL',
      'zeta_pkg',
    ], reason: 'in name order, whatever the case');
  });

  test('M8 a licence named from its text', () {
    expect(licenceKind(mit), 'MIT');
    expect(licenceKind('Apache License\nVersion 2.0'), 'Apache-2.0');
    expect(
      licenceKind(
        'Redistribution and use in source and binary forms … Neither the name',
      ),
      'BSD-3-Clause',
    );
    expect(
      licenceKind('Redistribution and use in source and binary forms …'),
      'BSD-2-Clause',
    );
    expect(licenceKind('Mozilla Public License Version 2.0'), 'MPL-2.0');
    expect(licenceKind('Some other terms'), isNull);
  });
}

/// [licence]'s bundled text, a line each, as the sheet lays it out.
List<String> _lines(Licence licence) =>
    File(licence.asset!)
        .readAsStringSync()
        .replaceAll('\r\n', '\n')
        .split('\n');

/// FR-M8-01: the open sheet shows [licence]'s text in full: its first line,
/// and its last once scrolled to.
Future<void> _expectWhole(WidgetTester tester, Licence licence) async {
  final lines = _lines(licence).where((line) => line.trim().isNotEmpty);
  final sheet = find.byType(ListView).last;
  expect(find.text(lines.first), findsWidgets, reason: licence.name);
  await tester.scrollUntilVisible(
    find.text(lines.last),
    3000,
    scrollable: find.descendant(of: sheet, matching: find.byType(Scrollable)),
  );
  expect(find.text(lines.last), findsWidgets, reason: licence.name);
}
