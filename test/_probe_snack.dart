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
    'cadburys snack',
    'snack cadburys',
    'avocado snack',
    'snack avocado',
    'cadburys',
    'avocado',
    'snack',
  ]) {
    test('probe: "$phrase"', () {
      final ctx = extractMealContext(phrase);
      print('$phrase -> explicitCategory=${ctx.$1} textToParse="${ctx.$3}"');
      final result = parser.parse(ctx.$3);
      for (final item in result.items) {
        print('  item: canonicalId=${item.canonicalId} confidence=${item.confidence} nutrition=${item.nutrition}');
      }
      print('  unresolved=${result.unresolved.map((u) => u.text).toList()}');
    });
  }
}
