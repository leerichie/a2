/// Explicit metric measurements (grams/kilograms/millilitres/litres). The
/// household-portion lexicon doesn't enumerate bare metric abbreviations, so
/// this stage uses its own regex, the same way `FoodEstimator` already does
/// today -- just centralized here instead of duplicated per call site.
class MeasurementParseResult {
  const MeasurementParseResult({
    this.grams,
    this.millilitres,
    required this.remainder,
  });
  final double? grams;
  final double? millilitres;
  final String remainder;
}

final _measurementPattern = RegExp(
  r'^(\d+(?:\.\d+)?)\s*(kilograms?|kg|grams?|g|millilitres?|milliliters?|ml|litres?|liters?|l)\b',
);

MeasurementParseResult parseMeasurement(String text) {
  final remaining = text.trimLeft();
  final match = _measurementPattern.firstMatch(remaining);
  if (match == null) {
    return MeasurementParseResult(remainder: remaining);
  }
  final value = double.parse(match.group(1)!);
  final unit = match.group(2)!;
  final rest = remaining.substring(match.end).trimLeft();
  if (unit.startsWith('kg') || unit.startsWith('kilogram')) {
    return MeasurementParseResult(grams: value * 1000, remainder: rest);
  }
  if (unit.startsWith('g') || unit.startsWith('gram')) {
    return MeasurementParseResult(grams: value, remainder: rest);
  }
  if (unit.startsWith('l') ||
      unit.startsWith('litre') ||
      unit.startsWith('liter')) {
    return MeasurementParseResult(millilitres: value * 1000, remainder: rest);
  }
  return MeasurementParseResult(millilitres: value, remainder: rest);
}
