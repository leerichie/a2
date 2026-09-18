// Milestone: FoodEstimator -> canonical catalogue nutrient/portion
// migration. One parameterized matrix per concern rather than dozens of
// near-identical hand-written cases.
import 'package:a2/parser/food_parser.dart';
import 'package:a2/parser/models/parse_confidence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FoodParser parser;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    parser = await FoodParser.load();
  });

  // Every solid food safely migrated from FoodEstimator: canonical id ->
  // (kcal/100g, defaultGrams), verbatim from lib/main.dart's `foods` map.
  // A bare mention (no unit) must now resolve to a real number via the
  // food-specific default-grams portion rule, at medium confidence (never
  // high -- no exact measurement was actually given).
  const migratedSolidFoods = {
    'oats': (389, 40), 'peach': (39, 100), 'plum': (46, 80),
    'crisps': (520, 25), 'raisins': (300, 30), 'coleslaw': (150, 70),
    'ham': (145, 60), 'bacon': (450, 40), 'sausage': (300, 100),
    'bread': (265, 40), 'banana': (89, 120), 'apple': (52, 150),
    'chicken': (165, 150), 'salmon': (208, 150), 'trout': (148, 150),
    'tuna': (132, 120), 'cod': (105, 150), 'rice': (130, 180),
    'pasta': (158, 180), 'potato': (87, 180), 'cheese': (350, 30),
    'avocado': (160, 100), 'mushroom': (22, 60), 'tomato': (18, 100),
    'onion': (40, 50), 'carrot': (41, 80), 'bell_pepper': (31, 60),
    'gherkin': (12, 50), 'cabbage': (25, 100), 'lettuce': (15, 60),
    'salad': (60, 100), 'vinegar': (18, 15), 'beans': (127, 150),
    'soup': (55, 250), 'milk': (50, 150), 'egg': (143, 60),
    'yoghurt': (80, 100), 'cottage_cheese': (98, 60),
  };

  group('bare mentions resolve via the food-specific default-grams portion', () {
    migratedSolidFoods.forEach((id, expected) {
      final (kcalPer100g, defaultGrams) = expected;
      final phrase = id.replaceAll('_', ' '); // canonical ids are lowercase_snake; the word people type has spaces
      test('bare "$phrase" -> $defaultGrams g, ${kcalPer100g}kcal/100g, medium confidence', () {
        final item = parser.parse(phrase).items.single;
        expect(item.canonicalId, id);
        expect(item.grams, defaultGrams.toDouble(), reason: id);
        expect(item.nutrition, isNotNull, reason: id);
        expect(
          item.nutrition!.kcal,
          closeTo(kcalPer100g * defaultGrams / 100, 0.05),
          reason: id,
        );
        expect(item.confidence, ParseConfidence.medium, reason: id);
      });

      test('quantity scales the default for "$phrase" (2x)', () {
        final item = parser.parse('2 $phrase').items.single;
        expect(item.grams, defaultGrams * 2, reason: id);
      });

      test('an explicit gram amount overrides the default for "$phrase" -> high', () {
        final item = parser.parse('200g $phrase').items.single;
        expect(item.grams, 200, reason: id);
        expect(item.confidence, ParseConfidence.high, reason: id);
      });
    });
  });

  // Drinks migrated from FoodEstimator's `drinks` map (per 100ml). No
  // bare-mention default is added for spirits/wine -- container sizes
  // (shot/double/glass/bottle) vary too widely to guess. Beer is the
  // deliberate exception (2026-09-18): unlike a "wine"/"whisky" mention, a
  // bare beer/piwo mention defaults like cola's can/glass serving does --
  // see its own group below.
  const migratedDrinks = {
    'whisky': 220, 'vodka': 220, 'gin': 220, 'rum': 220, 'wine': 83,
  };

  group('drinks have real nutrient data but no invented default measure', () {
    migratedDrinks.forEach((id, kcalPer100ml) {
      test('bare "$id" has nutrient data available but stays incomplete '
          '(no measure given, no default invented)', () {
        final item = parser.parse(id).items.single;
        expect(item.canonicalId, id);
        expect(item.grams, null, reason: id);
        expect(item.confidence, ParseConfidence.incomplete, reason: id);
      });

      test('an explicit ml amount for "$id" resolves at high confidence', () {
        final item = parser.parse('250ml $id').items.single;
        expect(item.grams, 250, reason: id);
        expect(item.nutrition!.kcal, closeTo(kcalPer100ml * 2.5, 0.05), reason: id);
        expect(item.confidence, ParseConfidence.high, reason: id);
      });
    });
  });

  // Beer is the deliberate exception to "no alcohol default" above --
  // explicit product decision 2026-09-18: a bare beer/piwo mention should
  // resolve like a can of cola does, since (unlike wine/spirits) it's
  // near-universally a single ~500ml bottle/can.
  group('beer opts back into a bare-mention default, unlike other alcohol', () {
    test('bare "beer" resolves via a typical bottle/can serving', () {
      final item = parser.parse('beer').items.single;
      expect(item.canonicalId, 'beer');
      expect(item.grams, 500);
      expect(item.confidence, ParseConfidence.medium);
      expect(item.nutrition!.kcal, closeTo(43 * 5, 0.01));
    });

    test('a bare count ("1 beer") still resolves the same way, not blocked',
        () {
      final item = parser.parse('1 beer').items.single;
      expect(item.canonicalId, 'beer');
      expect(item.grams, 500);
      expect(item.confidence, ParseConfidence.medium);
    });
  });

  // Standard container volumes (glass/mug/cup/bottle/carton), reused from
  // WaterIntakeParser's own numbers, applied uniformly to every pourable
  // food (drink or dairy) that has real nutrient data but no food-specific
  // portion rule of its own.
  const containerMl = {'glass': 250, 'mug': 250, 'cup': 250, 'bottle': 500, 'carton': 500};
  const pourableFoods = ['wine', 'beer', 'milk']; // drink + dairy

  group('household container words resolve to a standard volume for pourable foods', () {
    for (final food in pourableFoods) {
      containerMl.forEach((unit, ml) {
        test('"$unit of $food" -> ${ml}ml, medium confidence', () {
          final item = parser.parse('$unit of $food').items.single;
          expect(item.canonicalId, food, reason: '$unit of $food');
          expect(item.grams, ml.toDouble(), reason: '$unit of $food');
          expect(item.confidence, ParseConfidence.medium, reason: '$unit of $food');
        });
      });
    }

    test('a container word on a non-pourable solid food does not invent a volume', () {
      // "glass of rice" -- rice has no glass-specific portion rule and
      // isn't pourable, so this must stay incomplete, not silently use the
      // 250ml container number for a solid.
      final item = parser.parse('glass of rice').items.single;
      expect(item.canonicalId, 'rice');
      expect(item.grams, null);
      expect(item.confidence, ParseConfidence.incomplete);
    });
  });

  group('chips/crisps regional split is preserved through migration', () {
    test('"chips" (-> fries) now has its own real migrated data', () {
      // FoodEstimator's "chips" tuple was actually the crisps figure, so it
      // was correctly NOT migrated onto `fries` early on -- but fries has
      // since gained its own real data, migrated from FoodEstimator's own
      // `wholeItems['fries (medium)']` (340kcal/115g), not the crisps one.
      final item = parser.parse('chips').items.single;
      expect(item.canonicalId, 'fries');
      expect(item.nutrition, isNotNull);
      expect(item.confidence, ParseConfidence.medium);
    });

    test('"crisps" got the real migrated figure instead', () {
      final item = parser.parse('crisps').items.single;
      expect(item.canonicalId, 'crisps');
      expect(item.nutrition, isNotNull);
      expect(item.confidence, ParseConfidence.medium);
    });
  });
}
