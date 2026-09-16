import 'package:a2/main.dart';
import 'package:a2/parser/food_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FoodParser parser;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    parser = await FoodParser.load();
  });

  for (final phrase in [
    'avocado, snack',
    'avocado , snack',
    'Avocado Snack',
    'avocado - snack',
    'avocado (snack)',
    '1 avocado, snack',
    'snack: avocado',
    'snack - avocado',
  ]) {
    test('probe: "$phrase"', () {
      final ctx = extractMealContext(phrase);
      final result = parser.parse(ctx.$3);
      print(
        '"$phrase" -> explicitCategory=${ctx.$1} textToParse="${ctx.$3}" '
        'items=${result.items.map((i) => '${i.canonicalId}/${i.confidence}').toList()} '
        'unresolved=${result.unresolved.map((u) => u.text).toList()}',
      );
    });
  }
}
