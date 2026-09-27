"""`app/lib/domain/cloze.dart`'s `clozeGap`, in Python, for the content gates
(#631): whether a cloze card, a practice sentence or an exam gap fill can
blank a word in an example sentence.

The two must agree: `tools/cloze_vectors.json` is the contract, and both
`tools/tests/test_cloze.py` and `app/test/domain/cloze_test.dart` run it.
"""

from __future__ import annotations

import re

from pipeline_steps import search_key, search_key_alt

#: Below this a key matches only whole words.
MIN_KEY = 3

#: Words a phrase's fallback never blanks alone, as search keys.
FUNCTION_WORDS = frozenset(
    # articles
    "der die das den dem des ein eine einen einem einer eines kein keine "
    "keinen keinem keiner "
    # pronouns
    "ich du er sie es wir ihr mich dich sich uns euch mir dir ihm ihn ihnen "
    "man "
    # question words
    "was wer wie wo wann warum wen wem wessen welche welcher welches welchen "
    "woher wohin "
    # conjunctions
    "und oder aber dass ob wenn als denn sondern".split()
)

#: Separable prefixes, as search keys, a longer one before any it starts with.
PARTICLES = (
    "zurueck zusammen weiter vorbei heraus herein hinaus kennen spazieren "
    "kaputt statt teil frei fern wohl fest fort hin her los weg nach mit vor "
    "aus auf ein bei dar ab an zu um"
).split()

_WORD = re.compile(r"[^\W\d_]+")
_INFINITIVE = re.compile(r"e?n$")
_NOTE = re.compile(r"\s*\([^)]*\)")


def cloze_gap(sentence: str, german: str, pos: str | None = None) -> tuple[int, int] | None:
    """(start, end) of the gap in [sentence], or None. A headword's bracket
    ("aber (Partikel)", "erheben (Steuern)") is tried with it first, then
    without it."""
    gap = _gap(sentence, german, pos)
    if gap is None and "(" in german:
        gap = _gap(sentence, _NOTE.sub("", german), pos)
    return gap


def _gap(sentence: str, german: str, pos: str | None):
    tokens = [(m.start(), m.end(), search_key(m.group(0))) for m in _WORD.finditer(sentence)]
    every = _WORD.findall(german)
    reflexive = len(every) > 1 and every[0].lower() == "sich"
    words = every[1:] if reflexive else every
    if not words:
        return None
    keys = [search_key(w) for w in words]
    if len(keys) == 1:
        return _find(tokens, keys[0], verb=pos == "verb")

    for i in range(len(tokens) - len(keys) + 1):
        if all(tokens[i + j][2] == keys[j] for j in range(len(keys))):
            return (tokens[i][0], tokens[i + len(keys) - 1][1])

    noun_verb = len(words) == 2 and words[-1] == words[-1].lower() and keys[-1].endswith("n")

    def noun(i: int) -> bool:
        return (i > 0 or reflexive or noun_verb) and words[i] != words[i].lower()

    for i in sorted(range(len(words)), key=lambda i: (not noun(i), -len(keys[i]), i)):
        if len(keys[i]) < MIN_KEY or keys[i] in FUNCTION_WORDS:
            continue
        infinitive = not noun(i) and len(keys[i]) > MIN_KEY + 1 and keys[i].endswith("n")
        hit = _find(tokens, keys[i], verb=infinitive, whole=len(keys[i]) <= MIN_KEY)
        if hit:
            return hit
    return None


def _find(tokens, key: str, *, verb: bool, whole: bool = False):
    stem = _INFINITIVE.sub("", key, count=1) if verb and len(key) > MIN_KEY + 1 else key
    for start, end, token in tokens:
        if whole or len(stem) < MIN_KEY:
            hit = token == stem
        else:
            hit = token.startswith(stem) or (verb and token.startswith("ge" + stem))
        if hit:
            return (start, end)
    if not verb:
        return None
    for particle in PARTICLES:
        if not key.startswith(particle):
            continue
        rest = _INFINITIVE.sub("", key[len(particle):], count=1)
        if len(rest) < MIN_KEY:
            continue
        for i, (start, end, token) in enumerate(tokens):
            split = token.startswith(rest) and any(t[2] == particle for t in tokens[i + 1 :])
            if split or token.startswith(f"{particle}ge{rest}") or token.startswith(f"{particle}zu{rest}"):
                return (start, end)
    return None


#: A form that names no word: the auxiliary of "hat gegeben", the "am" of
#: "am besten".
_AUXILIARIES = frozenset({"hat", "ist", "am"})


def names_its_word(sentence: str, german: str, forms: str | None) -> bool:
    """Whether [sentence] says its word at all: a gap, or a word sharing the
    first three letters of the headword's words or its forms' ("liest" for
    lesen, "Erdäpfelsalat" for Erdapfel). The cloze's gap is stricter; a
    sentence that fails this is about something else (#631)."""
    if cloze_gap(sentence, german) is not None:
        return True
    tokens = {search_key(t) for t in _WORD.findall(sentence)}
    tokens |= {search_key_alt(t) for t in _WORD.findall(sentence)}
    for text in (german, forms or ""):
        for word in _WORD.findall(_NOTE.sub("", text)):
            for key in {search_key(word), search_key_alt(word)}:
                if len(key) < MIN_KEY or key in FUNCTION_WORDS or key in _AUXILIARIES:
                    continue
                if any(key[:MIN_KEY] in token for token in tokens):
                    return True
    return False


def examples_without_their_word(words) -> list[str]:
    """#631: a warning per example of a word to learn that does not say it.
    A note's examples show its lesson, not its name."""
    return [
        f"example without its word: {word.source_file} row {word.row} "
        f"({word.german}) example {example.ord}: {example.german!r}"
        for word in words
        if word.kind == "vocab"
        for example in word.examples
        if cloze_gap(example.german, word.german, word.pos) is None
        and not names_its_word(example.german, word.german, word.forms)
    ]
