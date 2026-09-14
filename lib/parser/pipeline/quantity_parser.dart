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

QuantityParseResult parseQuantity(String text, Lexicon lexicon) {
  var remaining = text.trimLeft();
  var approximate = false;
  double? quantity;

  final approxTable = PhraseTable({for (final w in lexicon.approximationWords) w: true});
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
