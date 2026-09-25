import 'dart:io';

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/features/me/about_screen.dart';
import 'package:deutschplan/features/me/licences_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

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
  }) async {
    tester.view
      ..physicalSize = const Size(1200, 4000)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...aboutStub(dated: dated),
          openWebProvider.overrideWithValue((page) async {
            opened.add(page);
            return true;
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

  test("FR-M8-01 the models' and fonts' licences are bundled whole", () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    for (final licence in <Licence>[...modelLicences, ...fontLicences]) {
      final asset = licence.asset!;
      expect(
        await container.read(licenceTextProvider(asset).future),
        File(asset).readAsStringSync(),
        reason: licence.name,
      );
    }
    expect(
      File('assets/licences/HY-MT1.5-Tencent-HY.txt').readAsStringSync(),
      startsWith('TENCENT HY COMMUNITY LICENSE AGREEMENT'),
    );
    // #172: the SDK whose text front end supertonic_text.dart ports.
    expect(
      File('assets/licences/Supertonic-SDK-MIT.txt').readAsStringSync(),
      startsWith('MIT License'),
    );
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
      final asset = licence.asset!;
      await tester.tap(find.text(licence.name));
      await tester.pumpAndSettle();
      final full = File(asset).readAsStringSync();
      expect(find.text(full), findsOneWidget, reason: licence.name);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }
  });

  testWidgets("M8's packages, each with its licence's name", (tester) async {
    await pump(tester, at: '/me/about/licences');
    for (final package in artboardPackages) {
      expect(find.text(package.name), findsOneWidget);
    }
    expect(find.text('BSD-2-Clause'), findsOneWidget);
    // The three MIT packages, and the Supertonic SDK above them (#172).
    expect(find.text('MIT'), findsNWidgets(4));
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
