import 'package:a2/parser/catalogue/lexicon.dart';
import 'package:a2/parser/pipeline/household_portion_parser.dart';
import 'package:a2/parser/pipeline/size_fullness_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Lexicon lexicon;

  setUpAll(() async {
    lexicon = await Lexicon.load();
  });

  group('parseSizeAndFullness', () {
    test('size word', () {
      final r = parseSizeAndFullness('large banana', lexicon);
      expect(r.size, 'large');
      expect(r.remainder, 'banana');
    });

    test('size word after connector "a"', () {
      final r = parseSizeAndFullness('a large bowl of coleslaw', lexicon);
      expect(r.size, 'large');
      expect(r.remainder, 'bowl of coleslaw');
    });

    test('no size or fullness present', () {
      final r = parseSizeAndFullness('cheddar', lexicon);
      expect(r.size, null);
      expect(r.fullness, null);
      expect(r.remainder, 'cheddar');
    });
  });

  group('parseHouseholdPortion', () {
    test('tablespoon abbreviation', () {
      final r = parseHouseholdPortion('tbsp light mayo', lexicon);
      expect(r.unit, 'tablespoon');
      expect(r.remainder, 'light mayo');
    });

    test('bowl', () {
      final r = parseHouseholdPortion('bowl coleslaw', lexicon);
      expect(r.unit, 'bowl');
      expect(r.remainder, 'coleslaw');
    });

    test('slices (plural)', () {
      final r = parseHouseholdPortion('slices cheddar', lexicon);
      expect(r.unit, 'slice');
      expect(r.remainder, 'cheddar');
    });

    test('mug, then connector "of" before food', () {
      final r = parseHouseholdPortion('mug of yoghurt', lexicon);
      expect(r.unit, 'mug');
      expect(r.remainder, 'yoghurt');
    });

    test('no unit present', () {
      final r = parseHouseholdPortion('banana', lexicon);
      expect(r.unit, null);
      expect(r.remainder, 'banana');
    });
  });
}
