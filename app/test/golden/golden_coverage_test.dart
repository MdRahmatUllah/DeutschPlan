import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #168 · every screen in `docs/04-screens/` has its golden matrix: light,
/// dark and glass on the phone and the tablet frame (`testing.md`). A screen
/// added to the docs without goldens fails here, and so does a golden file
/// whose every case narrows the matrix.
void main() {
  // Each screen's doc, and the golden files that draw it.
  const goldens = <String, List<String>>{
    'about-licences': <String>['about'],
    'add-word': <String>['add_word'],
    'backlog': <String>['backlog', 'backlog_empty'],
    'categories': <String>['categories', 'category_words'],
    'compare': <String>['compare'],
    'day-complete': <String>['day_complete'],
    'exam-hub': <String>['step_detail'],
    'exam-results': <String>['exam_results', 'exam_review'],
    'exam-runner': <String>['exam_runner', 'exam_intro'],
    'exam-writing-speaking': <String>['exam_writing', 'exam_speaking'],
    'export-import': <String>['export_import'],
    'grammar-library': <String>['grammar_library'],
    'grammar-practice': <String>['grammar_practice'],
    'grammar-topic': <String>['grammar_topic'],
    'learn': <String>['learn'],
    'me': <String>['me'],
    'model-manager': <String>['model_manager'],
    'onboarding': <String>[
      'onboarding_welcome',
      'onboarding_meaning',
      'onboarding_start',
      'onboarding_pace',
      'onboarding_voice',
    ],
    'placement': <String>['placement', 'placement_result'],
    'practice-sentences': <String>['sentences'],
    'progress': <String>['progress'],
    'quiz': <String>['quiz_setup', 'quiz_runner', 'quiz_result'],
    'reminder-days': <String>['reminder_days'],
    'reset': <String>['reset'],
    'search': <String>['search'],
    'session-summary': <String>['study_summary'],
    'settings': <String>['settings'],
    'splash': <String>['splash'],
    'step-detail': <String>['step_detail'],
    'study-session': <String>[
      'study_front',
      'study_back',
      'study_new',
      'study_swipe',
    ],
    'study-session-states': <String>['study_cloze'],
    'today': <String>['today', 'today_cards', 'today_done', 'today_rest'],
    'word-detail': <String>['word_detail'],
  };
  // Screens no Flutter golden can draw, and why.
  const native = <String, String>{
    // Glance on Android and WidgetKit on iOS draw it, not Flutter; its data
    // is `widget_snapshot_test`'s and its views `widget_native_test`'s.
    'widget': 'the home-screen widget is drawn natively',
  };

  final screens = <String>[
    for (final doc in Directory('../docs/04-screens').listSync())
      if (doc is File &&
          doc.path.endsWith('.md') &&
          !doc.uri.pathSegments.last.startsWith('_'))
        doc.uri.pathSegments.last.replaceAll('.md', ''),
  ]..sort();

  test('#168 every screen in docs/04-screens has goldens, or says why not', () {
    expect(screens, isNotEmpty);
    expect(
      <String>[
        for (final screen in screens)
          if (!goldens.containsKey(screen) && !native.containsKey(screen))
            screen,
      ],
      isEmpty,
      reason: 'a screen doc with no golden file named here',
    );
    expect(
      <String>[
        for (final screen in <String>[...goldens.keys, ...native.keys])
          if (!screens.contains(screen)) screen,
      ],
      isEmpty,
      reason: 'named here, but no longer in docs/04-screens',
    );
  });

  test('#168 each of those golden files draws its screen in the full '
      'matrix at least once: every mode, both devices', () {
    final narrow = <String>[];
    for (final file in <String>{for (final names in goldens.values) ...names}) {
      final source = File('test/golden/${file}_golden_test.dart');
      expect(source.existsSync(), isTrue, reason: '$file has no golden test');
      if (!_hasFullCase(source.readAsStringSync())) narrow.add(file);
    }
    expect(narrow, isEmpty, reason: 'only narrowed cases');
  });
}

/// Whether a `goldenTest(` call in [source] takes the default matrix: no
/// `modes:` or `devices:` of its own, or a helper's defaults passed through.
bool _hasFullCase(String source) {
  for (final call in RegExp(r'goldenTest\(').allMatches(source)) {
    var depth = 1;
    var end = call.end;
    while (depth > 0 && end < source.length) {
      final char = source[end];
      if (char == '(') depth++;
      if (char == ')') depth--;
      end++;
    }
    final arguments = source.substring(call.end, end);
    final narrowed = RegExp(r'\b(modes|devices):\s*(?!devices\b)')
        .hasMatch(arguments);
    if (!narrowed) return true;
    // A helper that passes its own `devices` through, as the voice page's
    // does: full when the helper's default is every device.
    if (RegExp(r'\bdevices:\s*devices\b').hasMatch(arguments) &&
        RegExp(r'List<GoldenDevice>\s+devices\s*=\s*GoldenDevice\.values')
            .hasMatch(source)) {
      return true;
    }
  }
  return false;
}
