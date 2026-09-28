import 'dart:io';

import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/data/repositories/course_text.dart';
import 'package:sogda/domain/grammar_item_generator.dart';
import 'package:sogda/features/learn/grammar_topic_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../db/content_fixture.dart';

/// #330: what the grammar generator checks its forms against, as the app
/// reads it from content.db.
void main() {
  late Directory directory;
  late AppDatabase db;

  setUp(() async {
    directory = tempDir('sogda_course');
    final content = ContentFixture.write('${directory.path}/content.db').file;
    db = AppDatabase.memory();
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('FR-L15-01 #330 the words, their forms and examples, and the examples '
      'to borrow', () async {
    final course = await loadCourseText(db);
    expect(course.knows('Haus'), isTrue, reason: 'a word');
    expect(course.knows('sehe'), isTrue, reason: 'a word of an example');
    expect(course.knows('Hauses'), isFalse);
    expect(course.sentencesWith('Haus'), <({String german, String english})>[
      (german: 'Das Haus ist groß.', english: 'The house is big.'),
      (german: 'Ich sehe das Haus.', english: ''),
    ]);
  });

  test('FR-L15-01 #330 read once for the database', () async {
    expect(
      identical(await loadCourseText(db), await loadCourseText(db)),
      isTrue,
    );
  });

  test(
    'FR-L15-01 #386 a course that cannot be read practises without it',
    () async {
      // No content attached: no words table to read.
      final bare = AppDatabase.memory();
      addTearDown(bare.close);
      final container = ProviderContainer(
        overrides: <Override>[appDatabaseProvider.overrideWithValue(bare)],
      );
      addTearDown(container.dispose);
      expect(
        identical(
          await container.read(grammarCourseProvider.future),
          CourseText.none,
        ),
        isTrue,
      );
    },
  );
}
