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
  // Null means "no unit was given at all" -- a bare-mention default portion
  // ("egg", "banana"), distinct from a rule that applies to a specific
  // household unit.
  final String? unit;
  final String? size;
  final double grams;
  final String confidence;
}

class PortionCatalogue {
  const PortionCatalogue(this.rules);
  final List<PortionRule> rules;

  /// Pass `unit: null` to look up the bare-mention default portion for a
  /// food (no household unit/measurement was present in the text at all).
  PortionRule? lookup({required String foodId, required String? unit, String? size}) {
    for (final rule in rules) {
      if (rule.foodId != foodId) continue;
      if (rule.unit != unit) continue;
      if (size != null && rule.size != null && rule.size != size) continue;
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
        unit: m['unit'] as String?,
        size: m['size'] as String?,
        grams: (m['grams'] as num).toDouble(),
        confidence: m['confidence'] as String,
      );
    }).toList();
    return PortionCatalogue(rules);
  }
}

/// Standard container volumes for drinks ("glass"/"bottle"/...), reused
/// from the same numbers already live in `WaterIntakeParser` rather than
/// invented fresh -- and deliberately NOT scaled by size words ("large
/// glass"), since no established ratio exists anywhere in this app.
class DrinkContainerCatalogue {
  const DrinkContainerCatalogue(this._mlByUnit);
  final Map<String, double> _mlByUnit;

  double? millilitresFor(String unit) => _mlByUnit[unit];

  static Future<DrinkContainerCatalogue> load({
    AssetReader reader = defaultAssetReader,
  }) async {
    final raw = await reader('assets/parser/shared/nutrition/drink_container_ml.json');
    final map = json.decode(raw) as Map<String, dynamic>;
    return DrinkContainerCatalogue(
      map.map((k, v) => MapEntry(k, (v as num).toDouble())),
    );
  }
}

class GenericVolumeEntry {
  const GenericVolumeEntry({required this.ml, required this.confidence});
  final double ml;
  final String confidence;
}

/// Density-neutral ml-as-grams conversion for standard-volume units
/// (teaspoon/tablespoon/dessertspoon/cup/fluid_ounce, plus "spoonful" as a
/// deliberate low-confidence addition) applicable to ANY food, not just
/// drinks -- the same simplification already used for drinks, generalized.
/// Deliberately NOT extended to vague `approx_household` units (bowl,
/// handful, scoop, ...); the source dataset explicitly warns against a
/// universal gram value for those.
class GenericVolumeCatalogue {
  const GenericVolumeCatalogue(this._byUnit);
  final Map<String, GenericVolumeEntry> _byUnit;

  GenericVolumeEntry? lookup(String unit) => _byUnit[unit];

  static Future<GenericVolumeCatalogue> load({
    AssetReader reader = defaultAssetReader,
  }) async {
    final raw = await reader('assets/parser/shared/nutrition/generic_volume_ml.json');
    final map = json.decode(raw) as Map<String, dynamic>;
    return GenericVolumeCatalogue(
      map.map((k, v) {
        final m = v as Map<String, dynamic>;
        return MapEntry(
          k,
          GenericVolumeEntry(
            ml: (m['ml'] as num).toDouble(),
            confidence: m['confidence'] as String,
          ),
        );
      }),
    );
  }
}
