import 'alias_index.dart';

const knownActivityCategories = {
  'athletics',
  'combat_sport',
  'cycling',
  'daily_activity',
  'dance',
  'fitness',
  'gym',
  'indoor_game',
  'outdoor',
  'racket_sport',
  'running',
  'swimming',
  'team_sport',
  'tennis',
  'walking',
  'water_sport',
  'winter_sport',
};

const validPortionConfidenceValues = {'high', 'medium', 'low'};

List<String> validateParserDatasets({
  required List<dynamic> foodCatalogue,
  required Map<String, dynamic> foodAliases,
  required List<dynamic> taxonomyCategories,
  required List<dynamic> activityCatalogue,
  required Map<String, dynamic> activityAliases,
  required List<dynamic> nutrients,
  required List<dynamic> portions,
}) {
  final issues = <String>[];

  final foodIds = <String>{};
  final taxonomy = taxonomyCategories.cast<String>().toSet();
  for (final raw in foodCatalogue) {
    final m = raw as Map<String, dynamic>;
    final id = m['id'] as String;
    if (!foodIds.add(id)) {
      issues.add('Duplicate food canonical id: $id');
    }
    final category = m['category'] as String;
    if (!taxonomy.contains(category)) {
      issues.add(
        'Food $id has category "$category" not in taxonomy_categories.json',
      );
    }
    final aliasesForId =
        (foodAliases[id] as List<dynamic>?)?.cast<String>() ?? const [];
    if (aliasesForId.isEmpty) {
      issues.add('Food $id has no aliases');
    }
  }
  for (final raw in foodCatalogue) {
    final m = raw as Map<String, dynamic>;
    final baseFood = m['base_food'] as String?;
    if (baseFood != null && !foodIds.contains(baseFood)) {
      issues.add(
        'Food ${m['id']} has base_food "$baseFood" which does not exist',
      );
    }
  }

  final foodAliasCollisions = AliasIndex.build(
    foodAliases.map((k, v) => MapEntry(k, (v as List<dynamic>).cast<String>())),
  ).collisions;
  for (final collision in foodAliasCollisions) {
    issues.add('Food alias collision: $collision');
  }

  final activityIds = <String>{};
  for (final raw in activityCatalogue) {
    final m = raw as Map<String, dynamic>;
    final id = m['id'] as String;
    if (!activityIds.add(id)) {
      issues.add('Duplicate activity canonical id: $id');
    }
    final category = m['category'] as String;
    if (!knownActivityCategories.contains(category)) {
      issues.add('Activity $id has unknown category "$category"');
    }
    final met = (m['met'] as num).toDouble();
    if (met <= 0 || met > 20) {
      issues.add('Activity $id has out-of-range MET value $met');
    }
    final aliasesForId =
        (activityAliases[id] as List<dynamic>?)?.cast<String>() ?? const [];
    if (aliasesForId.isEmpty) {
      issues.add('Activity $id has no aliases');
    }
  }

  final activityAliasCollisions = AliasIndex.build(
    activityAliases.map(
      (k, v) => MapEntry(k, (v as List<dynamic>).cast<String>()),
    ),
  ).collisions;
  for (final collision in activityAliasCollisions) {
    issues.add('Activity alias collision: $collision');
  }

  for (final raw in nutrients) {
    final m = raw as Map<String, dynamic>;
    final foodId = m['foodId'] as String;
    if (!foodIds.contains(foodId)) {
      issues.add('nutrients.json references nonexistent food id: $foodId');
    }
  }

  for (final raw in portions) {
    final m = raw as Map<String, dynamic>;
    final foodId = m['foodId'] as String?;
    if (foodId != null && !foodIds.contains(foodId)) {
      issues.add('food_portions.json references nonexistent food id: $foodId');
    }
    final confidence = m['confidence'] as String;
    if (!validPortionConfidenceValues.contains(confidence)) {
      issues.add(
        'food_portions.json has invalid confidence value: $confidence',
      );
    }
  }

  return issues;
}
