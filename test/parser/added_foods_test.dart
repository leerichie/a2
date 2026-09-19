import 'package:a2/parser/food_parser.dart';
import 'package:a2/parser/models/parse_confidence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression coverage for a real user-reported bug: a "cornflakes with milk
/// and toast with strawberry jam" entry came out ~150 kcal too high. Root
/// cause was that neither "cornflakes" nor "jam" existed in the local
/// catalogue at all, so a bare "strawberry jam" mention fell through to a
/// per-fragment AI guess with no context that it was a thin spread on
/// toast -- AI assumed something like a third of a jar (400g/250kcal).
/// These foods (plus several common Polish dishes that were catalogue+alias
/// entries with NO nutrition/portion data at all -- always "incomplete",
/// always needing AI, every single time) now resolve locally and
/// deterministically. See test/parser/coverage_matrix_test.dart's broad
/// matrix test for the general "every food with nutrition data resolves for
/// an exact measurement" pass -- this file checks the specific bare-mention
/// portion sizes that matter for this bug.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FoodParser parser;
  late FoodParser plParser;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    parser = await FoodParser.load();
    plParser = await FoodParser.load(locale: 'pl');
  });

  group('the original bug: jam is no longer a bare-mention 400g guess', () {
    test('a bare "jam" mention resolves to a realistic spread portion, not a jar', () {
      final item = parser.parse('jam').items.single;
      expect(item.canonicalId, 'jam');
      expect(item.grams, 15);
      expect(item.nutrition!.kcal, closeTo(37.5, 0.01));
      expect(item.confidence, ParseConfidence.medium);
    });

    test('"strawberry jam" resolves the same way as bare "jam"', () {
      final item = parser.parse('strawberry jam').items.single;
      expect(item.canonicalId, 'jam');
      expect(item.grams, 15);
    });

    test('Polish "dżem" resolves locally too', () {
      final item = plParser.parse('dżem').items.single;
      expect(item.canonicalId, 'jam');
      expect(item.grams, 15);
    });

    test('the full original sentence no longer inflates the jam component', () {
      final result = parser.parse(
        'i had a bowl of cornflakes with milk and no sugar then 2 slices of '
        'toast with strawberry jam',
      );
      final jam = result.items.firstWhere((i) => i.canonicalId == 'jam');
      expect(jam.grams, 15);
      expect(jam.nutrition!.kcal, closeTo(37.5, 0.01));
      final milk = result.items.firstWhere((i) => i.canonicalId == 'milk');
      expect(milk.nutrition!.kcal, 75);
    });
  });

  group('other common breakfast/pantry foods that were entirely missing', () {
    test('cornflakes resolves with a real bowl-sized default', () {
      final item = parser.parse('cornflakes').items.single;
      expect(item.canonicalId, 'cornflakes');
      expect(item.grams, 30);
    });

    test('honey, peanut butter, muesli, granola, and nutella all resolve', () {
      for (final MapEntry(key: text, value: id) in {
        'honey': 'honey',
        'peanut butter': 'peanut_butter',
        'muesli': 'muesli',
        'granola': 'granola',
        'nutella': 'chocolate_spread',
      }.entries) {
        final result = parser.parse(text);
        expect(result.unresolved, isEmpty, reason: '"$text" should resolve');
        expect(result.items.single.canonicalId, id);
      }
    });

    test('honey by the tablespoon uses the tablespoon-specific portion', () {
      final item = parser.parse('1 tbsp honey').items.single;
      expect(item.grams, 21);
    });
  });

  group('Polish dishes that used to have zero nutrition/portion data', () {
    test('common Polish dishes now resolve with real nutrition, not "incomplete"', () {
      for (final text in [
        'pierogi',
        'bigos',
        'barszcz',
        'żurek',
        'rosół',
        'gołąbki',
        'flaki',
        'kotlet schabowy',
      ]) {
        final result = plParser.parse(text);
        expect(result.unresolved, isEmpty, reason: '"$text" should resolve');
        final item = result.items.single;
        expect(item.confidence, isNot(ParseConfidence.incomplete), reason: '"$text"');
        expect(item.nutrition, isNotNull, reason: '"$text"');
      }
    });

    test('kopytka is a brand-new entry and resolves too', () {
      final item = plParser.parse('kopytka').items.single;
      expect(item.canonicalId, 'kopytka');
      expect(item.grams, 200);
    });

    test('fermented cucumber and yellow cheese borrow real nutrition via genericParent', () {
      final cucumber = plParser.parse('ogórek kiszony').items.single;
      expect(cucumber.canonicalId, 'sour_cucumber');
      expect(cucumber.nutrition, isNotNull);

      final cheese = plParser.parse('żółty ser').items.single;
      expect(cheese.canonicalId, 'yellow_cheese');
      expect(cheese.nutrition, isNotNull);
    });
  });

  group('"mashed" joins "boiled" as a recognized preparation', () {
    test('mashed potato now resolves the same way boiled potato already did', () {
      final mashed = parser.parse('mashed potato').items.single;
      expect(mashed.canonicalId, 'potato');
      expect(mashed.preparations, contains('mashed'));
    });
  });
}
