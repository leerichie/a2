import '../catalogue/lexicon.dart';
import 'token_matching.dart';

class DurationParseResult {
  const DurationParseResult({this.minutes, required this.approximate, required this.remainder});
  final double? minutes;
  final bool approximate;
  final String remainder;
}

final _numberThenUnit = RegExp(r'^(\d+(?:\.\d+)?)\s*');

DurationParseResult parseDuration(String text, Lexicon lexicon) {
  var remaining = text.trimLeft();
  var approximate = false;

  final approxTable = PhraseTable({for (final w in lexicon.approximationWords) w: true});
  while (true) {
    final match = approxTable.matchAtStart(remaining);
    if (match == null) break;
    approximate = true;
    remaining = remaining.substring(match.$2).trimLeft();
  }

  final phraseTable = PhraseTable(lexicon.durationPhraseMinutes);
  final phraseMatch = phraseTable.matchAtStart(remaining);
  if (phraseMatch != null) {
    return DurationParseResult(
      minutes: phraseMatch.$1,
      approximate: approximate,
      remainder: remaining.substring(phraseMatch.$2).trimLeft(),
    );
  }

  final numberMatch = _numberThenUnit.firstMatch(remaining);
  if (numberMatch != null) {
    final afterNumber = remaining.substring(numberMatch.end);
    final unitTable = PhraseTable(lexicon.timeUnitByAlias);
    final unitMatch = unitTable.matchAtStart(afterNumber);
    if (unitMatch != null) {
      final value = double.parse(numberMatch.group(1)!);
      final minutes = switch (unitMatch.$1) {
        'hour' => value * 60,
        'second' => value / 60,
        _ => value,
      };
      return DurationParseResult(
        minutes: minutes,
        approximate: approximate,
        remainder: afterNumber.substring(unitMatch.$2).trimLeft(),
      );
    }
  }

  return DurationParseResult(minutes: null, approximate: approximate, remainder: remaining);
}
