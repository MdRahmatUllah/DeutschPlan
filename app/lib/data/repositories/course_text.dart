import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/domain/grammar_item_generator.dart';

/// #330: what the grammar generator checks a made-up form against and takes
/// *Pick the form*'s sentence from — every word, its forms and examples, and
/// the grammar examples. Read once per database: some 17,000 rows, which
/// L4, L15 and the mocks all ask for.
// ponytail: kept while the database is open, so a course update reaches it
// on the next start; key it by the content version if that must be sooner.
Future<CourseText> loadCourseText(AppDatabase db) async {
  final cached = _loaded[db];
  if (cached != null) return cached;
  final loading = _load(db);
  _loaded[db] = loading;
  try {
    return await loading;
  } on Object {
    // A read that failed is tried again, not remembered.
    _loaded[db] = null;
    rethrow;
  }
}

final Expando<Future<CourseText>> _loaded = Expando<Future<CourseText>>();

Future<CourseText> _load(AppDatabase db) async {
  final words = await db.customSelect('SELECT german, forms FROM words').get();
  final grammar = await db
      .customSelect('SELECT example_de FROM grammar_topics')
      .get();
  final examples = await db
      .customSelect(
        'SELECT german, english FROM word_examples ORDER BY word_uid, ord',
      )
      .get();
  return CourseText(
    texts: <String>[
      for (final row in words)
        '${row.read<String>('german')} ${row.read<String?>('forms') ?? ''}',
      for (final row in grammar) row.read<String?>('example_de') ?? '',
    ],
    sentences: <({String german, String english})>[
      for (final row in examples)
        (
          german: row.read<String>('german'),
          english: row.read<String?>('english') ?? '',
        ),
    ],
  );
}
