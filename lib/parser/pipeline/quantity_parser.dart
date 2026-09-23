import '../catalogue/lexicon.dart';
import 'token_matching.dart';

class QuantityParseResult {
  const QuantityParseResult(this.quantity, this.approximate, this.remainder);
  final double quantity;
  final bool approximate;
  final String remainder;
}

final _multiplierPrefix = RegExp(r'^(\d+(?:\.\d+)?)\s*[x×]\b');
final _multiplierSuffix = RegExp(r'^[x×]\s*(\d+(?:\.\d+)?)\b');
// A bare `\b` here would let the engine backtrack "0.5l" down to just "0"
// (boundary holds between digit "0" and ".") -- the lookahead blocks that by
// also forbidding a following ".", so a decimal number glued to a unit
// letter (measurement_parser's job) is correctly left untouched here.
final _plainNumber = RegExp(r'^(\d+(?:\.\d+)?)(?![a-zA-Z0-9.])');
final _andWord = RegExp(r'^and\b');
final _aOrAn = RegExp(r'^(a|an)\b');

/// Matches "`<cardinal-or-digit>` and [a/an] `<fraction>`" ("one and a half",
/// "two and a quarter", "1 and a half") from the same cardinals/fractions
/// tables the rest of this parser already uses -- not a hardcoded phrase,
/// so it generalizes to every cardinal/fraction combination those tables
/// support.
(double, String)? _tryCompoundCardinalFraction(String text, Lexicon lexicon) {
  double whole;
  var rest = text;

  final cardinalTable = PhraseTable(
    lexicon.cardinals.map((k, v) => MapEntry(k, v.toDouble())),
  );
  final cardinalMatch = cardinalTable.matchAtStart(rest);
  if (cardinalMatch != null && cardinalMatch.$1 > 0) {
    whole = cardinalMatch.$1;
    rest = rest.substring(cardinalMatch.$2);
  } else {
    final numberMatch = _plainNumber.firstMatch(rest);
    if (numberMatch == null) return null;
    whole = double.parse(numberMatch.group(1)!);
    rest = rest.substring(numberMatch.end);
  }

  rest = rest.trimLeft();
  final andMatch = _andWord.firstMatch(rest);
  if (andMatch == null) return null;
  rest = rest.substring(andMatch.end).trimLeft();

  final aMatch = _aOrAn.firstMatch(rest);
  if (aMatch != null) rest = rest.substring(aMatch.end).trimLeft();

  final fractionTable = PhraseTable(lexicon.fractions);
  final fractionMatch = fractionTable.matchAtStart(rest);
  if (fractionMatch == null) return null;

  return (
    whole + fractionMatch.$1,
    rest.substring(fractionMatch.$2).trimLeft(),
  );
}

QuantityParseResult parseQuantity(String text, Lexicon lexicon) {
  var remaining = text.trimLeft();
  var approximate = false;
  double? quantity;

  final approxTable = PhraseTable({
    for (final w in lexicon.approximationWords) w: true,
  });
  while (true) {
    final match = approxTable.matchAtStart(remaining);
    if (match == null) break;
    approximate = true;
    remaining = remaining.substring(match.$2).trimLeft();
  }

  final prefixMatch = _multiplierPrefix.firstMatch(remaining);
  if (prefixMatch != null) {
    quantity = double.parse(prefixMatch.group(1)!);
    remaining = remaining.substring(prefixMatch.end).trimLeft();
  } else {
    final suffixMatch = _multiplierSuffix.firstMatch(remaining);
    if (suffixMatch != null) {
      quantity = double.parse(suffixMatch.group(1)!);
      remaining = remaining.substring(suffixMatch.end).trimLeft();
    }
  }

  // Word multipliers ("couple", "a couple", "double", "triple") -- this
  // table was already loaded but never actually consulted until now.
  if (quantity == null) {
    final multiplierTable = PhraseTable(
      lexicon.multipliers.map((k, v) => MapEntry(k, v.toDouble())),
    );
    final match = multiplierTable.matchAtStart(remaining);
    if (match != null) {
      quantity = match.$1;
      remaining = remaining.substring(match.$2).trimLeft();
    }
  }

  // Compound cardinal+fraction ("one and a half", "2 and a quarter") must
  // be tried before a bare cardinal/number would otherwise just match the
  // whole part and stop.
  if (quantity == null) {
    final compound = _tryCompoundCardinalFraction(remaining, lexicon);
    if (compound != null) {
      quantity = compound.$1;
      remaining = compound.$2;
    }
  }

  if (quantity == null) {
    final fractionTable = PhraseTable(lexicon.fractions);
    final match = fractionTable.matchAtStart(remaining);
    if (match != null) {
      quantity = match.$1;
      remaining = remaining.substring(match.$2).trimLeft();
    }
  }

  if (quantity == null) {
    final match = _plainNumber.firstMatch(remaining);
    if (match != null) {
      quantity = double.parse(match.group(1)!);
      remaining = remaining.substring(match.end).trimLeft();
    }
  }

  if (quantity == null) {
    final cardinalTable = PhraseTable(
      lexicon.cardinals.map((k, v) => MapEntry(k, v.toDouble())),
    );
    final match = cardinalTable.matchAtStart(remaining);
    if (match != null && match.$1 > 0) {
      quantity = match.$1;
      remaining = remaining.substring(match.$2).trimLeft();
    }
  }

  return QuantityParseResult(quantity ?? 1.0, approximate, remaining);
}
