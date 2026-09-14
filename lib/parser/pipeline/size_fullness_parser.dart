import '../catalogue/lexicon.dart';
import 'token_matching.dart';

class SizeFullnessResult {
  const SizeFullnessResult({this.size, this.fullness, required this.remainder});
  final String? size;
  final String? fullness;
  final String remainder;
}

/// Matches at most one size word and one fullness word, in whichever order
/// they appear, each optionally preceded by connector words ("a", "of").
SizeFullnessResult parseSizeAndFullness(String text, Lexicon lexicon) {
  var remaining = consumeConnectorsAndWhitespace(text, lexicon.connectorWords);
  String? size;
  String? fullness;

  for (var i = 0; i < 2; i++) {
    if (size == null) {
      final sizeTable = PhraseTable(lexicon.sizeByAlias);
      final match = sizeTable.matchAtStart(remaining);
      if (match != null) {
        size = match.$1;
        remaining = consumeConnectorsAndWhitespace(
          remaining.substring(match.$2),
          lexicon.connectorWords,
        );
        continue;
      }
    }
    if (fullness == null) {
      final fullnessTable = PhraseTable(lexicon.fullnessByAlias);
      final match = fullnessTable.matchAtStart(remaining);
      if (match != null) {
        fullness = match.$1;
        remaining = consumeConnectorsAndWhitespace(
          remaining.substring(match.$2),
          lexicon.connectorWords,
        );
        continue;
      }
    }
    break;
  }

  return SizeFullnessResult(size: size, fullness: fullness, remainder: remaining);
}
