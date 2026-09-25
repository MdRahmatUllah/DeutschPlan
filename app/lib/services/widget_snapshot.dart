import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/word_repository.dart'
    show WordStatus;
import 'package:deutschplan/domain/plan_engine.dart' show addDays, planDate;
import 'package:deutschplan/domain/word_of_day.dart';
import 'package:deutschplan/features/today/today_providers.dart';
import 'package:deutschplan/features/today/today_view.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'widget_snapshot.g.dart';

/// The widget's Wort des Tages: the word, and its meaning in the learner's
/// meaning language.
typedef WidgetWord = ({
  String uid,
  String? article,
  String german,
  String meaning,
});

/// FR-X1-01: what the home-screen widget draws, as `notifications-widget.md`
/// names it, plus the day it is for and, once the day is done, tomorrow's
/// preview for the Lime-check state.
Map<String, Object?> widgetSnapshot(TodayView today, WidgetWord? word) {
  final tomorrow = today.tomorrow;
  return <String, Object?>{
    'date': today.date,
    'step': today.step,
    'remaining': today.left,
    'total': today.total,
    'minutes': today.estimateMinutes,
    'done': today.isDone,
    'wordOfDay': word == null
        ? null
        : <String, Object?>{
            'uid': word.uid,
            'article': word.article,
            'german': word.german,
            'meaning': word.meaning,
          },
    'tomorrow': tomorrow == null
        ? null
        : <String, Object?>{
            'revise': tomorrow.revise,
            'newWords': tomorrow.newWords,
            'minutes': (tomorrow.estimate.inSeconds / 60).ceil(),
          },
  };
}

/// FR-X1-03: a learned word due within three days, seeded by the date; never
/// a To-do word, nor a suspended one. Follows the reviews: a word revised
/// today leaves the candidates. And the meaning language: M3's change of it
/// reaches the widget at once.
@riverpod
Stream<WidgetWord?> widgetWord(Ref ref) {
  final language = ref.watch(languagesProvider.select((l) => l.meaning));
  final today = ref.watch(todayProvider);
  return ref.watch(wordRepositoryProvider).watchDue(addDays(today, 3)).map((
    due,
  ) {
    final learned = {
      for (final word in due)
        if (word.status != WordStatus.todo &&
            word.status != WordStatus.suspended)
          word.word.uid: word.word,
    };
    final uid = wordOfDay(learned.keys.toList(), today);
    if (uid == null) return null;
    final word = learned[uid]!;
    final bangla = word.bangla;
    return (
      uid: uid,
      article: word.article,
      german: word.german,
      meaning: switch (language) {
        MeaningLanguage.english => word.english,
        MeaningLanguage.bangla => bangla ?? word.english,
        MeaningLanguage.both =>
          bangla == null ? word.english : '${word.english} · $bangla',
      },
    );
  });
}

/// The snapshot as the JSON the widget reads, again whenever today's plan or
/// the word moves.
@riverpod
Future<String> widgetSnapshotJson(Ref ref) async {
  final today = await ref.watch(todayViewProvider.future);
  final word = await ref.watch(widgetWordProvider.future);
  return jsonEncode(widgetSnapshot(today, word));
}

/// Where the snapshot goes: an interface so the writer can be tested without
/// the native widgets (#159's third criterion).
abstract interface class WidgetStore {
  Future<void> save(String snapshot);
}

/// [WidgetStore] on `home_widget`: SharedPreferences on Android, the App
/// Group's UserDefaults on iOS, under [key].
class HomeWidgetStore implements WidgetStore {
  const HomeWidgetStore();

  /// The value the native widgets read (#160, #161).
  static const String key = 'widget_snapshot';

  /// release.md's App Group, shared with the widget extension.
  static const String appGroup = 'group.app.deutschplan';

  // ponytail: saves only. #160 and #161 add `HomeWidget.updateWidget` with
  // their providers' names, once there is a widget to redraw.
  @override
  Future<void> save(String snapshot) async {
    if (Platform.isIOS) await HomeWidget.setAppGroupId(appGroup);
    await HomeWidget.saveWidgetData<String>(key, snapshot);
  }
}

/// Writes the snapshot from [container]'s database: a background task's
/// widget_refresh and plan_pregenerate. A failure costs the widget one
/// refresh, never the task it runs in.
Future<void> refreshWidget(
  ProviderContainer container,
  WidgetStore store,
) async {
  final snapshot = container.listen(
    widgetSnapshotJsonProvider.future,
    (_, _) {},
  );
  try {
    await store.save(await snapshot.read());
  } on Object catch (error) {
    debugPrint('widget: $error');
  } finally {
    snapshot.close();
  }
}

/// FR-X1-01's "after every session", in the app: the snapshot saved now and
/// whenever it changes, which a finished session always does.
ProviderSubscription<AsyncValue<String>> followWidget(
  ProviderContainer container,
  WidgetStore store,
) {
  String? saved;
  return container.listen(widgetSnapshotJsonProvider, (_, next) {
    final snapshot = next.value;
    if (snapshot == null || snapshot == saved) return;
    // An app left open across midnight holds yesterday's date, and would
    // write it over the 00:05 snapshot: read the date again, and save what
    // follows from it instead.
    final today = planDate(container.read(clockProvider)());
    if ((jsonDecode(snapshot) as Map<String, Object?>)['date'] != today) {
      // After this rebuild, not inside it.
      scheduleMicrotask(() => container.invalidate(todayProvider));
      return;
    }
    saved = snapshot;
    unawaited(
      store.save(snapshot).catchError((Object error) {
        debugPrint('widget: $error');
      }),
    );
  });
}
