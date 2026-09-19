import 'package:a2/parser/catalogue/alias_index.dart';
import 'package:a2/parser/catalogue/lexicon.dart';
import 'package:a2/parser/pipeline/segmenter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Lexicon lexicon;
  final aliasIndex = AliasIndex.build({});

  setUpAll(() async {
    lexicon = await Lexicon.load();
  });

  group('normal food separation on "and"/","', () {
    test('two foods joined by "and"', () {
      expect(segmentPhrases('egg and cheese', lexicon, aliasIndex), ['egg', 'cheese']);
    });

    test('comma-and list of three foods', () {
      expect(segmentPhrases('egg, cheese and ham', lexicon, aliasIndex), ['egg', 'cheese', 'ham']);
    });

    test('quantities on each side of "and" stay in their own segment', () {
      expect(segmentPhrases('2 eggs and 1 banana', lexicon, aliasIndex), ['2 eggs', '1 banana']);
    });
  });

  group('compound quantities protect their "and" from the food-list split', () {
    test('word cardinal + half is kept as one segment', () {
      expect(segmentPhrases('one and a half eggs', lexicon, aliasIndex), ['one and a half eggs']);
    });

    test('digit cardinal + half is kept as one segment', () {
      expect(segmentPhrases('2 and a half eggs', lexicon, aliasIndex), ['2 and a half eggs']);
    });

    test('quarter and three-quarters are protected too, not just half', () {
      expect(segmentPhrases('one and a quarter bananas', lexicon, aliasIndex), ['one and a quarter bananas']);
      expect(
        segmentPhrases('one and three quarters bananas', lexicon, aliasIndex),
        ['one and three quarters bananas'],
      );
    });

    test('a protected compound quantity can still be followed by more foods', () {
      expect(
        segmentPhrases('one and a half eggs and a banana', lexicon, aliasIndex),
        ['one and a half eggs', 'a banana'],
      );
    });
  });

  group('an "and" only counts as compound when both sides actually look like one', () {
    test('a cardinal followed by a non-fraction word still splits normally', () {
      expect(segmentPhrases('one and cheese', lexicon, aliasIndex), ['one', 'cheese']);
    });

    test('a fraction-looking word with no cardinal before it still splits normally', () {
      expect(segmentPhrases('cheese and a half', lexicon, aliasIndex), ['cheese', 'a half']);
    });

    test('"and" at the very start or end of text does not crash and just drops', () {
      expect(segmentPhrases('and cheese', lexicon, aliasIndex), ['cheese']);
      expect(segmentPhrases('cheese and', lexicon, aliasIndex), ['cheese']);
    });
  });

  group('a known compound dish name containing "with" is not torn apart', () {
    final compoundAliasIndex = AliasIndex.build({
      'cottage_cheese_with_chives': ['cottage cheese with chives'],
    });

    test('the bare compound name is kept as one segment', () {
      expect(
        segmentPhrases('cottage cheese with chives', lexicon, compoundAliasIndex),
        ['cottage cheese with chives'],
      );
    });

    // Regression: an exact gram measurement glued to the front used to stop
    // the whole-phrase alias lookup from ever matching (the alias index only
    // has "cottage cheese with chives", not "100g cottage cheese with
    // chives"), so this silently fell through to being split on "with" into
    // "100g cottage cheese" + "chives" -- two unrelated foods instead of one
    // dish. Caught by test/parser/coverage_matrix_test.dart once this dish
    // finally got real nutrition data to check against.
    test('the same compound name with a leading gram measurement is also kept whole', () {
      expect(
        segmentPhrases('100g cottage cheese with chives', lexicon, compoundAliasIndex),
        ['100g cottage cheese with chives'],
      );
      expect(
        segmentPhrases('250 g cottage cheese with chives', lexicon, compoundAliasIndex),
        ['250 g cottage cheese with chives'],
      );
    });

    test('an unrecognized "X with Y" phrase still splits normally', () {
      expect(
        segmentPhrases('chicken with rice', lexicon, compoundAliasIndex),
        ['chicken', 'rice'],
      );
    });
  });
}
