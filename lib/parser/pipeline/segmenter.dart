import '../catalogue/alias_index.dart';
import '../catalogue/lexicon.dart';
import 'measurement_parser.dart';

final _wordSplit = RegExp(r'\s+');
final _digit = RegExp(r'^\d+(?:\.\d+)?$');

// A period ends a sentence-like separator ("rocket. glass water") --
// except when it's a decimal point ("0.5l") or part of a known
// abbreviation ("tsp.", "tbsp."), which measurement/unit parsing still
// needs to see intact.
final _sentenceSplitPeriod = RegExp(r'(?<!\d)(?<!\btsp)(?<!\btbsp)\.(?=\s)\s*');

/// True when the word before [andIndex] and the word(s) after it form a
/// compound quantity phrase ("`<cardinal-or-digit>` and [a/an] `<fraction>`",
/// e.g. "one and a half", "two and a quarter", "1 and a half") -- built
/// from the same cardinals/fractions tables the quantity parser uses, not
/// a hardcoded phrase, so it generalizes to every combination those tables
/// support.
bool _isCompoundQuantityAnd(List<String> words, int andIndex, Lexicon lexicon) {
  if (andIndex <= 0 || andIndex >= words.length - 1) return false;
  final before = words[andIndex - 1];
  final beforeIsQuantity = lexicon.cardinals.containsKey(before) || _digit.hasMatch(before);
  if (!beforeIsQuantity) return false;

  var afterIndex = andIndex + 1;
  if (words[afterIndex] == 'a' || words[afterIndex] == 'an') afterIndex++;
  if (afterIndex >= words.length) return false;

  final oneWord = words[afterIndex];
  final twoWord = afterIndex + 1 < words.length ? '$oneWord ${words[afterIndex + 1]}' : null;
  return lexicon.fractions.containsKey(oneWord) ||
      (twoWord != null && lexicon.fractions.containsKey(twoWord));
}

/// Splits a sentence into independent food/exercise phrases on top-level
/// commas, semicolons, sentence-ending periods, the standalone word "and"
/// and the standalone word "with" -- except an "and" that's actually part
/// of a compound quantity ("one and a half eggs"), which is protected so
/// it reaches the quantity parser intact, and a "with" that's part of an
/// already-known compound dish name ("burger with cheese"), which is left
/// whole rather than split into two unrelated components. This is a
/// heuristic, not a full grammar: a compound food name containing "and"/
/// "with" that ISN'T a registered alias would still be mis-split. Refine
/// this once real user input shows it matters.
List<String> segmentPhrases(String normalizedText, Lexicon lexicon, AliasIndex aliasIndex) {
  final commaParts = normalizedText.split(RegExp('\\s*[,;]\\s*|${_sentenceSplitPeriod.pattern}'));
  final segments = <String>[];
  for (final part in commaParts) {
    for (final piece in _splitOnStandaloneAnd(part, lexicon)) {
      segments.addAll(_splitOnStandaloneWith(piece, aliasIndex));
    }
  }
  return segments.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
}

List<String> _splitOnStandaloneAnd(String text, Lexicon lexicon) {
  final words = text.trim().split(_wordSplit).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return const [];

  final segments = <String>[];
  var current = <String>[];
  for (var i = 0; i < words.length; i++) {
    final word = words[i];
    if (word == 'and' && !_isCompoundQuantityAnd(words, i, lexicon)) {
      if (current.isNotEmpty) segments.add(current.join(' '));
      current = [];
      continue;
    }
    current.add(word);
  }
  if (current.isNotEmpty) segments.add(current.join(' '));
  return segments;
}

List<String> _splitOnStandaloneWith(String text, AliasIndex aliasIndex) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const [];
  // Already a known whole dish name ("burger with cheese",
  // "cottage cheese with chives") -- don't tear it apart. Checked both with
  // the text as-is AND with a leading exact measurement peeled off first
  // ("100g cottage cheese with chives"), since otherwise the "100g" prefix
  // stops the whole-phrase alias lookup from ever matching and this falls
  // through to being wrongly split into "100g cottage cheese" + "chives".
  if (aliasIndex.resolve(trimmed) != null) return [trimmed];
  if (aliasIndex.resolve(parseMeasurement(trimmed).remainder) != null) {
    return [trimmed];
  }

  final words = trimmed.split(_wordSplit).where((w) => w.isNotEmpty).toList();
  final withIndex = words.indexOf('with');
  if (withIndex <= 0 || withIndex >= words.length - 1) return [trimmed];

  return [
    words.sublist(0, withIndex).join(' '),
    words.sublist(withIndex + 1).join(' '),
  ];
}
