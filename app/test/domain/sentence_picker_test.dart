import 'package:deutschplan/domain/plan_engine.dart';
import 'package:deutschplan/domain/sentence_picker.dart';
import 'package:flutter_test/flutter_test.dart';

/// The practice sentence picker — #80, `docs/03-domain/sentences.md`.
void main() {
  SentenceCandidate s(String uid, int ord, String german) =>
      SentenceCandidate(wordUid: uid, ord: ord, german: german);

  group('coverage', () {
    const learned = <String>{'wohnung', 'gross', 'miete', 'zahlen'};

    test('is the share of tokens longer than two letters that are learned', () {
      // "Die", "ist" are three letters and count; "zu" does not.
      expect(coverage('Die Wohnung ist zu groß.', learned), 2 / 4);
    });

    test('counts a token that starts with a learned key: a stem match', () {
      expect(coverage('Wohnungen zahlen', learned), 1.0);
    });

    test('reads umlauts and ß the way the search keys are written', () {
      expect(coverage('groß', learned), 1.0, reason: 'groß → gross');
    });

    test('stays quick with a whole course learned', () {
      // The stem match runs for every token of every sampled sentence, on the
      // first open of the day. Scanning the vocabulary per token took seconds
      // at this size; a prefix lookup takes milliseconds.
      final vocabulary = <String>{for (var i = 0; i < 50000; i++) 'wort$i'};
      final sentences = <SentenceCandidate>[
        for (var i = 0; i < 400; i++)
          s('w$i', 1, 'Das große Haus hat einen schönen Garten mit Bäumen.'),
      ];
      final clock = Stopwatch()..start();
      pickSentences(sentences, learned: vocabulary, count: 3, seed: 1);
      expect(clock.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('an empty sentence covers nothing', () {
      expect(coverage('Ja, zu!', learned), 0);
    });
  });

  group('pickSentences', () {
    const learned = <String>{'haus', 'gross', 'garten', 'hat'};
    final candidates = <SentenceCandidate>[
      s('haus', 1, 'Das Haus ist groß.'), // haus, gross: 2 / 4
      s('haus', 2, 'Das Haus hat einen Garten.'), // haus, hat, garten: 3 / 5
      s('tuer', 1, 'Die Tür ist offen.'), // 0 / 4
      s('garten', 1, 'Der Garten ist groß.'), // garten, gross: 2 / 4
    ];

    test('highest coverage first, one sentence per headword', () {
      final picked = pickSentences(
        candidates,
        learned: learned,
        count: 3,
        seed: 1,
      );
      expect(picked.map((c) => c.wordUid), <String>['haus', 'garten', 'tuer']);
      expect(picked.first.ord, 2, reason: "haus's better sentence, 3 / 5");
    });

    test('never more than sentence_count', () {
      expect(
        pickSentences(candidates, learned: learned, count: 2, seed: 1),
        hasLength(2),
      );
    });

    test('the same seed picks the same sentences', () {
      final many = <SentenceCandidate>[
        for (var i = 0; i < 50; i++) s('w$i', 1, 'Das Haus ist groß.'),
      ];
      List<String> pick(int seed) => pickSentences(
        many,
        learned: learned,
        count: 3,
        seed: seed,
      ).map((c) => c.wordUid).toList();

      expect(pick(20260921), pick(20260921));
      expect(pick(20260921), isNot(pick(20260922)), reason: 'the jitter');
    });
  });

  group('forDay', () {
    late _FakeStore store;
    late SentencePicker picker;
    const today = '2026-09-21';

    setUp(() {
      store = _FakeStore()
        ..learned = <String>{'haus', 'gross'}
        ..pool = <SentenceCandidate>[
          s('haus', 1, 'Das Haus ist groß.'),
          s('tuer', 1, 'Die Tür ist offen.'),
          s('garten', 1, 'Der Garten ist groß.'),
          s('auto', 1, 'Das Auto ist neu.'),
        ];
      picker = SentencePicker(store, count: 3, gapDays: 14);
    });

    test('picks and records the day', () async {
      final picked = await picker.forDay(today);
      expect(picked, hasLength(3));
      expect(store.log[today], picked);
      expect(store.askedGap, 14);
    });

    test('FR-T5-01 the day reopened gets the same set back', () async {
      final first = await picker.forDay(today);
      store.pool = <SentenceCandidate>[s('neu', 1, 'Das Haus ist neu.')];

      expect(await picker.forDay(today), first);
    });

    test('with nothing learned there is nothing to record', () async {
      store.pool = <SentenceCandidate>[];
      expect(await picker.forDay(today), isEmpty);
      expect(store.log, isEmpty);
    });
  });
}

class _FakeStore implements SentenceStore {
  List<SentenceCandidate> pool = <SentenceCandidate>[];
  Set<String> learned = <String>{};
  final Map<PlanDate, List<SentenceCandidate>> log =
      <PlanDate, List<SentenceCandidate>>{};
  int? askedGap;

  @override
  Future<List<SentenceCandidate>> shownOn(PlanDate date) async =>
      log[date] ?? const <SentenceCandidate>[];

  @override
  Future<List<SentenceCandidate>> candidates(
    PlanDate today, {
    required int gapDays,
  }) async {
    askedGap = gapDays;
    return pool;
  }

  @override
  Future<Set<String>> learnedKeys() async => learned;

  @override
  Future<void> record(PlanDate date, List<SentenceCandidate> picked) async =>
      log[date] = picked;
}
