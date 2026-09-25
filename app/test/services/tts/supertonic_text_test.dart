import 'dart:convert';
import 'dart:io';

import 'package:deutschplan/services/tts/nfkd_latin.dart';
import 'package:deutschplan/services/tts/supertonic_text.dart';
import 'package:flutter_test/flutter_test.dart';

/// Supertonic 3's text front end (#152), against vectors from the reference
/// SDK: supertonic 1.3.1's `UnicodeProcessor` over the real
/// `unicode_indexer.json`, with the app's five extra replacements and
/// unindexed characters dropped. The fixture keeps only the index entries
/// these cases use.
void main() {
  final vectors = jsonDecode(
    File('test/services/tts/supertonic_text_vectors.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final indexer = List<int>.filled(0x10000, -1);
  (vectors['indexer']! as Map<String, Object?>).forEach(
    (unit, index) => indexer[int.parse(unit)] = index! as int,
  );
  final text = SupertonicText(indexer);
  final cases = (vectors['cases']! as List<Object?>)
      .cast<Map<String, Object?>>();

  test('#152 each text is prepared as the SDK prepares it, tagged <de>', () {
    for (final vector in cases) {
      expect(
        SupertonicText.prepare(vector['text']! as String),
        vector['prepared'],
        reason: vector['text']! as String,
      );
    }
  });

  test('#152 and gives the model the SDK\'s ids', () {
    for (final vector in cases) {
      expect(
        text.ids(vector['text']! as String),
        (vector['ids']! as List<Object?>).cast<int>(),
        reason: vector['text']! as String,
      );
    }
  });

  test('#152 an umlaut reaches the model as its letter and the combining '
      'diaeresis, which is all the indexer knows', () {
    expect(nfkdLatin['ä'.codeUnitAt(0)], 'ä');
    expect(nfkdLatin['Ü'.codeUnitAt(0)], 'Ü');
    expect(nfkdLatin.containsKey('ß'.codeUnitAt(0)), isFalse);
    expect(SupertonicText.prepare('Tür'), '<de>Tür.</de>');
  });

  test('#152 German quotes and ↔ become what the indexer has, and a '
      'character it still lacks is dropped rather than sent as -1', () {
    expect(SupertonicText.prepare('„Ja“'), '<de>"Ja"</de>');
    expect(SupertonicText.prepare('a ↔ b'), '<de>a b.</de>');
    final taste = cases.firstWhere((c) => c['text'] == 'Taste ⌘ drücken');
    expect(taste['prepared'], contains('⌘'));
    expect(text.ids('Taste ⌘ drücken'), isNot(contains(-1)));
    expect(
      text.ids('Taste ⌘ drücken'),
      hasLength((taste['prepared']! as String).length - 1),
    );
  });

  test('#152 emoji go, as the SDK removes them', () {
    expect(SupertonicText.prepare('Hallo 😀'), '<de>Hallo.</de>');
    expect(SupertonicText.prepare('Sonne ☀'), '<de>Sonne.</de>');
  });
}
