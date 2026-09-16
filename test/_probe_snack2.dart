import 'package:a2/main.dart';
import 'package:a2/parser/catalogue/local_overlay.dart';
import 'package:a2/parser/food_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('probe: add cadburys via AddFoodSheet flow, then edit to add snack', () async {
    SharedPreferences.setMockInitialValues({});
    // Simulates AddFoodSheet._save() adding "cadburys" manually.
    final entry = OverlayFoodEntry(
      id: OverlayFoodEntry.idFor('cadburys'),
      canonical: 'cadburys',
      kcalPer100g: 534 * 100 / 45, // 534 kcal for a 45g bar, entered by user
      proteinPer100g: null,
      carbsPer100g: null,
      fatPer100g: null,
      servingAmount: 45,
      servingUnit: 'g',
      source: 'user',
    );
    final overlay = await LocalCatalogueOverlay.load();
    await overlay.upsert(entry);

    final parser = await FoodParser.load();

    for (final phrase in ['cadburys', 'cadburys snack', 'snack cadburys']) {
      final ctx = extractMealContext(phrase);
      final result = parser.parse(ctx.$3);
      print(
        '$phrase -> explicitCategory=${ctx.$1} textToParse="${ctx.$3}" '
        'items=${result.items.map((i) => '${i.canonicalId}/${i.confidence}/nutrition=${i.nutrition}').toList()} '
        'unresolved=${result.unresolved.map((u) => u.text).toList()}',
      );
    }
  });
}
