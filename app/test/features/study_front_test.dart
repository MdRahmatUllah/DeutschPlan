import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/components/dp_speaker_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/features/study/study_front.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/services/tts/tts_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// T2 · StudyFront — #101.
void main() {
  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  Word word({
    String uid = 'rechnung',
    String? article = 'die',
    String german = 'Rechnung',
    String? forms = 'Rechnungen',
    String? pos = 'noun',
    String? pron = 'রেশনুং',
  }) => Word(
    uid: uid,
    sublevelCode: 'A2.1',
    levelCode: 'A2',
    seq: 1,
    seqInSublevel: 1,
    article: article,
    german: german,
    forms: forms,
    pos: pos,
    pronBn: pron,
    english: 'bill',
    searchKey: german.toLowerCase(),
    searchKeyAlt: german.toLowerCase(),
  );

  group('the caption', () {
    test('a noun: Nomen, its plural after it, the pronunciation', () {
      expect(
        frontCaption(word(), l10n, pron: true),
        'Nomen · die Rechnung, Rechnungen · /রেশনুং/',
      );
    });

    test('a verb: its forms stand on their own', () {
      expect(
        frontCaption(
          word(
            article: null,
            german: 'arbeiten',
            forms: 'arbeitet · hat gearbeitet',
            pos: 'verb',
            pron: null,
          ),
          l10n,
          pron: true,
        ),
        'Verb · arbeitet · hat gearbeitet',
      );
    });

    test('show_pron_bn off leaves the pronunciation out', () {
      expect(
        frontCaption(word(), l10n, pron: false),
        'Nomen · die Rechnung, Rechnungen',
      );
    });
  });

  group('the card', () {
    late AppDatabase db;
    late SettingsRepository settings;
    late _RecordingTts tts;

    Future<void> pump(
      WidgetTester tester, {
      Word? of,
      bool autoplay = false,
      bool voice = true,
      ThemeData? theme,
    }) async {
      await tester.runAsync(() async {
        db = AppDatabase.memory();
        settings = SettingsRepository(db);
        await settings.load();
        await settings.write(SettingKeys.autoplayHeadword, autoplay);
      });
      addTearDown(
        () => tester.runAsync(() async {
          await settings.dispose();
          await db.close();
        }),
      );
      tts = _RecordingTts(voice: voice);
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            settingsProvider.overrideWithValue(settings),
            systemTtsProvider.overrideWithValue(tts),
          ],
          child: MaterialApp(
            theme: theme ?? AppTheme.light(),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: supportedLocales,
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: StudyFrontCard(word: of ?? word()),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Color bar(WidgetTester tester) => tester
        .widget<ColoredBox>(
          find.descendant(
            of: find.byType(PositionedDirectional),
            matching: find.byType(ColoredBox),
          ),
        )
        .color;

    testWidgets('the gender bar is the article colour', (tester) async {
      await pump(tester);
      expect(bar(tester), DpPalette.light.die);
    });

    testWidgets('der and das take theirs, and no article is neutral', (
      tester,
    ) async {
      await pump(
        tester,
        of: word(article: 'der', german: 'Tisch'),
      );
      expect(bar(tester), DpPalette.light.der);

      await pump(
        tester,
        of: word(article: 'das', german: 'Haus'),
      );
      expect(bar(tester), DpPalette.light.das);

      await pump(
        tester,
        of: word(article: null, german: 'gehen', pos: 'verb'),
      );
      expect(bar(tester), DpSurfaceTokens.light.muted);
    });

    testWidgets('under glass the card takes the gender tint too', (
      tester,
    ) async {
      await pump(tester, theme: AppTheme.glass());
      final surface = tester.widget<DpSurface>(find.byType(DpSurface).first);
      expect(surface.selected, isFalse);
      expect(surface.kind, isNot(DpSurfaceKind.card));
      expect(bar(tester), DpPalette.light.die);
    });

    testWidgets('FR-T2-09 a long-press on the headword copies it', (
      tester,
    ) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(
              (call.arguments as Map<Object?, Object?>)['text']! as String,
            );
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pump(tester);

      await tester.longPress(find.text('die Rechnung', findRichText: true));
      await tester.pump();

      expect(copied, <String>['die Rechnung']);
      expect(find.text(l10n.studyCopied('die Rechnung')), findsOneWidget);
    });

    testWidgets('the speaker plays the word with its article', (tester) async {
      await pump(tester);
      await tester.tap(find.byType(DpSpeakerButton));
      await tester.pump();
      expect(tts.said, <(String, double)>[('die Rechnung', 1)]);
    });

    testWidgets('FR-T2-09 a long-press on the speaker plays it at 0.75×', (
      tester,
    ) async {
      await pump(tester);
      await tester.longPress(find.byType(DpSpeakerButton));
      await tester.pump();
      expect(tts.said, <(String, double)>[('die Rechnung', 0.75)]);
    });

    testWidgets('and at the chosen speech speed', (tester) async {
      await pump(tester);
      await tester.runAsync(() => settings.write(SettingKeys.ttsSpeed, 1.25));
      await tester.longPress(find.byType(DpSpeakerButton));
      await tester.pump();
      expect(tts.said.single.$2, closeTo(1.25 * 0.75, 1e-9));
    });

    testWidgets('autoplay_headword on: the word plays as the card appears', (
      tester,
    ) async {
      await pump(tester, autoplay: true);
      await tester.pump();
      expect(tts.said, <(String, double)>[('die Rechnung', 1)]);
    });

    testWidgets('off: it waits to be asked', (tester) async {
      await pump(tester);
      await tester.pump();
      expect(tts.said, isEmpty);
    });

    testWidgets('no German voice: the speaker is slashed and says why', (
      tester,
    ) async {
      await pump(tester, voice: false);
      await tester.tap(find.byType(DpSpeakerButton));
      await tester.pump();

      expect(
        tester.widget<DpSpeakerButton>(find.byType(DpSpeakerButton)).state,
        DpSpeakerState.unavailable,
      );
      expect(find.text(l10n.studyNoVoice), findsOneWidget);

      // A tap on the slashed speaker explains again and asks nothing more
      // of the engine.
      await tester.pumpAndSettle();
      await tester.pump(DpToast.duration);
      await tester.pumpAndSettle();
      expect(find.text(l10n.studyNoVoice), findsNothing);
      await tester.tap(find.byType(DpSpeakerButton));
      await tester.pump();
      expect(find.text(l10n.studyNoVoice), findsOneWidget);
      expect(tts.said, hasLength(1));
    });

    testWidgets('and autoplay says so once, not on every card', (tester) async {
      await pump(tester, autoplay: true, voice: false);
      await tester.pump();
      expect(find.text(l10n.studyNoVoice), findsOneWidget);

      await tester.pumpAndSettle();
      await tester.pump(DpToast.duration);
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            settingsProvider.overrideWithValue(settings),
            systemTtsProvider.overrideWithValue(tts),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: supportedLocales,
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: StudyFrontCard(
                  word: word(uid: 'tisch', article: 'der', german: 'Tisch'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text(l10n.studyNoVoice), findsNothing);
      expect(tts.said, hasLength(1));
    });
  });
}

class _RecordingTts implements TtsEngine {
  _RecordingTts({this.voice = true});

  final bool voice;
  final List<(String, double)> said = <(String, double)>[];

  @override
  Future<bool> speak(String text, {double rate = 1}) async {
    said.add((text, rate));
    return voice;
  }

  @override
  Future<void> stop() async {}
}
