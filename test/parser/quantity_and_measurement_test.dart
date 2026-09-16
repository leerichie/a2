import 'package:a2/parser/catalogue/lexicon.dart';
import 'package:a2/parser/pipeline/measurement_parser.dart';
import 'package:a2/parser/pipeline/quantity_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Lexicon lexicon;

  setUpAll(() async {
    lexicon = await Lexicon.load();
  });

  group('parseQuantity', () {
    test('plain number', () {
      final r = parseQuantity('3 slices cheddar', lexicon);
      expect(r.quantity, 3);
      expect(r.remainder, 'slices cheddar');
    });

    test('Nx multiplier', () {
      final r = parseQuantity('1x large banana', lexicon);
      expect(r.quantity, 1);
      expect(r.remainder, 'large banana');
    });

    test('2x with space before unit', () {
      final r = parseQuantity('2x tbsp mayo', lexicon);
      expect(r.quantity, 2);
      expect(r.remainder, 'tbsp mayo');
    });

    test('cardinal word', () {
      final r = parseQuantity('two small eggs', lexicon);
      expect(r.quantity, 2);
      expect(r.remainder, 'small eggs');
    });

    test('one handful', () {
      final r = parseQuantity('one handful grapes', lexicon);
      expect(r.quantity, 1);
      expect(r.remainder, 'handful grapes');
    });

    test('fraction word "half"', () {
      final r = parseQuantity('half bowl coleslaw', lexicon);
      expect(r.quantity, 0.5);
      expect(r.remainder, 'bowl coleslaw');
    });

    test('fraction symbol', () {
      final r = parseQuantity('½ glass milk', lexicon);
      expect(r.quantity, 0.5);
      expect(r.remainder, 'glass milk');
    });

    test('three-word fraction phrase', () {
      final r = parseQuantity('three quarters of a mug of yoghurt', lexicon);
      expect(r.quantity, 0.75);
      expect(r.remainder, 'of a mug of yoghurt');
    });

    test('approximation word sets approximate and is stripped', () {
      final r = parseQuantity('about half a large bowl of coleslaw', lexicon);
      expect(r.approximate, true);
      expect(r.quantity, 0.5);
      expect(r.remainder, 'a large bowl of coleslaw');
    });

    test('no leading quantity defaults to 1', () {
      final r = parseQuantity('small splash milk', lexicon);
      expect(r.quantity, 1);
      expect(r.remainder, 'small splash milk');
    });

    test('explicit multiplier x weight, "2 x 25g cheese"', () {
      final r = parseQuantity('2 x 25g cheese', lexicon);
      expect(r.quantity, 2);
      expect(r.remainder, '25g cheese');
    });

    test('regression: a decimal number glued to a unit letter is left for '
        'measurement_parser, not truncated to its integer part', () {
      final r = parseQuantity('0.5l beer', lexicon);
      expect(r.quantity, 1); // no quantity token consumed
      expect(r.remainder, '0.5l beer'); // NOT "5l beer" / ".5l beer"
    });

    group('compound cardinal+fraction ("X and a Y") -- built from the '
        'cardinals/fractions tables, not a hardcoded phrase', () {
      test('word cardinal + half', () {
        final one = parseQuantity('one and a half eggs', lexicon);
        expect(one.quantity, 1.5);
        expect(one.remainder, 'eggs');
        final two = parseQuantity('two and a half eggs', lexicon);
        expect(two.quantity, 2.5);
      });

      test('digit cardinal + half', () {
        final r = parseQuantity('1 and a half eggs', lexicon);
        expect(r.quantity, 1.5);
        expect(r.remainder, 'eggs');
      });

      test('quarter and three-quarters, not just half', () {
        expect(parseQuantity('one and a quarter portions', lexicon).quantity, 1.25);
        expect(parseQuantity('one and three quarters portions', lexicon).quantity, 1.75);
      });

      test('a bare "X and" with no fraction after it does not fire', () {
        // "one and cheese" -- "and" here is a food separator, not part of a
        // compound quantity, so parseQuantity should only claim "one".
        final r = parseQuantity('one and cheese', lexicon);
        expect(r.quantity, 1);
        expect(r.remainder, 'and cheese');
      });
    });

    group('word multipliers ("couple") -- lexicon.multipliers is now read', () {
      test('bare "couple"', () {
        final r = parseQuantity('couple of eggs', lexicon);
        expect(r.quantity, 2);
        expect(r.remainder, 'of eggs');
      });

      test('"a couple" as one phrase, not "a" + "couple" separately', () {
        final r = parseQuantity('a couple of eggs', lexicon);
        expect(r.quantity, 2);
        expect(r.remainder, 'of eggs');
      });

      test('"double" and "triple"', () {
        expect(parseQuantity('double cheeseburger', lexicon).quantity, 2);
        expect(parseQuantity('triple cheeseburger', lexicon).quantity, 3);
      });
    });
  });

  group('parseMeasurement', () {
    test('bare grams', () {
      final r = parseMeasurement('250g chicken breast');
      expect(r.grams, 250);
      expect(r.remainder, 'chicken breast');
    });

    test('kilograms convert to grams', () {
      final r = parseMeasurement('1.5kg mince');
      expect(r.grams, 1500);
      expect(r.remainder, 'mince');
    });

    test('litres convert to millilitres', () {
      final r = parseMeasurement('0.5l beer');
      expect(r.millilitres, 500);
      expect(r.remainder, 'beer');
    });

    test('does not misfire on "large" starting with l', () {
      final r = parseMeasurement('large banana');
      expect(r.grams, null);
      expect(r.millilitres, null);
      expect(r.remainder, 'large banana');
    });

    test('no measurement present', () {
      final r = parseMeasurement('cheddar cheese');
      expect(r.grams, null);
      expect(r.millilitres, null);
    });
  });
}
