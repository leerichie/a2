import 'parse_confidence.dart';

class ExerciseParseItem {
  const ExerciseParseItem({
    this.activityId,
    this.canonicalActivity,
    this.matchedAlias,
    required this.durationMinutes,
    this.intensity,
    this.met,
    this.approximate = false,
    this.calorieEstimateKcal,
    required this.confidence,
    this.suggestions = const [],
  });

  final String? activityId;
  final String? canonicalActivity;
  final String? matchedAlias;
  final double? durationMinutes;
  final String? intensity;
  final double? met;
  final bool approximate;
  final double? calorieEstimateKcal;
  final ParseConfidence confidence;
  final List<String> suggestions;
}
