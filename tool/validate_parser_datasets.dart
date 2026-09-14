import 'dart:convert';
import 'dart:io';

import 'package:a2/parser/catalogue/dataset_validator.dart';

dynamic _readJson(String path) => json.decode(File(path).readAsStringSync());

void main() {
  const base = 'assets/parser';
  final issues = validateParserDatasets(
    foodCatalogue: _readJson('$base/shared/food_catalogue.json') as List<dynamic>,
    foodAliases: _readJson('$base/en/food_aliases.json') as Map<String, dynamic>,
    taxonomyCategories:
        (_readJson('$base/shared/taxonomy_categories.json') as Map<String, dynamic>)['categories']
            as List<dynamic>,
    activityCatalogue: _readJson('$base/shared/activity_catalogue.json') as List<dynamic>,
    activityAliases: _readJson('$base/en/activity_aliases.json') as Map<String, dynamic>,
    nutrients: _readJson('$base/shared/nutrition/nutrients.json') as List<dynamic>,
    portions: _readJson('$base/shared/nutrition/food_portions.json') as List<dynamic>,
  );

  if (issues.isEmpty) {
    stdout.writeln('Parser datasets valid: no issues found.');
    exit(0);
  }

  stderr.writeln('Parser dataset validation found ${issues.length} issue(s):');
  for (final issue in issues) {
    stderr.writeln('  - $issue');
  }
  exit(1);
}
