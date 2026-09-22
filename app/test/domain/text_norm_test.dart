@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:deutschplan/domain/text_norm.dart';
import 'package:flutter_test/flutter_test.dart';

/// PIPE-04, from the Dart side.
///
/// `tools/test_vectors.json` is loaded rather than restated, because the point
/// of these is that *both* implementations reproduce the same file. A copy
/// here would only prove the copy was made.
///
/// A mismatch is invisible on Search: the word is in content.db under the key
/// the Python pipeline wrote, the learner types something that looks right,
/// and nothing comes back.
void main() {
  final vectors =
      (jsonDecode(File('../tools/test_vectors.json').readAsStringSync())
              as Map<String, dynamic>)['vectors']
          as List<dynamic>;

  test('the vector file was found and is populated', () {
    // Every assertion below iterates it, so an empty or misplaced file would
    // make the whole suite pass by having nothing to check.
    expect(vectors, hasLength(greaterThanOrEqualTo(25)));
    expect(
      vectors.map((v) => (v as Map<String, dynamic>)['input']),
      containsAll(<String>['Tür', 'die Bank', 'groß', 'মেয়ে']),
    );
  });

  group('matches the Python pipeline on every vector', () {
    for (final entry in vectors.cast<Map<String, dynamic>>()) {
      final input = entry['input'] as String;
      test('${entry['why']} — ${jsonEncode(input)}', () {
        expect(
          searchKey(input),
          entry['search_key'],
          reason: 'searchKey disagrees with tools/pipeline_steps.py',
        );
        expect(
          searchKeyAlt(input),
          entry['search_key_alt'],
          reason: 'searchKeyAlt disagrees with tools/pipeline_steps.py',
        );
      });
    }
  });

  group('the rules, stated once here so a vector change is visible', () {
    test('umlauts expand the German way, and fold in the alt key', () {
      expect(searchKey('Tür'), 'tuer');
      expect(searchKeyAlt('Tür'), 'tur');
    });

    test('ß is ss in both — nobody types anything else', () {
      expect(searchKey('groß'), 'gross');
      expect(searchKeyAlt('groß'), 'gross');
      expect(searchKey('Straße'), searchKey('STRASSE'));
    });

    test('a leading article goes, a word that starts like one stays', () {
      expect(searchKey('der Tisch'), 'tisch');
      expect(searchKey('Diebstahl'), 'diebstahl');
      expect(searchKey('der'), 'der');
    });

    test('Bangla comes back unchanged', () {
      // search.md matches `bangla = raw`. Bangla vowel signs are combining
      // marks, which a diacritic strip that did not check the script would eat.
      for (final text in <String>['মেয়ে', 'বই', 'ঘর্ষণ']) {
        expect(searchKey(text), text);
        expect(searchKeyAlt(text), text);
      }
    });

    test('the two umlaut tables cover the same letters', () {
      expect(umlautExpansions.keys.toSet(), umlautFolds.keys.toSet());
    });
  });
}
