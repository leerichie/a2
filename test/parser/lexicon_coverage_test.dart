// Milestone: verify the *complete* English measurement/quantity lexicon is
// actually reachable through the parser, as a small number of matrix tests
// driven by the lexicon itself -- not hand-picked individual phrases. If a
// future dataset edit adds or removes an alias, these tests automatically
// cover it without being touched.
import 'package:a2/parser/catalogue/lexicon.dart';
import 'package:a2/parser/pipeline/household_portion_parser.dart';
import 'package:a2/parser/pipeline/quantity_parser.dart';
import 'package:a2/parser/pipeline/size_fullness_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Lexicon lexicon;

  setUpAll(() async {
    lexicon = await Lexicon.load();
  });

  group('every household-portion unit alias resolves to its canonical unit', () {
    test(
      'covers tsp/tbsp/cup, spoon/bowl/glass/mug/handful/pinch/splash, '
      'slice/piece/scoop, pack/container -- and everything else in the lexicon',
      () {
        expect(lexicon.unitByAlias, isNotEmpty);
        final failures = <String>[];
        lexicon.unitByAlias.forEach((alias, expectedUnit) {
          final result = parseHouseholdPortion('$alias food', lexicon);
          if (result.unit != expectedUnit) {
            failures.add('"$alias" -> ${result.unit} (expected $expectedUnit)');
          }
        });
        expect(failures, isEmpty, reason: failures.join('\n'));
      },
    );

    // Spot-check a representative sample by name, so a passing matrix test
    // above can't silently hide a wrong *expected* mapping in the lexicon
    // reverse-index itself (this cross-checks a few by literal id).
    const representative = {
      'tsp': 'teaspoon',
      'tbsp': 'tablespoon',
      'cup': 'cup',
      'ml': 'millilitre',
      'spoon': 'spoonful',
      'bowl': 'bowl',
      'glass': 'glass',
      'mug': 'mug',
      'handful': 'handful',
      'pinch': 'pinch',
      'splash': 'splash',
      'slice': 'slice',
      'piece': 'piece',
      'scoop': 'scoop',
      'serving': 'serving',
      'pack': 'pack',
      'container': 'container',
      'bottle': 'bottle',
      'jar': 'jar',
    };
    representative.forEach((alias, unitId) {
      test('"$alias" -> $unitId', () {
        expect(parseHouseholdPortion('$alias food', lexicon).unit, unitId);
      });
    });
  });

  group('every size and fullness alias resolves to its canonical id', () {
    test('every size alias in the lexicon', () {
      final failures = <String>[];
      lexicon.sizeByAlias.forEach((alias, expectedSize) {
        final result = parseSizeAndFullness('$alias food', lexicon);
        if (result.size != expectedSize) {
          failures.add('"$alias" -> ${result.size} (expected $expectedSize)');
        }
      });
      expect(failures, isEmpty, reason: failures.join('\n'));
    });

    test('every fullness alias in the lexicon', () {
      final failures = <String>[];
      lexicon.fullnessByAlias.forEach((alias, expectedFullness) {
        final result = parseSizeAndFullness('$alias food', lexicon);
        if (result.fullness != expectedFullness) {
          failures.add(
            '"$alias" -> ${result.fullness} (expected $expectedFullness)',
          );
        }
      });
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  });

  group('every numeric/word quantity form resolves to its value', () {
    test('every fraction word/symbol in the lexicon', () {
      final failures = <String>[];
      lexicon.fractions.forEach((phrase, expectedValue) {
        final result = parseQuantity('$phrase food', lexicon);
        if ((result.quantity - expectedValue).abs() > 0.0001) {
          failures.add(
            '"$phrase" -> ${result.quantity} (expected $expectedValue)',
          );
        }
      });
      expect(failures, isEmpty, reason: failures.join('\n'));
    });

    test('every cardinal word in the lexicon (one..twenty, zero excluded '
        'since a zero quantity has no meaning here)', () {
      final failures = <String>[];
      lexicon.cardinals.forEach((word, expectedValue) {
        if (expectedValue == 0) return;
        final result = parseQuantity('$word food', lexicon);
        if (result.quantity != expectedValue) {
          failures.add(
            '"$word" -> ${result.quantity} (expected $expectedValue)',
          );
        }
      });
      expect(failures, isEmpty, reason: failures.join('\n'));
    });

    test(
      'every word multiplier in the lexicon (single/double/triple/couple)',
      () {
        final failures = <String>[];
        lexicon.multipliers.forEach((word, expectedValue) {
          final result = parseQuantity('$word food', lexicon);
          if (result.quantity != expectedValue) {
            failures.add(
              '"$word" -> ${result.quantity} (expected $expectedValue)',
            );
          }
        });
        expect(failures, isEmpty, reason: failures.join('\n'));
      },
    );

    test('every approximation word sets approximate=true', () {
      final failures = <String>[];
      for (final word in lexicon.approximationWords) {
        final result = parseQuantity('$word food', lexicon);
        if (!result.approximate) failures.add(word);
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
    });

    test('digit-based multiplier patterns (1x, x1, 2×, ...) all parse', () {
      for (final pattern in [
        '1x',
        '2x',
        '3x',
        'x1',
        'x2',
        'x3',
        '2 x',
        '3 x',
        '2×',
        '3×',
      ]) {
        final result = parseQuantity('$pattern food', lexicon);
        expect(result.quantity, greaterThan(0), reason: pattern);
      }
    });
  });
}
