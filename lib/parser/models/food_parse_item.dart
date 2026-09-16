import 'nutrient_totals.dart';
import 'parse_confidence.dart';
import 'unresolved_span.dart';

class FoodParseItem {
  const FoodParseItem({
    required this.quantity,
    this.approximate = false,
    this.unit,
    this.size,
    this.fullness,
    this.canonicalId,
    this.canonicalName,
    this.category,
    this.matchedAlias,
    this.modifiers = const [],
    this.preparations = const [],
    this.grams,
    this.nutrition,
    required this.confidence,
    this.suggestions = const [],
  });

  final double quantity;
  final bool approximate;
  final String? unit;
  final String? size;
  final String? fullness;
  final String? canonicalId;
  final String? canonicalName;
  // The catalogue's taxonomic category ("drink", "vegetable", ...) --
  // lets a caller distinguish a drink-only entry from a mixed meal
  // without re-parsing the description text itself.
  final String? category;
  final String? matchedAlias;
  final List<String> modifiers;
  final List<String> preparations;
  final double? grams;
  final NutrientTotals? nutrition;
  final ParseConfidence confidence;
  final List<String> suggestions;
}

class FoodParseResult {
  const FoodParseResult(this.items, this.unresolved);
  final List<FoodParseItem> items;
  final List<UnresolvedSpan> unresolved;
}
