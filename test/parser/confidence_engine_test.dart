import 'package:a2/parser/models/parse_confidence.dart';
import 'package:a2/parser/pipeline/confidence_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('deriveFoodConfidence', () {
    test('high: exact entity + exact measurement + nutrient data', () {
      final c = deriveFoodConfidence(
        foodResolved: true,
        hasUnresolvedText: false,
        nutrientDataAvailable: true,
        gramsKnown: true,
        exactMeasurementGiven: true,
        approximate: false,
      );
      expect(c, ParseConfidence.high);
    });

    test('medium: recognized food + a food-specific portion rule, no exact measurement', () {
      final c = deriveFoodConfidence(
        foodResolved: true,
        hasUnresolvedText: false,
        nutrientDataAvailable: true,
        gramsKnown: true,
        exactMeasurementGiven: false,
        approximate: false,
        portionRuleConfidence: 'medium',
      );
      expect(c, ParseConfidence.medium);
    });

    test('low: approximation wording downgrades an otherwise-high result', () {
      final c = deriveFoodConfidence(
        foodResolved: true,
        hasUnresolvedText: false,
        nutrientDataAvailable: true,
        gramsKnown: true,
        exactMeasurementGiven: true,
        approximate: true,
      );
      expect(c, ParseConfidence.low);
    });

    test('low: the portion rule itself is authored as low-confidence', () {
      final c = deriveFoodConfidence(
        foodResolved: true,
        hasUnresolvedText: false,
        nutrientDataAvailable: true,
        gramsKnown: true,
        exactMeasurementGiven: false,
        approximate: false,
        portionRuleConfidence: 'low',
      );
      expect(c, ParseConfidence.low);
    });

    test('incomplete: food unresolved', () {
      final c = deriveFoodConfidence(
        foodResolved: false,
        hasUnresolvedText: false,
        nutrientDataAvailable: false,
        gramsKnown: false,
        exactMeasurementGiven: false,
        approximate: false,
      );
      expect(c, ParseConfidence.incomplete);
    });

    test('incomplete: food recognized but no nutrient record exists', () {
      final c = deriveFoodConfidence(
        foodResolved: true,
        hasUnresolvedText: false,
        nutrientDataAvailable: false,
        gramsKnown: true,
        exactMeasurementGiven: true,
        approximate: false,
      );
      expect(c, ParseConfidence.incomplete);
    });

    test('incomplete: nutrient data exists but grams cannot be determined -- never guessed', () {
      final c = deriveFoodConfidence(
        foodResolved: true,
        hasUnresolvedText: false,
        nutrientDataAvailable: true,
        gramsKnown: false,
        exactMeasurementGiven: false,
        approximate: false,
      );
      expect(c, ParseConfidence.incomplete);
    });
  });

  group('deriveExerciseConfidence', () {
    test('high: activity + duration + body weight all present, not approximate', () {
      final c = deriveExerciseConfidence(
        activityResolved: true,
        durationKnown: true,
        bodyWeightKnown: true,
        approximate: false,
      );
      expect(c, ParseConfidence.high);
    });

    test('low: approximate duration downgrades', () {
      final c = deriveExerciseConfidence(
        activityResolved: true,
        durationKnown: true,
        bodyWeightKnown: true,
        approximate: true,
      );
      expect(c, ParseConfidence.low);
    });

    test('incomplete: missing duration', () {
      final c = deriveExerciseConfidence(
        activityResolved: true,
        durationKnown: false,
        bodyWeightKnown: true,
        approximate: false,
      );
      expect(c, ParseConfidence.incomplete);
    });

    test('incomplete: missing body weight', () {
      final c = deriveExerciseConfidence(
        activityResolved: true,
        durationKnown: true,
        bodyWeightKnown: false,
        approximate: false,
      );
      expect(c, ParseConfidence.incomplete);
    });

    test('incomplete: unresolved activity', () {
      final c = deriveExerciseConfidence(
        activityResolved: false,
        durationKnown: true,
        bodyWeightKnown: true,
        approximate: false,
      );
      expect(c, ParseConfidence.incomplete);
    });
  });
}
