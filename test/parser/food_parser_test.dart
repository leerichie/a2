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

  // Every fixture from docs/food_parser_english_dataset/.../09_parser_test_cases.json,
  // adapted to our flat model. Confidence is asserted honestly: with only the
  // 5 supplied portion examples and FoodEstimator's existing nutrient values
  // seeded (see build report), almost none of these have both a portion
  // rule AND a nutrient record for the same food yet -- so most correctly
  // come back Incomplete rather than a fabricated number. That's the
  // instructed behaviour, not a bug.
  group('09_parser_test_cases.json fixtures', () {
    test('2 tbsp light mayo', () {
      final r = parser.parse('2 tbsp light mayo');
      expect(r.unresolved, isEmpty);
      final item = r.items.single;
      expect(item.quantity, 2);
      expect(item.unit, 'tablespoon');
      expect(item.canonicalId, 'mayonnaise');
      expect(item.modifiers, ['light']);
      expect(item.grams, 28); // 2 x 14g tablespoon rule
      // mayonnaise now has a real nutrient record (USDA FoodData Central).
      expect(item.nutrition!.kcal, closeTo(190.4, 0.01)); // 680 kcal/100g * 28g
      expect(item.confidence, ParseConfidence.medium);
    });

    test('two tablespoons light mayonnaise', () {
      final item = parser.parse('two tablespoons light mayonnaise').items.single;
      expect(item.quantity, 2);
      expect(item.unit, 'tablespoon');
      expect(item.canonicalId, 'mayonnaise');
      expect(item.modifiers, ['light']);
    });

    test('2x tbsp mayo', () {
      final item = parser.parse('2x tbsp mayo').items.single;
      expect(item.quantity, 2);
      expect(item.unit, 'tablespoon');
      expect(item.canonicalId, 'mayonnaise');
      expect(item.modifiers, isEmpty);
    });

    test('half bowl coleslaw', () {
      final item = parser.parse('half bowl coleslaw').items.single;
      expect(item.quantity, 0.5);
      expect(item.unit, 'bowl');
      expect(item.canonicalId, 'coleslaw');
      expect(item.confidence, ParseConfidence.incomplete); // no portion rule, no nutrient data
    });

    test('about half a large bowl of coleslaw', () {
      final item = parser.parse('about half a large bowl of coleslaw').items.single;
      expect(item.approximate, true);
      expect(item.quantity, 0.5);
      expect(item.size, 'large');
      expect(item.unit, 'bowl');
      expect(item.canonicalId, 'coleslaw');
    });

    test('1x large banana', () {
      final item = parser.parse('1x large banana').items.single;
      expect(item.quantity, 1);
      expect(item.size, 'large');
      expect(item.canonicalId, 'banana');
      // Milestone: bare mentions now use FoodEstimator's own per-food
      // default weight (120g for banana) as a food-specific "no unit
      // given" portion rule -- not a global assumption, so this is
      // medium, not high (no exact measurement was given) and not
      // incomplete (a real number is available).
      expect(item.grams, 120);
      expect(item.confidence, ParseConfidence.medium);
    });

    test('two small eggs', () {
      final item = parser.parse('two small eggs').items.single;
      expect(item.quantity, 2);
      expect(item.size, 'small');
      expect(item.canonicalId, 'egg');
      expect(item.grams, 120); // 2 x 60g bare-mention default
      expect(item.confidence, ParseConfidence.medium);
    });

    test('3 slices cheddar', () {
      final item = parser.parse('3 slices cheddar').items.single;
      expect(item.quantity, 3);
      expect(item.unit, 'slice');
      expect(item.canonicalId, 'cheddar');
      expect(item.canonicalName, 'cheddar cheese');
      expect(item.grams, 60); // 3 x 20g medium slice rule
      // Cheddar now has its own real nutrient record (USDA FoodData
      // Central, via tool/import_usda_nutrients.py) instead of falling back
      // to the generic "cheese" parent.
      expect(item.nutrition!.kcal, closeTo(246, 0.01)); // 410 kcal/100g * 60g
      expect(item.confidence, ParseConfidence.medium);
    });

    test('one handful grapes', () {
      final item = parser.parse('one handful grapes').items.single;
      expect(item.quantity, 1);
      expect(item.unit, 'handful');
      expect(item.canonicalId, 'grapes');
    });

    test('half a pack mozzarella', () {
      final item = parser.parse('half a pack mozzarella').items.single;
      expect(item.quantity, 0.5);
      expect(item.unit, 'pack');
      expect(item.canonicalId, 'mozzarella');
    });

    test('small splash milk', () {
      final item = parser.parse('small splash milk').items.single;
      expect(item.quantity, 1);
      expect(item.unit, 'splash');
      expect(item.size, 'small');
      expect(item.canonicalId, 'milk');
      // milk HAS nutrient data, but no portion rule for splash -> incomplete.
      expect(item.confidence, ParseConfidence.incomplete);
    });

    test('2 large spoonfuls cottage cheese', () {
      final item = parser.parse('2 large spoonfuls cottage cheese').items.single;
      expect(item.quantity, 2);
      expect(item.size, 'large');
      expect(item.unit, 'spoonful');
      expect(item.canonicalId, 'cottage_cheese');
    });

    test('2 x 25g cheese -- generic "cheese" now has real nutrient data (milestone 2) -> high', () {
      final item = parser.parse('2 x 25g cheese').items.single;
      expect(item.canonicalId, 'cheese');
      expect(item.grams, 50); // 2 x 25g
      expect(item.nutrition!.kcal, closeTo(175, 0.01)); // 350 kcal/100g * 50g
      expect(item.confidence, ParseConfidence.high);
    });

    test('½ glass milk', () {
      final item = parser.parse('½ glass milk').items.single;
      expect(item.quantity, 0.5);
      expect(item.unit, 'glass');
      expect(item.canonicalId, 'milk');
    });

    test('three quarters of a mug of yoghurt', () {
      final item = parser.parse('three quarters of a mug of yoghurt').items.single;
      expect(item.quantity, 0.75);
      expect(item.unit, 'mug');
      expect(item.canonicalId, 'yoghurt');
    });
  });

  // Demonstrates the full confidence range is genuinely reachable end to
  // end, using foods that DO have real seeded nutrient data.
  group('confidence range with seeded nutrient data', () {
    test('exact grams + known nutrient data -> high', () {
      final item = parser.parse('100g cottage cheese').items.single;
      expect(item.grams, 100);
      expect(item.nutrition!.kcal, closeTo(98, 0.01));
      expect(item.confidence, ParseConfidence.high);
    });

    test('exact litres + known nutrient data -> high', () {
      final item = parser.parse('0.5l beer').items.single;
      expect(item.grams, 500); // ml treated 1:1 as grams for now (density-neutral)
      expect(item.nutrition!.kcal, closeTo(215, 0.01)); // 43 kcal/100ml * 500ml
      expect(item.confidence, ParseConfidence.high);
    });

    test('approximate wording downgrades an exact measurement to low', () {
      final item = parser.parse('about 100g cottage cheese').items.single;
      expect(item.approximate, true);
      expect(item.confidence, ParseConfidence.low);
    });

    test('recognized food, resolved portion, and now a real nutrient record', () {
      // mayonnaise now has its own real nutrient record (USDA FoodData
      // Central, via tool/import_usda_nutrients.py) instead of the honest
      // gap this used to be.
      final item = parser.parse('1 tablespoon mayonnaise').items.single;
      expect(item.canonicalId, 'mayonnaise');
      expect(item.grams, 14);
      expect(item.nutrition!.kcal, closeTo(95.2, 0.01)); // 680 kcal/100g * 14g
      expect(item.confidence, ParseConfidence.medium);
    });

    test('subtype now has its own real nutrient record instead of '
        'borrowing its generic parent\'s', () {
      final item = parser.parse('250g chicken breast').items.single;
      expect(item.canonicalId, 'chicken_breast');
      expect(item.grams, 250);
      // 187 kcal/100g * 250g -- its own USDA record, not "chicken"'s.
      expect(item.nutrition!.kcal, closeTo(467.5, 0.01));
      expect(item.confidence, ParseConfidence.high);
    });
  });

  // Step 3 added these generic entries with no nutrient data at all --
  // milestone 2 then safely migrated FoodEstimator's real numbers for 7 of
  // the 8 (every one that's a solid food with an unambiguous FoodEstimator
  // match). "wine" is the one exception: it's a drink, and drinks
  // deliberately get no bare-mention default portion (the old universal
  // "25ml" assumption is gone), so a bare "wine" with no container word
  // correctly stays incomplete -- not a regression, the intended asymmetry.
  group('generic canonical entries recognize real migrated nutrition where safe', () {
    const nowHaveRealData = {
      'chicken': 165, 'cheese': 350, 'sausage': 300, 'salad': 60,
      'soup': 55, 'beans': 127, 'raisins': 300,
    };
    nowHaveRealData.forEach((word, kcalPer100g) {
      test('"$word" resolves with real migrated nutrient data, not invented', () {
        final item = parser.parse(word).items.single;
        expect(item.canonicalId, word);
        expect(item.confidence, ParseConfidence.medium);
        expect(item.nutrition, isNotNull);
        expect(item.nutrition!.kcal, closeTo(kcalPer100g * item.grams! / 100, 0.01));
      });
    });

    test('"wine" (a drink) still has no bare-mention default -- the old '
        '25ml-universal-measure assumption is not carried forward', () {
      final item = parser.parse('wine').items.single;
      expect(item.canonicalId, 'wine');
      expect(item.grams, null);
      expect(item.confidence, ParseConfidence.incomplete);
    });

    test('generic "chicken" is never silently narrowed to chicken breast', () {
      final item = parser.parse('chicken').items.single;
      expect(item.canonicalId, isNot('chicken_breast'));
      expect(item.canonicalId, 'chicken');
    });

    test('generic "cheese" is never silently narrowed to cheddar', () {
      final item = parser.parse('cheese').items.single;
      expect(item.canonicalId, isNot('cheddar'));
      expect(item.canonicalId, 'cheese');
    });

    test('"raisin" (singular) resolves to the new "raisins" entry', () {
      final item = parser.parse('raisin').items.single;
      expect(item.canonicalId, 'raisins');
    });

    test('"porridge" and "oat" resolve to the existing "oats" entry', () {
      expect(parser.parse('porridge').items.single.canonicalId, 'oats');
      expect(parser.parse('oat').items.single.canonicalId, 'oats');
    });

    test('"crisp" (singular) resolves to the existing "crisps" entry', () {
      expect(parser.parse('crisp').items.single.canonicalId, 'crisps');
    });

    test('regional term "chips" still resolves to fries, not crisps', () {
      expect(parser.parse('chips').items.single.canonicalId, 'fries');
    });
  });

  group('unresolved-word tracking', () {
    test('a mixed sentence keeps recognized items and flags the rest', () {
      final r = parser.parse('egg, cheddar and dragonfruit powder');
      final ids = r.items.map((i) => i.canonicalId).toList();
      expect(ids, containsAll(['egg', 'cheddar']));
      expect(r.unresolved.map((u) => u.text), contains('dragonfruit powder'));
    });
  });

  // A subtype (e.g. cheddar) with no nutrient record of its own borrows its
  // generic parent's real, already-migrated data -- a taxonomic fact, not
  // an invented number -- and is always flagged Low confidence so the UI
  // never overclaims precision it doesn't have.
  group('generic-parent nutrition fallback', () {
    // Only subtypes with no real record of their own still borrow from a
    // generic parent -- cheddar/mozzarella/chicken_breast/chicken_thigh
    // used to be in this group too, until tool/import_usda_nutrients.py
    // gave each of them its own real USDA record (see the dedicated tests
    // below and above).
    const subtypes = {'greek_yoghurt': 'yoghurt'};
    subtypes.forEach((subtypeId, parentId) {
      test('"$subtypeId" borrows nutrition from its parent "$parentId" at Low confidence', () {
        final subtypeItem = parser.parse('100g $subtypeId'.replaceAll('_', ' ')).items.single;
        expect(subtypeItem.canonicalId, subtypeId);
        expect(subtypeItem.nutrition, isNotNull);
        expect(subtypeItem.confidence, ParseConfidence.low);

        final parentItem = parser.parse('100g ${parentId.replaceAll('_', ' ')}').items.single;
        // Same grams (100g) -> the fallback nutrition must match the
        // parent's own record exactly, not an invented approximation.
        expect(subtypeItem.nutrition!.kcal, closeTo(parentItem.nutrition!.kcal, 0.01));
      });
    });

    test('"mozzarella" now has its own real record instead of borrowing '
        'from "cheese"', () {
      final item = parser.parse('100g mozzarella').items.single;
      expect(item.canonicalId, 'mozzarella');
      expect(item.nutrition!.kcal, closeTo(141, 0.01));
      expect(item.confidence, ParseConfidence.high);
    });

    test('"chicken_thigh" now has its own real record instead of '
        'borrowing from "chicken"', () {
      final item = parser.parse('100g chicken thigh').items.single;
      expect(item.canonicalId, 'chicken_thigh');
      expect(item.nutrition!.kcal, closeTo(218, 0.01));
      expect(item.confidence, ParseConfidence.high);
    });
  });

  // Density-neutral ml-as-grams for the dataset's own `standard_volume`
  // units, generalized beyond drinks to any food -- plus "spoonful" as a
  // deliberate Low-confidence addition. Never extended to vague
  // `approx_household` units like bowl/handful/scoop.
  group('generic standard-volume fallback (any food, not just drinks)', () {
    const cases = {
      '1 teaspoon cottage cheese': {'unit': 'teaspoon', 'grams': 5.0, 'confidence': ParseConfidence.medium},
      '1 tablespoon cottage cheese': {'unit': 'tablespoon', 'grams': 15.0, 'confidence': ParseConfidence.medium},
      '1 dessertspoon cottage cheese': {'unit': 'dessertspoon', 'grams': 10.0, 'confidence': ParseConfidence.medium},
      '1 cup cottage cheese': {'unit': 'cup', 'grams': 240.0, 'confidence': ParseConfidence.medium},
      '1 fluid ounce cottage cheese': {'unit': 'fluid_ounce', 'grams': 30.0, 'confidence': ParseConfidence.medium},
      '1 spoonful cottage cheese': {'unit': 'spoonful', 'grams': 15.0, 'confidence': ParseConfidence.low},
    };
    cases.forEach((phrase, expected) {
      test('"$phrase"', () {
        final item = parser.parse(phrase).items.single;
        expect(item.canonicalId, 'cottage_cheese');
        expect(item.unit, expected['unit']);
        expect(item.grams, expected['grams']);
        expect(item.nutrition, isNotNull);
        expect(item.confidence, expected['confidence']);
      });
    });

    test('vague approx_household units (bowl/handful/scoop) are NOT given a universal gram value', () {
      final item = parser.parse('one bowl cottage cheese').items.single;
      expect(item.canonicalId, 'cottage_cheese');
      expect(item.grams, isNull);
      expect(item.confidence, ParseConfidence.incomplete);
    });
  });

  // Zero/negligible-calorie foods are a known FACT, not missing data --
  // must resolve normally and never make a meal "incomplete" just because
  // the contribution is 0 kcal.
  group('zero and negligible-calorie foods', () {
    test('water is 0 kcal and fully resolved, not incomplete', () {
      final item = parser.parse('glass water').items.single;
      expect(item.canonicalId, 'water');
      expect(item.grams, 250);
      expect(item.nutrition!.kcal, 0);
      expect(item.confidence, ParseConfidence.medium);
    });

    test('black coffee resolves with a bare-mention default, negligible kcal', () {
      final item = parser.parse('black coffee').items.single;
      expect(item.canonicalId, 'coffee');
      expect(item.grams, 100);
      expect(item.nutrition!.kcal, closeTo(3, 0.01));
      expect(item.confidence, ParseConfidence.medium);
    });

    test('tea resolves with a bare-mention default, negligible kcal', () {
      final item = parser.parse('tea').items.single;
      expect(item.canonicalId, 'tea');
      expect(item.nutrition!.kcal, closeTo(2, 0.01));
      expect(item.confidence, ParseConfidence.medium);
    });
  });

  // The exact real-world input reported live. Closing the two remaining
  // gaps (smoked salmon's own catalogue entry + data, fruit smoothie's
  // derived nutrient value) means this now resolves completely, locally,
  // with no AI needed at all.
  group('real-world regression: mixed breakfast sentence', () {
    late final result = parser.parse(
      '2 tbsp coleslaw, 4 slice smoked salmon, boiled egg, 2 slice cheddar, '
      'spoon light cottage cheese, black coffee, glass water, half glass fruit smoothie',
    );

    test('resolves all 8 components with usable nutrition data, none invented', () {
      final resolvedIds = result.items.map((i) => i.canonicalId).toList();
      expect(
        resolvedIds,
        containsAll([
          'coleslaw', 'smoked_salmon', 'boiled_egg', 'cheddar',
          'cottage_cheese', 'coffee', 'water', 'smoothie',
        ]),
      );
      for (final item in result.items) {
        expect(item.confidence, isNot(ParseConfidence.incomplete));
        expect(item.nutrition, isNotNull);
      }
    });

    test('nothing is silently dropped -- no leftover unresolved text at all', () {
      expect(result.unresolved, isEmpty);
    });

    test('exact quantities are preserved through the whole sentence', () {
      final byId = {for (final i in result.items) i.canonicalId: i};
      expect(byId['coleslaw']!.quantity, 2);
      expect(byId['smoked_salmon']!.quantity, 4);
      expect(byId['cheddar']!.quantity, 2);
      expect(byId['smoothie']!.quantity, 0.5); // "half glass" preserved
    });

    test('water is genuinely 0 kcal; cheddar and smoked salmon resolve with '
        'their own real data', () {
      final byId = {for (final i in result.items) i.canonicalId: i};
      expect(byId['water']!.nutrition!.kcal, 0);
      expect(byId['cheddar']!.confidence, ParseConfidence.medium); // own real data, unit-based portion
      expect(byId['smoked_salmon']!.confidence, ParseConfidence.medium); // own real data
    });
  });

  // Dataset-coverage acceptance check: mayonnaise/cheddar/avocado etc. now
  // have real nutrient records (tool/import_usda_nutrients.py) instead of
  // the "I don't have nutrition data for mayonnaise yet" gap this used to
  // hit. A leading meal-time word ("breakfast ...") is also stripped before
  // segmentation, same as any other filler word, so it doesn't block the
  // rest of the sentence from resolving.
  group('real-world regression: user-reported breakfast sentence', () {
    late final result = parser.parse(
      'breakfast half avocado, 3 tbsp coleslaw with light mayo, 2 slice cheddar, '
      'half bell pepper, 2 tbsp cottage cheese, black coffee, glass fruit smoothie',
    );

    test('nothing is silently dropped -- no leftover unresolved text', () {
      expect(result.unresolved, isEmpty);
    });

    test('avocado, cheddar, bell pepper and cottage cheese all resolve '
        'with real nutrition data, not invented', () {
      final byId = {for (final i in result.items) i.canonicalId: i};
      expect(byId['avocado']!.nutrition!.kcal, closeTo(80, 0.01)); // half, 160 kcal/100g
      expect(byId['cheddar']!.nutrition!.kcal, closeTo(164, 0.01)); // 2 slices, 410 kcal/100g
      expect(byId['bell_pepper']!.nutrition, isNotNull);
      expect(byId['cottage_cheese']!.nutrition, isNotNull);
      for (final id in ['avocado', 'cheddar', 'bell_pepper', 'cottage_cheese']) {
        expect(byId[id]!.confidence, isNot(ParseConfidence.incomplete));
      }
    });

    test('"with light mayo" splits into its own segment (by design, same '
        'as any "X with Y" phrase) with no quantity of its own, so it '
        'honestly stays Incomplete rather than guessing an amount -- '
        'mayonnaise itself DOES have real data now ("2 tbsp light mayo" '
        'above proves that)', () {
      final byId = {for (final i in result.items) i.canonicalId: i};
      expect(byId['mayonnaise']!.grams, isNull);
      expect(byId['mayonnaise']!.confidence, ParseConfidence.incomplete);
    });
  });

  // A small representative meal per category, catching practical
  // catalogue/portion holes rather than one-off phrases -- every
  // component in every meal below must resolve with real nutrition data,
  // not just the specific real-world sentence above.
  group('representative real-world meal matrix', () {
    const meals = {
      'breakfast': 'porridge, banana, orange juice',
      'lunch': 'chicken breast, rice, broccoli',
      'dinner': 'salmon, sweet potato, green beans',
      'snack': 'apple and a handful of almonds',
      'drinks': 'cup of tea, glass of orange juice, glass of cola',
    };
    meals.forEach((mealType, phrase) {
      test('$mealType: "$phrase" resolves completely, no invented data', () {
        final result = parser.parse(phrase);
        expect(result.unresolved, isEmpty, reason: 'nothing silently dropped for $mealType');
        for (final item in result.items) {
          expect(
            item.confidence,
            isNot(ParseConfidence.incomplete),
            reason: '${item.canonicalId} should resolve in "$phrase"',
          );
          expect(item.nutrition, isNotNull);
        }
      });
    });
  });
}
