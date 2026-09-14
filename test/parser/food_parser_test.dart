import 'package:a2/parser/food_parser.dart';
import 'package:a2/parser/models/parse_confidence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FoodParser parser;

  setUpAll(() async {
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
      expect(item.confidence, ParseConfidence.incomplete); // no mayo nutrient record
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
      // banana HAS nutrient data, but no unit -> no portion rule -> grams unknown.
      expect(item.grams, null);
      expect(item.confidence, ParseConfidence.incomplete);
    });

    test('two small eggs', () {
      final item = parser.parse('two small eggs').items.single;
      expect(item.quantity, 2);
      expect(item.size, 'small');
      expect(item.canonicalId, 'egg');
      expect(item.confidence, ParseConfidence.incomplete);
    });

    test('3 slices cheddar', () {
      final item = parser.parse('3 slices cheddar').items.single;
      expect(item.quantity, 3);
      expect(item.unit, 'slice');
      expect(item.canonicalId, 'cheddar');
      expect(item.canonicalName, 'cheddar cheese');
      expect(item.grams, 60); // 3 x 20g medium slice rule
      expect(item.confidence, ParseConfidence.incomplete); // no cheddar nutrient record
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

    test('2 x 25g cheese -- no generic "cheese" catalogue entry, correctly unresolved', () {
      final r = parser.parse('2 x 25g cheese');
      expect(r.items, isEmpty);
      expect(r.unresolved.single.text, '2 x 25g cheese');
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

    test('recognized food, resolved portion, but no nutrient record -> incomplete', () {
      final item = parser.parse('250g chicken breast').items.single;
      expect(item.canonicalId, 'chicken_breast');
      expect(item.grams, 250);
      expect(item.confidence, ParseConfidence.incomplete);
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
}
