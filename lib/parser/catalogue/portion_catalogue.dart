import 'dart:convert';

import 'asset_reader.dart';

class PortionRule {
  const PortionRule({
    this.foodId,
    required this.foodNameAsGiven,
    required this.unit,
    required this.size,
    required this.grams,
    required this.confidence,
  });

  final String? foodId;
  final String foodNameAsGiven;
  final String unit;
  final String size;
  final double grams;
  final String confidence;
}

class PortionCatalogue {
  const PortionCatalogue(this.rules);
  final List<PortionRule> rules;

  PortionRule? lookup({required String foodId, required String unit, String? size}) {
    for (final rule in rules) {
      if (rule.foodId != foodId) continue;
      if (rule.unit != unit) continue;
      if (size != null && rule.size != size) continue;
      return rule;
    }
    return null;
  }

  static Future<PortionCatalogue> load({
    AssetReader reader = defaultAssetReader,
  }) async {
    final raw = await reader('assets/parser/shared/nutrition/food_portions.json');
    final list = json.decode(raw) as List<dynamic>;
    final rules = list.map((raw) {
      final m = raw as Map<String, dynamic>;
      return PortionRule(
        foodId: m['foodId'] as String?,
        foodNameAsGiven: m['foodNameAsGiven'] as String,
        unit: m['unit'] as String,
        size: m['size'] as String,
        grams: (m['grams'] as num).toDouble(),
        confidence: m['confidence'] as String,
      );
    }).toList();
    return PortionCatalogue(rules);
  }
}
