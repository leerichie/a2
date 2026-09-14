import 'package:a2/parser/exercise_parser.dart';
import 'package:a2/parser/models/parse_confidence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ExerciseParser parser;
  const weight = 70.0;

  setUpAll(() async {
    parser = await ExerciseParser.load();
  });

  // Every fixture from exercise_activity/exercise_parser_tests.json, plus
  // the calorie estimate (met * bodyWeightKg * hours) that fixture doesn't
  // itself assert (it predates the MET-based calculation being wired up).
  group('exercise_parser_tests.json fixtures', () {
    test('20 min HIIT', () {
      final r = parser.parse('20 min HIIT', bodyWeightKg: weight);
      expect(r.activityId, 'hiit');
      expect(r.durationMinutes, 20);
      expect(r.intensity, 'vigorous');
      expect(r.calorieEstimateKcal, closeTo(210, 0.01));
      expect(r.confidence, ParseConfidence.high);
    });

    test('2 hours tennis singles', () {
      final r = parser.parse('2 hours tennis singles', bodyWeightKg: weight);
      expect(r.activityId, 'singles_tennis');
      expect(r.durationMinutes, 120);
      expect(r.calorieEstimateKcal, closeTo(1120, 0.01));
    });

    test('90 mins doubles tennis', () {
      final r = parser.parse('90 mins doubles tennis', bodyWeightKg: weight);
      expect(r.activityId, 'doubles_tennis');
      expect(r.durationMinutes, 90);
      expect(r.calorieEstimateKcal, closeTo(630, 0.01));
    });

    test('half an hour brisk walking', () {
      final r = parser.parse('half an hour brisk walking', bodyWeightKg: weight);
      expect(r.activityId, 'brisk_walking');
      expect(r.durationMinutes, 30);
      expect(r.calorieEstimateKcal, closeTo(168, 0.01));
    });

    test('45 min easy cycling', () {
      final r = parser.parse('45 min easy cycling', bodyWeightKg: weight);
      expect(r.activityId, 'easy_cycling');
      expect(r.durationMinutes, 45);
      expect(r.intensity, 'light');
      expect(r.calorieEstimateKcal, closeTo(210, 0.01));
    });

    test('1h vigorous swimming', () {
      final r = parser.parse('1h vigorous swimming', bodyWeightKg: weight);
      expect(r.activityId, 'vigorous_swimming');
      expect(r.durationMinutes, 60);
      expect(r.intensity, 'vigorous');
      expect(r.calorieEstimateKcal, closeTo(686, 0.01));
    });

    test('30 minutes weights', () {
      final r = parser.parse('30 minutes weights', bodyWeightKg: weight);
      expect(r.activityId, 'weight_training');
      expect(r.durationMinutes, 30);
      expect(r.calorieEstimateKcal, closeTo(122.5, 0.01));
    });

    test('15 min stair climbing', () {
      final r = parser.parse('15 min stair climbing', bodyWeightKg: weight);
      expect(r.activityId, 'stairs');
      expect(r.durationMinutes, 15);
      expect(r.calorieEstimateKcal, closeTo(140, 0.01));
    });

    test('about 40 min gardening -- approximate downgrades to low', () {
      final r = parser.parse('about 40 min gardening', bodyWeightKg: weight);
      expect(r.activityId, 'gardening');
      expect(r.durationMinutes, 40);
      expect(r.approximate, true);
      expect(r.calorieEstimateKcal, closeTo(186.67, 0.01));
      expect(r.confidence, ParseConfidence.low);
    });
  });

  test('missing body weight -> incomplete, never a guessed calorie number', () {
    final r = parser.parse('20 min HIIT', bodyWeightKg: null);
    expect(r.activityId, 'hiit');
    expect(r.calorieEstimateKcal, null);
    expect(r.confidence, ParseConfidence.incomplete);
  });

  test('unresolved activity', () {
    final r = parser.parse('30 min underwater basket weaving', bodyWeightKg: weight);
    expect(r.activityId, null);
    expect(r.confidence, ParseConfidence.incomplete);
  });
}
