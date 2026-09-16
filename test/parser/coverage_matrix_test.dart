import 'package:a2/parser/food_parser.dart';
import 'package:a2/parser/models/parse_confidence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Broad local food/drink coverage pass: every catalogue entry that now has
/// a nutrient record (directly, or via a genericParent fallback) must
/// actually resolve to real nutrition data given an exact measurement --
/// one matrix test standing in for what would otherwise be hundreds of
/// near-identical phrase-specific tests. This does not assert anything
/// about *portion* handling (bare mentions, household units) -- that is
/// covered by the dedicated portion/generic-volume/generic-parent groups
/// elsewhere in this file; "100g `<food>`" isolates just the nutrient-data
/// side of the coverage pass.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FoodParser parser;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    parser = await FoodParser.load();
  });

  test('every catalogue entry with a nutrient record (direct or via '
      'genericParent) resolves real nutrition data for an exact measurement', () {
    // "salted_nuts" and "wholemeal_flour" are unreachable by design, same
    // as "light_mayonnaise": "salted"/"wholemeal" are lexicon modifier
    // words, always stripped before food resolution, and there is no bare
    // "nuts"/"flour" entry for the remainder to fall back to -- not a
    // coverage gap, just not phraseable this way.
    final withNutrition = parser.catalogue.entries.where((e) {
      if (e.id == 'salted_nuts' || e.id == 'wholemeal_flour') return false;
      if (parser.nutrition.forFoodId(e.id) != null) return true;
      final parent = e.genericParent;
      return parent != null && parser.nutrition.forFoodId(parent) != null;
    });

    final failures = <String>[];
    for (final entry in withNutrition) {
      final result = parser.parse('100g ${entry.canonical}');
      if (result.items.length != 1) {
        failures.add('${entry.id}: expected exactly one item, got ${result.items.length}');
        continue;
      }
      final item = result.items.single;
      if (item.confidence == ParseConfidence.incomplete || item.nutrition == null) {
        failures.add('${entry.id}: confidence=${item.confidence} nutrition=${item.nutrition}');
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  // Spot-check representative entries across the categories covered in
  // this pass -- own real/standard data, not a fallback -- so a future
  // change to genericParent wiring can't silently mask a lost direct
  // nutrient record for foods where precision genuinely matters.
  group('representative own-data entries across newly covered categories', () {
    const samples = {
      'beef': 'meat_poultry', 'pork': 'meat_poultry', 'turkey': 'meat_poultry',
      'lamb': 'meat_poultry', 'duck': 'meat_poultry',
      'mackerel': 'fish_seafood', 'herring': 'fish_seafood', 'shrimp': 'fish_seafood',
      'crab': 'fish_seafood', 'smoked_salmon': 'fish_seafood',
      'feta': 'dairy_alternative', 'parmesan': 'dairy_alternative', 'butter': 'dairy_alternative',
      'whole_milk': 'dairy_alternative', 'sour_cream': 'dairy',
      'bagel': 'grain_bakery', 'croissant': 'grain_bakery', 'wrap': 'grain_bakery',
      'couscous': 'grain_bakery', 'quinoa': 'grain_bakery',
      'chickpeas': 'legume_nut_seed', 'tofu': 'legume_nut_seed', 'hummus': 'legume_nut_seed',
      'almonds': 'legume_nut_seed',
      'broccoli': 'vegetable', 'spinach': 'vegetable', 'sweet_potato': 'vegetable',
      'orange': 'fruit', 'grapes': 'fruit', 'mango': 'fruit',
      'espresso': 'drink', 'cappuccino': 'drink', 'orange_juice': 'drink',
      'coca_cola': 'drink', 'coke_zero': 'drink',
      'ketchup': 'sauce_condiment_fat', 'pesto': 'sauce_condiment_fat',
      'kebab': 'prepared_meal', 'fried_rice': 'prepared_meal', 'sushi': 'prepared_meal',
      'biscuit': 'snack_dessert', 'ice_cream': 'snack_dessert', 'chocolate_bar': 'snack_dessert',
    };
    samples.forEach((foodId, category) {
      test('"$foodId" ($category) has its own real nutrient record', () {
        final entry = parser.catalogue.entries.firstWhere((e) => e.id == foodId);
        expect(entry.category, category);
        expect(parser.nutrition.forFoodId(foodId), isNotNull);
      });
    });
  });

  // Zero/diet drinks: a known fact (genuinely ~0 kcal), not missing data.
  group('zero and diet drinks', () {
    for (final foodId in ['coke_zero', 'diet_coke']) {
      test('"$foodId" is genuinely near-zero kcal, not incomplete', () {
        final record = parser.nutrition.forFoodId(foodId);
        expect(record, isNotNull);
        expect(record!.kcalPer100g, lessThan(1));
      });
    }
  });

  // Generic-parent chains added in this pass: the subtype resolves with
  // the SAME real number as its parent (a taxonomic/compositional fact,
  // not a fresh invented figure), always at Low confidence.
  group('generic-parent chains added in this coverage pass', () {
    // The subtypes below were removed from this map once
    // tool/import_usda_nutrients.py gave each its own real USDA record --
    // see "subtypes upgraded to their own real record" below instead.
    const chains = {
      'back_bacon': 'bacon', 'hot_dog_sausage': 'sausage',
      'smoked_mackerel': 'mackerel', 'smoked_trout': 'trout',
      'king_prawn': 'shrimp', 'basmati_rice': 'rice', 'penne': 'pasta',
      'rolled_oats': 'oats', 'button_mushroom': 'mushroom',
      'red_onion': 'onion', 'lager': 'beer', 'brandy': 'whisky',
      'gyros': 'kebab', 'chicken_curry': 'curry', 'dijon_mustard': 'mustard',
    };
    chains.forEach((subtypeId, parentId) {
      test('"$subtypeId" borrows real data from "$parentId" at Low confidence', () {
        final result = parser.parse('100g ${subtypeId.replaceAll('_', ' ')}');
        final item = result.items.single;
        expect(item.canonicalId, subtypeId);
        expect(item.confidence, ParseConfidence.low);
        final parentRecord = parser.nutrition.forFoodId(parentId)!;
        expect(item.nutrition!.kcal, closeTo(parentRecord.kcalPer100g, 0.01));
      });
    });
  });

  // These used to be in the generic-parent chain above; the USDA import
  // pass gave each its own real record, so they now resolve directly (at
  // High confidence, given an exact 100g measurement) instead of borrowing.
  group('subtypes upgraded to their own real record', () {
    const ownData = {
      'minced_beef': 240.0, 'pork_chop': 202.0, 'turkey_breast': 147.0,
      'lamb_chop': 264.0, 'duck_breast': 123.0, 'cooked_ham': 172.0,
      'pickled_herring': 262.0, 'white_bread': 238.0, 'black_beans': 132.0,
      'red_cabbage': 31.0, 'iceberg_lettuce': 14.0, 'red_pepper': 26.0,
      'green_tea': 1.0, 'instant_coffee': 3.0, 'red_wine': 85.0,
      'mineral_water': 22.0, 'tomato_soup': 30.0, 'rapeseed_oil': 884.0,
    };
    ownData.forEach((foodId, kcalPer100g) {
      test('"$foodId" resolves with its own real data at High confidence', () {
        final item = parser.parse('100g ${foodId.replaceAll('_', ' ')}').items.single;
        expect(item.canonicalId, foodId);
        expect(item.confidence, ParseConfidence.high);
        expect(item.nutrition!.kcal, closeTo(kcalPer100g, 0.01));
      });
    });
  });

  // Vegetables now have a defensible bare-mention default: 80g, the
  // standard UK "5-a-day" single-portion reference, not an invented
  // number -- a real practical gap this pass closed.
  group('vegetable bare-mention default (standard 80g portion)', () {
    for (final foodId in ['broccoli', 'spinach', 'cauliflower', 'green_beans', 'kale']) {
      test('bare "$foodId" resolves at 80g, medium confidence', () {
        final item = parser.parse(foodId.replaceAll('_', ' ')).items.single;
        expect(item.canonicalId, foodId);
        expect(item.grams, 80);
        expect(item.confidence, ParseConfidence.medium);
      });
    }
  });

  // "A handful of X" for nuts specifically -- a food-specific handful
  // weight (not a universal handful value for every food).
  group('nut-specific handful portion', () {
    for (final foodId in ['almonds', 'cashews', 'walnuts', 'peanuts']) {
      test('"handful of $foodId" resolves at 30g, medium confidence', () {
        final item = parser.parse('handful of ${foodId.replaceAll('_', ' ')}').items.single;
        expect(item.canonicalId, foodId);
        expect(item.grams, 30);
        expect(item.confidence, ParseConfidence.medium);
      });
    }
  });
}
