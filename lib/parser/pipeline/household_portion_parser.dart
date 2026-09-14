import '../catalogue/lexicon.dart';
import 'token_matching.dart';

class HouseholdPortionResult {
  const HouseholdPortionResult({this.unit, required this.remainder});
  final String? unit;
  final String remainder;
}

HouseholdPortionResult parseHouseholdPortion(String text, Lexicon lexicon) {
  final remaining = consumeConnectorsAndWhitespace(text, lexicon.connectorWords);
  final table = PhraseTable(lexicon.unitByAlias);
  final match = table.matchAtStart(remaining);
  if (match == null) {
    return HouseholdPortionResult(remainder: remaining);
  }
  return HouseholdPortionResult(
    unit: match.$1,
    remainder: consumeConnectorsAndWhitespace(
      remaining.substring(match.$2),
      lexicon.connectorWords,
    ),
  );
}
