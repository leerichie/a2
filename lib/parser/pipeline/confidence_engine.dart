import '../models/parse_confidence.dart';

/// High: exact entity + exact measurement (explicit grams/ml) + nutrient data.
/// Medium: recognized food + a food-specific unit-to-grams conversion exists.
/// Low: the above, but either the portion rule itself is authored as
/// low-confidence, or the phrase used an approximation word ("about",
/// "roughly", ...) -- approximation should lower confidence, not vanish.
/// Incomplete: unresolved food, leftover meaningful text, no nutrient
/// record for the resolved food, or no way to determine grams at all.
/// Per explicit instruction: never invent a default gram value to avoid
/// landing here -- a food with no usable portion data IS Incomplete.
ParseConfidence deriveFoodConfidence({
  required bool foodResolved,
  required bool hasUnresolvedText,
  required bool nutrientDataAvailable,
  required bool gramsKnown,
  required bool exactMeasurementGiven,
  required bool approximate,
  String? portionRuleConfidence,
}) {
  if (!foodResolved || hasUnresolvedText) return ParseConfidence.incomplete;
  if (!nutrientDataAvailable) return ParseConfidence.incomplete;
  if (!gramsKnown) return ParseConfidence.incomplete;
  if (approximate || portionRuleConfidence == 'low') return ParseConfidence.low;
  if (exactMeasurementGiven) return ParseConfidence.high;
  return ParseConfidence.medium;
}

/// High: activity resolved (MET known) + duration + body weight all present.
/// Low: same, but the phrase was approximate ("about 40 min gardening").
/// Incomplete: unresolved activity, missing duration, or missing body weight
/// -- exercise calories are always an estimate (MET formula), but that
/// caveat belongs in how the number is presented, not as a fourth level.
ParseConfidence deriveExerciseConfidence({
  required bool activityResolved,
  required bool durationKnown,
  required bool bodyWeightKnown,
  required bool approximate,
}) {
  if (!activityResolved || !durationKnown || !bodyWeightKnown) {
    return ParseConfidence.incomplete;
  }
  return approximate ? ParseConfidence.low : ParseConfidence.high;
}
