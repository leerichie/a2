import 'dart:convert';

import 'asset_reader.dart';

/// One ingredient inside a [Recipe], at the quantity/unit that makes up a
/// typical default serving -- resolved through the SAME portion/nutrition
/// catalogues as if it had been typed on its own, so a recipe never carries
/// its own invented numbers, only a composition of already-real ones.
class RecipeIngredient {
  const RecipeIngredient({required this.foodId, required this.quantity, this.unit});
  final String foodId;
  final double quantity;
  // Null means the ingredient's own bare-mention default portion.
  final String? unit;
}

/// A prepared/composite dish's default recipe (e.g. "egg salad" = a boiled
/// egg + a teaspoon of mayonnaise) -- used only to fill in a *bare* mention
/// of the dish (see FoodParser.load), never to override an explicit
/// quantity/measurement the user actually typed.
class Recipe {
  const Recipe({required this.foodId, required this.ingredients, this.source});
  final String foodId;
  final List<RecipeIngredient> ingredients;
  final String? source;
}

class RecipeCatalogue {
  const RecipeCatalogue(this.recipes);
  final List<Recipe> recipes;

  static Future<RecipeCatalogue> load({
    AssetReader reader = defaultAssetReader,
  }) async {
    final raw = await reader('assets/parser/shared/nutrition/food_recipes.json');
    final list = json.decode(raw) as List<dynamic>;
    final recipes = list.map((raw) {
      final m = raw as Map<String, dynamic>;
      final ingredients = (m['ingredients'] as List<dynamic>).map((raw) {
        final i = raw as Map<String, dynamic>;
        return RecipeIngredient(
          foodId: i['foodId'] as String,
          quantity: (i['quantity'] as num).toDouble(),
          unit: i['unit'] as String?,
        );
      }).toList();
      return Recipe(
        foodId: m['foodId'] as String,
        ingredients: ingredients,
        source: m['source'] as String?,
      );
    }).toList();
    return RecipeCatalogue(recipes);
  }
}
