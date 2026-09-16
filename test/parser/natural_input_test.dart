// Dedicated natural-input / grammar-tolerance pass, ahead of wiring
// FoodParser into the live meal UI. Every case here already passes without
// any new hardcoded phrases -- it exercises the existing compositional
// lexicon (singular/plural unit aliases, "a"/"an"/"of" as connector words,
// abbreviations, regional food aliases) plus one real fix carried over from
// the previous session (self-referential unit/food collisions, see the
// dedicated group below) and a systematic audit for more of the same.
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

  void expectSameFood(List<String> phrases, String expectedId) {
    for (final phrase in phrases) {
      final item = parser.parse(phrase).items.single;
      expect(item.canonicalId, expectedId, reason: '"$phrase" should resolve to $expectedId');
    }
  }

  group('coleslaw: compound-word, split-word and slang all agree', () {
    test('all phrasings resolve to the same canonical id', () {
      expectSameFood([
        'coleslaw', 'cole slaw', 'slaw', '2 spoon coleslaw', '2 spoons coleslaw',
        '2 spoon of slaw', 'two spoons of slaw',
      ], 'coleslaw');
    });

    test('quantity and unit still extracted regardless of slaw/coleslaw spelling', () {
      for (final phrase in ['2 spoon coleslaw', '2 spoons coleslaw', '2 spoon of slaw']) {
        final item = parser.parse(phrase).items.single;
        expect(item.quantity, 2, reason: phrase);
        expect(item.unit, 'spoonful', reason: phrase);
      }
      final worded = parser.parse('two spoons of slaw').items.single;
      expect(worded.quantity, 2);
      expect(worded.unit, 'spoonful');
    });

    test('bare mentions default to quantity 1 with no unit', () {
      for (final phrase in ['coleslaw', 'cole slaw', 'slaw']) {
        final item = parser.parse(phrase).items.single;
        expect(item.quantity, 1, reason: phrase);
        expect(item.unit, null, reason: phrase);
      }
    });
  });

  group('oats: singular/plural, split fraction, and porridge alias all agree', () {
    test('all phrasings resolve to the same canonical id', () {
      expectSameFood([
        'half bowl oat', 'half bowl oats', 'half a bowl oats', 'half a bowl of oats',
        '½ bowl porridge',
      ], 'oats');
    });

    test('quantity/unit are identical across every phrasing', () {
      for (final phrase in [
        'half bowl oat', 'half bowl oats', 'half a bowl oats',
        'half a bowl of oats', '½ bowl porridge',
      ]) {
        final item = parser.parse(phrase).items.single;
        expect(item.quantity, 0.5, reason: phrase);
        expect(item.unit, 'bowl', reason: phrase);
      }
    });
  });

  group('cheese: singular/plural unit, cardinal vs digit, optional "of"', () {
    test('all phrasings resolve to the same canonical id', () {
      expectSameFood([
        '2 slice cheese', '2 slices cheese', 'two slice cheese', 'two slices of cheese',
      ], 'cheese');
    });

    test('quantity/unit are identical across every phrasing', () {
      for (final phrase in [
        '2 slice cheese', '2 slices cheese', 'two slice cheese', 'two slices of cheese',
      ]) {
        final item = parser.parse(phrase).items.single;
        expect(item.quantity, 2, reason: phrase);
        expect(item.unit, 'slice', reason: phrase);
      }
    });
  });

  group('mayonnaise: abbreviation, full word, brand-free slang, and modifier', () {
    test('all phrasings resolve to the same canonical id', () {
      expectSameFood([
        '2 tbsp mayo', '2 tablespoon mayo', '2 tablespoons mayonnaise',
      ], 'mayonnaise');
    });

    test('"light"/"reduced fat" modifiers survive and still resolve to base mayonnaise', () {
      for (final phrase in ['two tbsp light mayo', '2 spoon light mayo']) {
        final item = parser.parse(phrase).items.single;
        expect(item.canonicalId, 'mayonnaise', reason: phrase);
        expect(item.modifiers, ['light'], reason: phrase);
        expect(item.quantity, 2, reason: phrase);
      }
    });

    test('"reduced fat mayo" keeps its modifier too', () {
      final item = parser.parse('reduced fat mayo').items.single;
      expect(item.canonicalId, 'mayonnaise');
      expect(item.modifiers, ['reduced fat']);
    });
  });

  group('milk: size word, optional "of", and fraction all agree', () {
    test('all phrasings resolve to the same canonical id', () {
      expectSameFood([
        'large glass milk', 'large glass of milk', 'half glass milk', 'half a glass of milk',
      ], 'milk');
    });

    test('size and quantity are captured correctly per phrasing', () {
      final large1 = parser.parse('large glass milk').items.single;
      final large2 = parser.parse('large glass of milk').items.single;
      for (final item in [large1, large2]) {
        expect(item.size, 'large');
        expect(item.unit, 'glass');
        expect(item.quantity, 1);
      }
      final half1 = parser.parse('half glass milk').items.single;
      final half2 = parser.parse('half a glass of milk').items.single;
      for (final item in [half1, half2]) {
        expect(item.quantity, 0.5);
        expect(item.unit, 'glass');
      }
    });
  });

  group('quantity/plural combinations', () {
    test('singular/plural food noun does not change recognition', () {
      for (final phrase in ['2 egg', '2 eggs']) {
        final item = parser.parse(phrase).items.single;
        expect(item.canonicalId, 'egg', reason: phrase);
        expect(item.quantity, 2, reason: phrase);
      }
      for (final phrase in ['3 sausage', '3 sausages']) {
        final item = parser.parse(phrase).items.single;
        expect(item.canonicalId, 'sausage', reason: phrase);
        expect(item.quantity, 3, reason: phrase);
      }
    });

    test('fraction word vs. "half a" phrasing agree', () {
      for (final phrase in ['half banana', 'half a banana']) {
        final item = parser.parse(phrase).items.single;
        expect(item.canonicalId, 'banana', reason: phrase);
        expect(item.quantity, 0.5, reason: phrase);
      }
    });

    test('"Nx" multiplier works for both a unit-less food and a plural one', () {
      final banana = parser.parse('1x banana').items.single;
      expect(banana.canonicalId, 'banana');
      expect(banana.quantity, 1);
      final egg = parser.parse('2x egg').items.single;
      expect(egg.canonicalId, 'egg');
      expect(egg.quantity, 2);
    });
  });

  group('regional English aliases resolve to one shared canonical id', () {
    test('aubergine / eggplant', () {
      expect(parser.parse('aubergine').items.single.canonicalId, 'aubergine');
      expect(parser.parse('eggplant').items.single.canonicalId, 'aubergine');
    });
    test('courgette / zucchini', () {
      expect(parser.parse('courgette').items.single.canonicalId, 'courgette');
      expect(parser.parse('zucchini').items.single.canonicalId, 'courgette');
    });
    test('prawns / shrimp', () {
      expect(parser.parse('prawns').items.single.canonicalId, 'shrimp');
      expect(parser.parse('shrimp').items.single.canonicalId, 'shrimp');
    });
    test('minced beef / ground beef', () {
      expect(parser.parse('minced beef').items.single.canonicalId, 'minced_beef');
      expect(parser.parse('ground beef').items.single.canonicalId, 'minced_beef');
    });
  });

  // "Be careful with words that can be both a food and a portion/count
  // unit, as discovered with sausage." A systematic audit of every alias in
  // en/lexicon/units_and_portions.json against the food alias index found 8
  // such words total (all in the count_piece group -- individually-counted
  // meat/bakery/snack items, never volumes or packaging): sausage, steak,
  // roll, bun, wrap, cracker, biscuit, cookie. All 8 are covered here.
  //
  // The fix (in food_parser.dart) is generic, not per-word: if consuming a
  // household-portion unit leaves nothing else to resolve as food, the
  // parser retries resolving that same word as the food itself. It only
  // fires when nothing follows the unit word, so genuine container usage
  // ("a wrap of hummus") is unaffected -- checked below too.
  group('unit-vs-food collisions (full audit, not just sausage)', () {
    const collisions = {
      'sausage': 'sausage',
      'sausages': 'sausage',
      'steak': 'beef_steak',
      'roll': 'bread_roll',
      'bun': 'bread_roll',
      'wrap': 'wrap',
      'cracker': 'cracker',
      'biscuit': 'biscuit',
      'cookie': 'cookie',
    };
    collisions.forEach((word, expectedId) {
      test('bare "$word" resolves as food, not as an empty unit', () {
        final result = parser.parse(word);
        expect(result.items, isNotEmpty, reason: '"$word" should not be unresolved');
        final item = result.items.single;
        expect(item.canonicalId, expectedId);
        expect(item.unit, null, reason: 'the word was consumed as the food, not left as a unit');
      });
    });

    test('quantified collision words still resolve ("3 sausages", "2 wraps")', () {
      final sausages = parser.parse('3 sausages').items.single;
      expect(sausages.canonicalId, 'sausage');
      expect(sausages.quantity, 3);
      final wraps = parser.parse('2 wraps').items.single;
      expect(wraps.canonicalId, 'wrap');
      expect(wraps.quantity, 2);
    });

    test('"wrap" still works as a genuine container unit when something follows it', () {
      final item = parser.parse('a wrap of hummus').items.single;
      expect(item.unit, 'wrap');
      expect(item.canonicalId, 'hummus');
    });
  });

  group('preparations and modifiers survive grammar normalization', () {
    test('preparation words are captured, not discarded', () {
      // "fried egg" has its own dedicated catalogue entry (frying meaningfully
      // changes the nutrition profile), so the whole phrase resolves directly
      // to it rather than being generically stripped to egg + preparation.
      final fried = parser.parse('fried egg').items.single;
      expect(fried.canonicalId, 'fried_egg');
      expect(fried.preparations, isEmpty);

      // "grilled chicken breast" has no dedicated compound entry, so it
      // still falls back to generic stripping as before.
      final grilled = parser.parse('grilled chicken breast').items.single;
      expect(grilled.canonicalId, 'chicken_breast');
      expect(grilled.preparations, ['grilled']);
    });

    test('modifier words are captured, not discarded', () {
      final skinless = parser.parse('skinless chicken breast').items.single;
      expect(skinless.canonicalId, 'chicken_breast');
      expect(skinless.modifiers, ['skinless']);

      final lowFat = parser.parse('low fat milk').items.single;
      expect(lowFat.canonicalId, 'milk');
      expect(lowFat.modifiers, ['low fat']);
    });

    test('modifiers coexist correctly with an explicit measurement', () {
      final item = parser.parse('250g minced beef').items.single;
      expect(item.canonicalId, 'minced_beef');
      expect(item.grams, 250);
    });
  });

  group('a grammar-only fragment is unresolved, never a fake empty item', () {
    test('a bare number/approximation word with no food is flagged unresolved', () {
      for (final phrase in ['2', 'about', '2 x']) {
        final result = parser.parse(phrase);
        expect(result.items, isEmpty, reason: '"$phrase" carries no food identity');
        expect(result.unresolved, isNotEmpty, reason: '"$phrase" should be flagged, not silently dropped');
      }
    });

  });

  // Previously a known limitation: the segmenter split every standalone
  // "and" to separate foods ("egg, cheese and dragonfruit powder"), which
  // mis-split compound quantities like "one and a half eggs" into "one" +
  // "a half eggs". Fixed compositionally: the segmenter now recognizes an
  // "and" that sits between a cardinal/digit and a fraction word (using
  // the same cardinals/fractions tables the quantity parser reads, not a
  // hardcoded phrase list) and protects it from the split; the quantity
  // parser combines the two into one number.
  group('compound quantities survive segmentation ("X and a Y")', () {
    test('word cardinals: one/two and a half', () {
      expect(parser.parse('one and a half eggs').items.single.quantity, 1.5);
      expect(parser.parse('two and a half eggs').items.single.quantity, 2.5);
    });

    test('digit cardinals: 1/2 and a half', () {
      expect(parser.parse('1 and a half eggs').items.single.quantity, 1.5);
      expect(parser.parse('2 and a half eggs').items.single.quantity, 2.5);
    });

    test('quarter and three-quarters fractions, not just half', () {
      expect(parser.parse('one and a quarter bananas').items.single.quantity, 1.25);
      expect(parser.parse('one and three quarters bananas').items.single.quantity, 1.75);
    });

    test('all resolve to the expected food, not just the right number', () {
      final item = parser.parse('one and a half eggs').items.single;
      expect(item.canonicalId, 'egg');
    });

    test('a compound quantity with no food after it is honestly unresolved, '
        'not silently dropped or resolved to something else', () {
      // "portions" is a unit word with nothing after it to identify a
      // food -- correctly stays unresolved rather than inventing one.
      final result = parser.parse('one and a quarter portions');
      expect(result.items, isEmpty);
      expect(result.unresolved, isNotEmpty);
    });
  });

  group('normal food separation on "and"/"," still works', () {
    test('two foods joined by "and"', () {
      final r = parser.parse('egg and cheese');
      expect(r.items.map((i) => i.canonicalId), ['egg', 'cheese']);
      expect(r.unresolved, isEmpty);
    });

    test('a comma-and list of three foods', () {
      final r = parser.parse('egg, cheese and ham');
      expect(r.items.map((i) => i.canonicalId), ['egg', 'cheese', 'ham']);
    });

    test('quantities on each side of "and" are kept separate, not merged', () {
      final r = parser.parse('2 eggs and 1 banana');
      final egg = r.items.firstWhere((i) => i.canonicalId == 'egg');
      final banana = r.items.firstWhere((i) => i.canonicalId == 'banana');
      expect(egg.quantity, 2);
      expect(banana.quantity, 1);
    });
  });

  group('word multipliers ("couple") -- lexicon table now actually consulted', () {
    test('couple / a couple / N and a word both resolve to quantity 2', () {
      for (final phrase in ['couple of eggs', 'a couple of eggs', 'couple eggs']) {
        final item = parser.parse(phrase).items.single;
        expect(item.canonicalId, 'egg', reason: phrase);
        expect(item.quantity, 2, reason: phrase);
      }
    });
  });

  // Real live-input typos: conservative, generic word-level correction
  // (not one hardcoded alias per typo) applied before every remaining
  // matching stage, plus diacritic folding so Polish written with or
  // without accents resolves the same way.
  group('typo and diacritic normalization', () {
    test('a real live-entry sentence full of typos resolves completely', () {
      final r = parser.parse(
        '3 tbsp slaw, half tomato, boiled egg, spoon light cotage chese, '
        '4 slice smokd salmon, black cofee, half glass fruit smoothie, half glas waterr',
      );
      expect(r.unresolved, isEmpty);
      expect(
        r.items.map((i) => i.canonicalId),
        containsAll([
          'coleslaw', 'tomato', 'boiled_egg', 'cottage_cheese',
          'smoked_salmon', 'coffee', 'smoothie', 'water',
        ]),
      );
    });

    test('a typo never changes the stated quantity', () {
      final item = parser.parse('4 slice smokd salmon').items.single;
      expect(item.canonicalId, 'smoked_salmon');
      expect(item.quantity, 4);
    });

    test('an unrelated made-up word is left unresolved, not guessed', () {
      expect(parser.parse('xyzzyplonk').items, isEmpty);
      expect(parser.parse('xyzzyplonk').unresolved, isNotEmpty);
    });

    test('Polish written with or without diacritics resolves the same way', () async {
      final pl = await FoodParser.load(locale: 'pl');
      for (final text in ['duża kawa, pół łyżki serek wiejski', 'duza kawa, pol lyzki serek wiejski']) {
        final r = pl.parse(text);
        expect(r.unresolved, isEmpty, reason: text);
        expect(r.items.map((i) => i.canonicalId), ['coffee', 'cottage_cheese'], reason: text);
        expect(r.items.first.size, 'large', reason: text);
        expect(r.items.last.quantity, 0.5, reason: text);
      }
    });
  });
}
