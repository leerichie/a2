import 'dart:convert';

import 'asset_reader.dart';

class NutrientRecord {
  const NutrientRecord({
    required this.foodId,
    required this.kcalPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    this.fatPer100g,
    this.fibrePer100g,
    required this.source,
    this.sourceId,
  });

  final String foodId;
  final double kcalPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double? fatPer100g;
  final double? fibrePer100g;
  final String source;
  // The upstream dataset's own record id (e.g. a USDA FoodData Central
  // fdc_id) for traceability -- not read by the parser at runtime.
  final String? sourceId;
}

class NutritionCatalogue {
  const NutritionCatalogue(this._byFoodId);
  final Map<String, NutrientRecord> _byFoodId;

  NutrientRecord? forFoodId(String foodId) => _byFoodId[foodId];

  static Future<NutritionCatalogue> load({
    AssetReader reader = defaultAssetReader,
  }) async {
    final raw = await reader('assets/parser/shared/nutrition/nutrients.json');
    final list = json.decode(raw) as List<dynamic>;
    final byId = <String, NutrientRecord>{};
    for (final raw in list) {
      final m = raw as Map<String, dynamic>;
      final record = NutrientRecord(
        foodId: m['foodId'] as String,
        kcalPer100g: (m['kcalPer100g'] as num).toDouble(),
        proteinPer100g: (m['proteinPer100g'] as num).toDouble(),
        carbsPer100g: (m['carbsPer100g'] as num).toDouble(),
        fatPer100g: (m['fatPer100g'] as num?)?.toDouble(),
        fibrePer100g: (m['fibrePer100g'] as num?)?.toDouble(),
        source: m['source'] as String,
        sourceId: m['sourceId'] as String?,
      );
      byId[record.foodId] = record;
    }
    return NutritionCatalogue(byId);
  }
}
