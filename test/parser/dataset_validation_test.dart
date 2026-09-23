import 'dart:convert';
import 'dart:io';

import 'package:a2/parser/catalogue/dataset_validator.dart';
import 'package:flutter_test/flutter_test.dart';

dynamic _readJson(String path) => json.decode(File(path).readAsStringSync());

void main() {
  const base = 'assets/parser';

  test('shipped parser datasets have no validation issues', () {
    final issues = validateParserDatasets(
      foodCatalogue:
          _readJson('$base/shared/food_catalogue.json') as List<dynamic>,
      foodAliases:
          _readJson('$base/en/food_aliases.json') as Map<String, dynamic>,
      taxonomyCategories:
          (_readJson('$base/shared/taxonomy_categories.json')
                  as Map<String, dynamic>)['categories']
              as List<dynamic>,
      activityCatalogue:
          _readJson('$base/shared/activity_catalogue.json') as List<dynamic>,
      activityAliases:
          _readJson('$base/en/activity_aliases.json') as Map<String, dynamic>,
      nutrients:
          _readJson('$base/shared/nutrition/nutrients.json') as List<dynamic>,
      portions: _readJson(
        '$base/shared/nutrition/food_portions.json',
      ) as List<dynamic>,
    );
    expect(issues, isEmpty, reason: issues.join('\n'));
  });

  test('validator actually catches a duplicate canonical id', () {
    final issues = validateParserDatasets(
      foodCatalogue: [
        {'id': 'apple', 'canonical': 'apple', 'category': 'fruit'},
        {'id': 'apple', 'canonical': 'apple again', 'category': 'fruit'},
      ],
      foodAliases: {
        'apple': ['apple'],
      },
      taxonomyCategories: ['fruit'],
      activityCatalogue: [],
      activityAliases: {},
      nutrients: [],
      portions: [],
    );
    expect(issues, contains('Duplicate food canonical id: apple'));
  });

  test('validator actually catches an alias collision', () {
    final issues = validateParserDatasets(
      foodCatalogue: [
        {'id': 'a', 'canonical': 'a', 'category': 'fruit'},
        {'id': 'b', 'canonical': 'b', 'category': 'fruit'},
      ],
      foodAliases: {
        'a': ['shared word'],
        'b': ['shared word'],
      },
      taxonomyCategories: ['fruit'],
      activityCatalogue: [],
      activityAliases: {},
      nutrients: [],
      portions: [],
    );
    expect(issues.any((i) => i.contains('shared word')), true);
  });

  test('validator catches a nutrient record referencing an unknown food', () {
    final issues = validateParserDatasets(
      foodCatalogue: [],
      foodAliases: {},
      taxonomyCategories: [],
      activityCatalogue: [],
      activityAliases: {},
      nutrients: [
        {
          'foodId': 'no_such_food',
          'kcalPer100g': 1,
          'proteinPer100g': 1,
          'carbsPer100g': 1,
          'source': 'test',
        },
      ],
      portions: [],
    );
    expect(
      issues,
      contains('nutrients.json references nonexistent food id: no_such_food'),
    );
  });
}
