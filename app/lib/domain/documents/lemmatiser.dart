/// #1223: a German word as written to its course lemmas: «Häusern» → Haus,
/// «ging» → gehen, «rufe … an» → anrufen (`03-domain/document-matcher.md`,
/// *The lemmatiser*).
///
/// No dictionary from outside: the course's own words and `forms`, the
/// regular endings, and [strongVerbs]. Every form a course word can take is
/// generated once, folded, into one index; a token is then one lookup.
/// Over-generation is harmless as long as the made-up form is no other word
/// ("kommte"); where it is one, the best-founded reading wins (`_Source`).
library;

import 'package:sogda/domain/documents/stop_words.dart';
import 'package:sogda/domain/documents/strong_verbs.dart';
import 'package:sogda/domain/text_norm.dart';

/// A course word as the lemmatiser reads it from `content.db` (`kind`
/// `vocab` only: notes and comparisons are never studied, BR-CONTENT-04).
class LemmaEntry {
  const LemmaEntry({
    required this.uid,
    required this.german,
    required this.pos,
    this.article,
    this.forms,
  });

  final String uid;
  final String german;
  final String pos;
  final String? article;
  final String? forms;

  @override
  String toString() => german;
}

/// A gender form's ending after its stem, one word with it (#1270): «:in»,
/// «*innen», «_innen», «/innen», «/-innen», and with a capital I («:Innen»).
const String genderSuffix = r'[:*_/]-?[Ii]n(?:nen)?(?!\p{L})';

final RegExp _genderForm = RegExp('^(.+)$genderSuffix\$', unicode: true);

/// Where a form came from. A token several entries share keeps only its
/// best-founded readings: «gefallen» is the headword gefallen before it is
/// fallen's participle, «wegen» the preposition before Weg + -en.
enum _Source { head, forms, rule }

const List<String> _adjectiveEndings = <String>[
  '',
  'e',
  'en',
  'em',
  'er',
  'es',
];

/// Prefixes a verb takes on its base's strong stems: ver + stand, an + kam.
const Set<String> _prefixes = <String>{
  'be', 'ge', 'emp', 'ent', 'er', 'miss', 'ver', 'zer', //
  'ab', 'an', 'auf', 'aus', 'bei', 'dar', 'durch', 'ein', 'fest', 'fort',
  'her', 'hin', 'hinter', 'los', 'mit', 'nach', 'nieder', 'statt', 'teil',
  'über', 'um', 'unter', 'vor', 'weg', 'weiter', 'wider', 'wieder', 'zu',
  'zurück', 'zusammen', 'voll', 'vorbei', 'entgegen', 'gegenüber',
};

class Lemmatiser {
  Lemmatiser(Iterable<LemmaEntry> entries) {
    for (final entry in entries) {
      final head = headOf(entry);
      if (head == null) continue;
      switch (entry.pos) {
        case 'verb':
          _verb(entry, head);
        case 'noun':
          _noun(entry, head);
        case 'adj':
          _adjective(entry, head);
        default:
          _add(head, entry, _Source.head);
          // An adverb used as an adjective (die monatliche Zahlung, viele),
          // an ordinal (die ersten Busse).
          if (entry.pos == 'adv' ||
              (entry.pos == 'num' && head.endsWith('e'))) {
            final stem = _adjectiveStem(head);
            for (final ending in _adjectiveEndings) {
              _add('$stem$ending', entry, _Source.rule);
            }
          }
          _otherForms(entry);
      }
    }
  }

  /// Folded form → each entry it can be, with its best source.
  final Map<String, Map<LemmaEntry, _Source>> _index =
      <String, Map<LemmaEntry, _Source>>{};

  /// Separable verbs split in a main clause: particle → the base's finite
  /// form → the particle verbs («rufe … an» is an → rufe → anrufen).
  final Map<String, Map<String, Set<LemmaEntry>>> _separable =
      <String, Map<String, Set<LemmaEntry>>>{};

  static final RegExp _brackets = RegExp(r'\([^)]*\)');
  static final RegExp _list = RegExp(r'[/↔—:]|\bvs\.');
  static final RegExp _trailingMark = RegExp(r'[!?.]+$');

  /// The one word a headword inflects from: «aufkommen für» → aufkommen,
  /// «sich befassen mit» → befassen. Null for a phrase or a list
  /// («Blaue Karte», «sagen vs. behaupten»), which no single token is.
  static String? headOf(LemmaEntry entry) {
    final german = entry.german.replaceAll(_brackets, ' ');
    if (_list.hasMatch(german)) return null;
    final words = _words(german);
    if (words.length == 1) return words.single.replaceAll(_trailingMark, '');
    if (entry.pos != 'verb') return null;
    for (final word in words) {
      if (word.length > 3 && word.endsWith('n') && word == word.toLowerCase()) {
        return word;
      }
    }
    return null;
  }

  static List<String> _words(String text) => text
      .split(' ')
      .map((w) => w.trim())
      .where((w) => w.isNotEmpty && w != 'sich')
      .toList();

  static bool _multiword(LemmaEntry entry) =>
      _words(entry.german.replaceAll(_brackets, ' ')).length > 1;

  /// Search's fold, without its punctuation pass: case, ß as ss, umlauts
  /// expanded («Tür» → tuer), as `searchKey` keys a single word.
  static String fold(String word) {
    final lowered = nfc(word.toLowerCase());
    final buffer = StringBuffer();
    for (final rune in lowered.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(umlautExpansions[char] ?? char);
    }
    return buffer.toString();
  }

  void _add(String form, LemmaEntry entry, _Source source) {
    if (form.isEmpty) return;
    final readings = _index.putIfAbsent(
      fold(form),
      () => <LemmaEntry, _Source>{},
    );
    final had = readings[entry];
    if (had == null || source.index < had.index) readings[entry] = source;
  }

  void _noun(LemmaEntry entry, String head) {
    _add(head, entry, _Source.head);
    final masculine = entry.article == 'der';
    if (entry.article != 'die') {
      // The genitive (des Vertrags, des Hauses), and the old dative's -e
      // (nach Hause, im Jahre).
      _add('${head}s', entry, _Source.rule);
      _add('${head}es', entry, _Source.rule);
      if (!head.endsWith('e')) _add('${head}e', entry, _Source.rule);
    }
    if (head.endsWith('e')) {
      // A weak noun (den Kunden) or an adjectival one (ein Angestellter).
      for (final ending in <String>['n', 'r', 'm', 's']) {
        _add('$head$ending', entry, _Source.rule);
      }
    } else if (masculine &&
        RegExp(r'(ent|ant|ist|oge|at|nom|soph|ensch|err|bar|auer)$')
            .hasMatch(head)) {
      // den Studenten, dem Menschen, Herrn Meier, dem Nachbarn.
      _add('${head}en', entry, _Source.rule);
      _add('${head}n', entry, _Source.rule);
    }
    for (final plural in _alternatives(entry.forms)) {
      _add(plural, entry, _Source.forms);
      // The dative plural: mit den Kindern.
      if (!plural.endsWith('n') && !plural.endsWith('s')) {
        _add('${plural}n', entry, _Source.rule);
      }
    }
  }

  /// `forms` as single words: «Pizzen / Pizzas» is two plurals.
  static Iterable<String> _alternatives(String? forms) => (forms ?? '')
      .split(RegExp(r'[/,·]'))
      .map((f) => f.trim())
      .where((f) => f.isNotEmpty && !f.contains(' ') && f != '-');

  void _adjective(LemmaEntry entry, String head) {
    _add(head, entry, _Source.head);
    final stem = _adjectiveStem(head);
    for (final ending in _adjectiveEndings) {
      _add('$stem$ending', entry, _Source.rule);
    }
    if (!_comparison(entry)) {
      // dunkel → dunkler, leise → leiser, schnell → schnellste.
      final comparative = head.endsWith('e') ? '${head}r' : '${stem}er';
      final superlative = RegExp(r'([dtsßzx]|sch)$').hasMatch(head)
          ? '${head}est'
          : '${head}st';
      for (final ending in _adjectiveEndings) {
        _add('$comparative$ending', entry, _Source.rule);
        _add('$superlative$ending', entry, _Source.rule);
      }
    }
  }

  /// The stem endings attach to: dunkel → dunkl-e, teuer → teur-e, hoch →
  /// hoh-e, leise → leis-e.
  static String _adjectiveStem(String head) {
    if (head == 'hoch') return 'hoh';
    if (head.endsWith('e')) return head.substring(0, head.length - 1);
    if (RegExp(r'[^aeiouäöü]el$').hasMatch(head) ||
        RegExp(r'[aeiouäöü]er$').hasMatch(head)) {
      return '${head.substring(0, head.length - 2)}${head[head.length - 1]}';
    }
    return head;
  }

  /// `forms` as «höher · am höchsten» (adjectives, and gern, viel): the
  /// comparative and the superlative, with their endings. Whether it had them.
  bool _comparison(LemmaEntry entry) {
    final parts = (entry.forms ?? '').split('·').map((p) => p.trim()).toList();
    if (parts.length != 2 || !parts.last.startsWith('am ')) return false;
    final comparative = parts.first;
    var superlative = parts.last.substring(3);
    if (superlative.endsWith('en')) {
      superlative = superlative.substring(0, superlative.length - 2);
    }
    _add(comparative, entry, _Source.forms);
    for (final ending in _adjectiveEndings) {
      _add('$comparative$ending', entry, _Source.rule);
      _add('$superlative$ending', entry, _Source.rule);
    }
    return true;
  }

  void _otherForms(LemmaEntry entry) {
    if (_comparison(entry)) return;
    for (final form in _alternatives(entry.forms)) {
      _add(form, entry, _Source.forms);
    }
  }

  void _verb(LemmaEntry entry, String infinitive) {
    // A headword that is a form itself («ward», «mag», «dürfte») is no
    // infinitive to conjugate: «war» is sein's, never ward's. Its forms are
    // as founded as a rule's, so a verb whose form it is reads first: «mag»
    // is mögen's, not C1's concessive «mag» (#1274).
    if (!infinitive.endsWith('n')) {
      for (final form in <String>[infinitive, ..._alternatives(entry.forms)]) {
        _add(form, entry, _Source.rule);
      }
      return;
    }
    _add(infinitive, entry, _Source.head);
    // forms: «kommt auf · ist aufgekommen», «befasst sich · hat sich befasst».
    final parts = (entry.forms ?? '').split('·').map((p) => p.trim()).toList();
    final present = _words(parts.first);
    final third = present.isEmpty ? null : present.first;
    String? particle;
    if (present.length > 1 &&
        present.last != infinitive &&
        infinitive.startsWith(present.last)) {
      particle = present.last;
    }
    final participle = parts.length > 1 ? _words(parts.last).lastOrNull : null;

    final base = particle == null
        ? infinitive
        : infinitive.substring(particle.length);
    for (final form in _finite(base, third)) {
      if (particle == null) {
        _add(form, entry, form == third ? _Source.forms : _Source.rule);
      } else {
        // Joined in a subordinate clause (wenn er ankommt), split in a main
        // one (er kommt … an).
        _add('$particle$form', entry, _Source.rule);
        _separable
            .putIfAbsent(fold(particle), () => <String, Set<LemmaEntry>>{})
            .putIfAbsent(fold(form), () => <LemmaEntry>{})
            .add(entry);
      }
    }
    if (particle != null) _add('${particle}zu$base', entry, _Source.rule);
    if (participle != null) {
      _add(participle, entry, _Source.forms);
      // As an adjective: die geschlossene Tür.
      for (final ending in _adjectiveEndings.skip(1)) {
        _add('$participle$ending', entry, _Source.rule);
      }
    }
    // The present participle: spannend, die steigenden Kosten.
    for (final ending in _adjectiveEndings) {
      _add('${infinitive}d$ending', entry, _Source.rule);
    }
  }

  /// A verb's finite forms: present, past (weak, or [strongVerbs]'), the
  /// Konjunktiv II and the imperative, from its infinitive and its 3rd
  /// person (which carries a stem change: nimmt, fährt, weiß).
  static Set<String> _finite(String infinitive, String? third) {
    final String stem;
    if (infinitive.endsWith('eln') || infinitive.endsWith('ern')) {
      stem = infinitive.substring(0, infinitive.length - 1);
    } else if (infinitive.endsWith('en')) {
      stem = infinitive.substring(0, infinitive.length - 2);
    } else {
      stem = infinitive.substring(0, infinitive.length - 1);
    }
    // arbeit-e-t, rechn-e-t, but komm-t, lern-t.
    final e = RegExp(r'([dt]|[^aeiouäöülrhmn][mn])$').hasMatch(stem) ? 'e' : '';
    final forms = <String>{
      infinitive,
      stem,
      '${stem}e',
      '$stem${e}st',
      '$stem${e}t',
      '${stem}en',
      // ich sammle: -eln drops its e before the ending.
      if (infinitive.endsWith('eln')) '${stem.substring(0, stem.length - 2)}le',
      ...?irregularForms[infinitive],
    };
    final strong = _strong(infinitive);
    if (strong == null) {
      for (final ending in <String>['te', 'test', 'ten', 'tet']) {
        forms.add('$stem$e$ending');
      }
    } else {
      final (prefix, past, subjunctive) = strong;
      for (final form in [..._pastForms(past), ..._pastForms(subjunctive)]) {
        forms.add('$prefix$form');
      }
    }
    if (third != null) {
      forms.add(third);
      if (third.endsWith('t')) {
        // nimmt → nimmst, nimm.
        final root = third.substring(0, third.length - 1);
        forms
          ..add(root)
          ..add('${root}st');
      } else {
        // weiß → weißt.
        forms
          ..add('${third}t')
          ..add('${third}st');
      }
    }
    return forms;
  }

  static Iterable<String> _pastForms(String stem) => stem.endsWith('e')
      ? <String>[stem, '${stem}st', '${stem}n', '${stem}t']
      : <String>[
          stem,
          '${stem}st',
          '${stem}est',
          '${stem}en',
          '${stem}t',
          '${stem}et',
        ];

  /// [infinitive]'s strong row, through its base when it has a prefix:
  /// (prefix, Präteritum, Konjunktiv II). verstehen → (ver, stand, stünde).
  static (String, String, String)? _strong(String infinitive) {
    (String, String, String)? best;
    var bestLength = 0;
    for (final MapEntry(key: base, value: (past, subjunctive))
        in strongVerbs.entries) {
      if (base.length <= bestLength || !infinitive.endsWith(base)) continue;
      final prefix = infinitive.substring(0, infinitive.length - base.length);
      if (prefix.isNotEmpty && !_isPrefix(prefix)) continue;
      best = (prefix, past, subjunctive);
      bestLength = base.length;
    }
    return best;
  }

  /// One prefix or two (vorbe-, zurückge-), never a stray letter: kleiden
  /// isn't k + leiden.
  static bool _isPrefix(String prefix) {
    if (_prefixes.contains(prefix)) return true;
    for (var i = 1; i < prefix.length; i++) {
      if (_prefixes.contains(prefix.substring(0, i)) &&
          _prefixes.contains(prefix.substring(i))) {
        return true;
      }
    }
    return false;
  }

  static bool _punctuation(String token) =>
      RegExp(r'^[,;:.!?]+$').hasMatch(token);

  static const Set<String> _coordinators = <String>{'und', 'oder'};

  /// Each token of one sentence, with its commas and semicolons as tokens of
  /// their own (they end a clause): its course entries, best first. Empty
  /// when none; several when the learner has to choose («Bitte» at the start
  /// of a sentence). A separable verb's particle, joined to its verb, is
  /// empty.
  List<List<LemmaEntry>> sentence(List<String> tokens) {
    final result = List<List<LemmaEntry>>.filled(
      tokens.length,
      const <LemmaEntry>[],
    );
    final done = <int>{};
    var start = 0;
    for (var i = 0; i <= tokens.length; i++) {
      // «und» and «oder» join main clauses without a comma, each with its own
      // particle: «Holen Sie Ihr Kind ab oder geben Sie ihm … mit» (#1270).
      if (i < tokens.length &&
          !_punctuation(tokens[i]) &&
          !_coordinators.contains(tokens[i].toLowerCase())) {
        continue;
      }
      _splitVerb(tokens, start, i, result, done);
      start = i + 1;
    }
    final first = tokens.indexWhere((t) => !_punctuation(t));
    // A letter's salutation, «Liebe Eltern», «Lieber Herr Becker»: the
    // adjective lieb, which is neither the noun Liebe nor gern's lieber.
    if (first >= 0 &&
        first + 1 < tokens.length &&
        _salutation.hasMatch(tokens[first]) &&
        _startsCapital(tokens[first + 1])) {
      done.add(first);
    }
    for (var i = 0; i < tokens.length; i++) {
      if (done.contains(i) || _punctuation(tokens[i])) continue;
      result[i] = lookup(
        tokens[i],
        sentenceStart: i == first,
        afterArticle: i > 0 && _articles.contains(tokens[i - 1].toLowerCase()),
      );
    }
    return result;
  }

  static final RegExp _salutation = RegExp(r'^[Ll]ieb(e|er|es|en)$');

  static bool _startsCapital(String token) =>
      token[0] != token[0].toLowerCase();

  /// What a nominalised infinitive follows: «das Lesen», «beim Lesen».
  static const Set<String> _articles = <String>{
    'das', 'dem', 'des', 'beim', 'zum', 'vom', 'im', 'am', 'ins', 'ans', //
    'aufs', 'fürs', 'ums', 'durchs', 'übers',
  };

  /// A clause [start, end) that ends in a separable particle, with one of
  /// its verbs' finite forms before it: «Ich rufe Sie morgen an». Failing
  /// that, the sentence before the clause, since a comma also sets off a
  /// list or an apposition: «Der Termin findet am Dienstag, dem 14. Oktober,
  /// um 10 Uhr statt».
  void _splitVerb(
    List<String> tokens,
    int start,
    int end,
    List<List<LemmaEntry>> result,
    Set<int> done,
  ) {
    if (end - start < 2) return;
    final particle = tokens[end - 1].toLowerCase();
    final byForm = _separable[fold(particle)];
    final before = <int>[
      for (var i = start; i < end - 1; i++) i,
      for (var i = 0; i < start; i++) i,
    ].where((i) => !done.contains(i));
    if (byForm != null) {
      for (final i in before) {
        final verbs = byForm[fold(tokens[i])];
        if (verbs == null) continue;
        result[i] = _sorted(verbs);
        done.addAll(<int>[i, end - 1]);
        return;
      }
    }
    // A particle verb the course doesn't have («findet … statt»): its verb
    // is no form of finden, nor its particle the preposition statt. A
    // direction only (hin, her, los) leaves the verb as it is: «Wo gehst du
    // hin?» is still gehen.
    if (!_separableParticles.contains(particle)) return;
    for (final i in before) {
      final sentenceStart = i == tokens.indexWhere((t) => !_punctuation(t));
      if (!lookup(
        tokens[i],
        sentenceStart: sentenceStart,
      ).any((e) => e.pos == 'verb')) {
        continue;
      }
      done.add(end - 1);
      if (!_directions.contains(particle)) done.add(i);
      return;
    }
  }

  /// The particles a main clause sends to its end, whether or not the
  /// course has their verb: never be- or ver-, and not durch-, über- or um-,
  /// which end a clause as prepositions as often.
  static final Set<String> _separableParticles = _prefixes.difference(<String>{
    'be', 'ge', 'emp', 'ent', 'er', 'miss', 'ver', 'zer', //
    'durch', 'über', 'um', 'unter', 'wider', 'hinter', 'voll',
  });

  /// Particles that only add a direction to their verb.
  static const Set<String> _directions = <String>{'hin', 'her', 'los'};

  /// [token]'s course entries, alone. Case decides first, where it can: in
  /// the middle of a sentence «Weg» is the noun and «weg» the adverb. Then
  /// the best source, then a word over a phrase, then the bare word over a
  /// headword with more to it (warten before «warten auf»).
  List<LemmaEntry> lookup(
    String token, {
    bool sentenceStart = false,
    bool afterArticle = false,
  }) {
    // A gender form («Mitarbeiter*innen», «Kund:innen», «Ärzt_innen») is
    // its stem's word, or the stem's with -e (Kunde, Ärzte), or the -in one.
    final gender = _genderForm.firstMatch(token);
    if (gender != null) {
      for (final stem in <String>[
        gender[1]!,
        '${gender[1]}e',
        '${gender[1]}in',
      ]) {
        final found = lookup(
          stem,
          sentenceStart: sentenceStart,
          afterArticle: afterArticle,
        );
        if (found.isNotEmpty) return found;
      }
      return const <LemmaEntry>[];
    }
    final readings = _index[fold(token)];
    if (readings == null) return const <LemmaEntry>[];
    var candidates = readings.keys.toList();
    final allCaps = token.length > 1 && token == token.toUpperCase();
    if (!sentenceStart && !allCaps) {
      final capital = token[0] != token[0].toLowerCase();
      // In the middle of a sentence a capital is a noun's or a name's, and a
      // small letter never is: «kosten» is no form of die Kosten. Only a
      // nominalised infinitive after an article is its verb («beim Lesen»).
      final matching = candidates
          .where((e) => _capitalised(e) == capital)
          .toList();
      if (matching.isEmpty && capital && afterArticle) {
        candidates = candidates
            .where((e) => e.pos == 'verb' && fold(headOf(e)!) == fold(token))
            .toList();
      } else {
        candidates = matching;
      }
      if (candidates.isEmpty) return const <LemmaEntry>[];
    }
    final key = fold(token);
    final cased = candidates;
    final best = candidates
        .map((e) => readings[e]!.index)
        .reduce((a, b) => a < b ? a : b);
    candidates = candidates.where((e) => readings[e]!.index == best).toList();
    candidates = _prefer(candidates, (e) => e.pos != 'phrase');
    candidates = _prefer(candidates, (e) => !_multiword(e));
    // Equally founded, the headword nearer the token: «nächsten» is
    // nächste's before it is nah's superlative.
    int shared(LemmaEntry e) {
      final head = fold(headOf(e) ?? e.german);
      var n = 0;
      while (n < head.length && n < key.length && head[n] == key[n]) {
        n++;
      }
      return n;
    }

    final nearest = candidates.map(shared).reduce((a, b) => a > b ? a : b);
    candidates = candidates.where((e) => shared(e) == nearest).toList();
    final verb = _verbToo[key];
    if (verb != null) {
      candidates = <LemmaEntry>{
        ...candidates,
        ...cased.where((e) => headOf(e) == verb),
      }.toList();
    }
    return _sorted(candidates);
  }

  /// A verb's form that is also an unrelated word's headword: both
  /// readings stay, and D2 asks which (#1274). «Ich weiß nicht» is wissen,
  /// «Die Wand ist weiß» the colour. Folded form → the verb.
  // ponytail: a list, not a rule. The participles that are adjectives too
  // (erlaubt, reserviert) are their verb's, so the adjective is fine there.
  // Add a pair when a text finds another verb form like weiß.
  static const Map<String, String> _verbToo = <String, String>{
    'weiss': 'wissen',
  };

  /// «Nebenkostenabrechnung» → [Nebenkosten, Abrechnung]: a word the
  /// course doesn't have, as course words, the last one a noun (the
  /// compound's head), with a linking -s-, -es-, -n-, -en- or -e- between
  /// («Integrationskurs» → Integration + Kurs). The longest head wins. Null
  /// when it isn't one. A hint only: D2 never adds the parts.
  List<String>? compoundParts(String word) {
    for (var cut = 3; cut <= word.length - 3; cut++) {
      final rest = word.substring(cut);
      final nouns = lookup('${rest[0].toUpperCase()}${rest.substring(1)}')
          .where((e) => e.pos == 'noun');
      if (nouns.isEmpty) continue;
      final left = word.substring(0, cut);
      for (final link in const <String>['', 's', 'es', 'n', 'en', 'e']) {
        if (!left.endsWith(link) || left.length - link.length < 3) continue;
        final stem = left.substring(0, left.length - link.length);
        // A part is a word to learn, never a stop word: «Wasserzähler» is
        // no «Was» + «Erzähler».
        if (stopForms.contains(stem.toLowerCase())) continue;
        final known = lookup(stem, sentenceStart: true);
        final parts = known.isNotEmpty
            ? <String>[known.first.german]
            : compoundParts(stem);
        // The parts as their headwords: «Mietvertrags» → … + Vertrag.
        if (parts != null) return <String>[...parts, nouns.first.german];
      }
    }
    return null;
  }

  static bool _capitalised(LemmaEntry entry) {
    final first = entry.german[0];
    return first != first.toLowerCase();
  }

  static List<LemmaEntry> _prefer(
    List<LemmaEntry> candidates,
    bool Function(LemmaEntry) test,
  ) {
    final preferred = candidates.where(test).toList();
    return preferred.isEmpty ? candidates : preferred;
  }

  static List<LemmaEntry> _sorted(Iterable<LemmaEntry> entries) =>
      entries.toList()..sort((a, b) {
        final byWord = a.german.compareTo(b.german);
        return byWord != 0 ? byWord : a.uid.compareTo(b.uid);
      });
}
