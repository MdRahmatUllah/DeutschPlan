/// [text] as a field of [max] characters holds it (#1233): whole when it
/// fits; otherwise a window of it cut at word ends, around [around] when
/// that is in it, with «…» where it was cut. R2's fields take 200 characters
/// (#691 EX-13), and a document's sentence pre-filled longer would lose its
/// end, silently, at the learner's first edit.
String excerpt(String text, {required int max, String? around}) {
  final whole = text.trim();
  if (whole.length <= max) return whole;
  const dots = '…';
  // Room for a «…» on each side.
  final room = max - 2;
  final at = around == null || around.isEmpty
      ? -1
      : whole.toLowerCase().indexOf(around.toLowerCase());
  final word = at < 0 ? 0 : around!.length;
  var start = at < 0
      ? 0
      : (at + word ~/ 2 - room ~/ 2).clamp(0, whole.length - room);
  var end = start + room;
  // In to word ends. The window is centred on the word, so its first space
  // comes before the word and its last after it.
  if (start > 0) {
    final space = whole.indexOf(' ', start);
    if (space >= 0 && space < (at < 0 ? end : at)) start = space + 1;
  }
  if (end < whole.length) {
    final space = whole.lastIndexOf(' ', end);
    if (space > start) end = space;
  }
  // No space to cut at: never half a surrogate pair either side.
  if (start > 0 && _low(whole.codeUnitAt(start))) start++;
  if (end < whole.length && _high(whole.codeUnitAt(end - 1))) end--;
  return '${start > 0 ? dots : ''}'
      '${whole.substring(start, end).trim()}'
      '${end < whole.length ? dots : ''}';
}

bool _high(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
bool _low(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;
