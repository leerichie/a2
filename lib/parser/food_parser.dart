import 'aliases/personal_alias_repository.dart';
import 'catalogue/alias_index.dart';
import 'catalogue/asset_reader.dart';
import 'catalogue/food_catalogue.dart';
import 'catalogue/lexicon.dart';
import 'catalogue/nutrition_catalogue.dart';
import 'catalogue/portion_catalogue.dart';
import 'models/food_parse_item.dart';
import 'models/nutrient_totals.dart';
import 'models/parse_confidence.dart';
import 'models/unresolved_span.dart';
import 'pipeline/confidence_engine.dart';
import 'pipeline/food_resolver.dart';
import 'pipeline/household_portion_parser.dart';
import 'pipeline/measurement_parser.dart';
import 'pipeline/modifier_preparation_parser.dart';
import 'pipeline/quantity_parser.dart';
import 'pipeline/segmenter.dart';
import 'pipeline/size_fullness_parser.dart';
import 'pipeline/text_normalizer.dart';

class FoodParser {
  const FoodParser({
    required this.catalogue,
    required this.aliasIndex,
    required this.lexicon,
    required this.nutrition,
    required this.portions,
    this.personalAliases,
    this.locale = 'en',
  });

  final FoodCatalogue catalogue;
  final AliasIndex aliasIndex;
  final Lexicon lexicon;
  final NutritionCatalogue nutrition;
  final PortionCatalogue portions;
  final PersonalAliasRepository? personalAliases;
  final String locale;

  static Future<FoodParser> load({
    String locale = 'en',
    AssetReader reader = defaultAssetReader,
    PersonalAliasRepository? personalAliases,
  }) async {
    final catalogue = await FoodCatalogue.load(locale: locale, reader: reader);
    final lexicon = await Lexicon.load(locale: locale, reader: reader);
    final nutrition = await NutritionCatalogue.load(reader: reader);
    final portions = await PortionCatalogue.load(reader: reader);
    final aliasIndex = AliasIndex.build({
      for (final e in catalogue.entries) e.id: [...e.aliases, e.canonical],
    });
    if (aliasIndex.collisions.isNotEmpty) {
      throw StateError('Food alias collisions: ${aliasIndex.collisions}');
    }
    return FoodParser(
      catalogue: catalogue,
      aliasIndex: aliasIndex,
      lexicon: lexicon,
      nutrition: nutrition,
      portions: portions,
      personalAliases: personalAliases,
      locale: locale,
    );
  }

  FoodParseResult parse(String input) {
    final normalized = normalizeParserText(input);
    final segments = segmentPhrases(normalized);
    final items = <FoodParseItem>[];
    final unresolved = <UnresolvedSpan>[];
    var cursor = 0;

    for (final segment in segments) {
      final item = _parseSegment(segment);
      if (item != null) {
        items.add(item);
      } else {
        unresolved.add(UnresolvedSpan(segment, cursor, cursor + segment.length));
      }
      cursor += segment.length + 1;
    }
    return FoodParseResult(items, unresolved);
  }

  FoodParseItem? _parseSegment(String segment) {
    final quantityResult = parseQuantity(segment, lexicon);
    var remaining = quantityResult.remainder;

    final measurement = parseMeasurement(remaining);
    remaining = measurement.remainder;

    // Size/fullness before the unit: a size word routinely precedes the
    // unit word ("small splash milk", "a large bowl of coleslaw"), and
    // each stage only looks at the *start* of the remaining text, so the
    // unit parser would otherwise never see past an unconsumed size word.
    final sizeFullness = parseSizeAndFullness(remaining, lexicon);
    remaining = sizeFullness.remainder;

    String? unit;
    if (measurement.grams == null && measurement.millilitres == null) {
      final portion = parseHouseholdPortion(remaining, lexicon);
      unit = portion.unit;
      remaining = portion.remainder;
    }

    final modPrep = parseModifiersAndPreparations(remaining, lexicon);
    remaining = modPrep.remainder;

    if (remaining.trim().isNotEmpty) {
      final resolution = resolveFood(remaining, catalogue, aliasIndex,
          personalAliases: personalAliases, locale: locale);
      if (resolution.entry == null) return null;

      final entry = resolution.entry!;
      final baseEntry = entry.baseFoodId != null
          ? catalogue.entries.firstWhere(
              (e) => e.id == entry.baseFoodId,
              orElse: () => entry,
            )
          : entry;
      final nutrientLookupId = baseEntry.id;
      final record = nutrition.forFoodId(nutrientLookupId);

      double? gramsPerUnit;
      bool exactMeasurement = false;
      String? portionRuleConfidence;
      if (measurement.grams != null) {
        gramsPerUnit = measurement.grams;
        exactMeasurement = true;
      } else if (measurement.millilitres != null) {
        gramsPerUnit = measurement.millilitres; // density-neutral: ml treated 1:1 for now
        exactMeasurement = true;
      } else if (unit != null) {
        final rule = portions.lookup(foodId: nutrientLookupId, unit: unit, size: sizeFullness.size);
        if (rule != null) {
          gramsPerUnit = rule.grams;
          portionRuleConfidence = rule.confidence;
        }
      }

      final totalGrams = gramsPerUnit == null ? null : gramsPerUnit * quantityResult.quantity;
      final gramsKnown = totalGrams != null;

      NutrientTotals? nutritionTotals;
      if (record != null && gramsKnown) {
        final factor = totalGrams / 100.0;
        nutritionTotals = NutrientTotals(
          kcal: record.kcalPer100g * factor,
          proteinG: record.proteinPer100g * factor,
          carbsG: record.carbsPer100g * factor,
          fatG: record.fatPer100g == null ? null : record.fatPer100g! * factor,
          fibreG: record.fibrePer100g == null ? null : record.fibrePer100g! * factor,
        );
      }

      final confidence = deriveFoodConfidence(
        foodResolved: true,
        hasUnresolvedText: false,
        nutrientDataAvailable: record != null,
        gramsKnown: gramsKnown,
        exactMeasurementGiven: exactMeasurement,
        approximate: quantityResult.approximate,
        portionRuleConfidence: portionRuleConfidence,
      );

      return FoodParseItem(
        quantity: quantityResult.quantity,
        approximate: quantityResult.approximate,
        unit: unit,
        size: sizeFullness.size,
        fullness: sizeFullness.fullness,
        canonicalId: baseEntry.id,
        canonicalName: baseEntry.canonical,
        matchedAlias: resolution.matchedAlias,
        modifiers: modPrep.modifiers,
        preparations: modPrep.preparations,
        grams: totalGrams,
        nutrition: nutritionTotals,
        confidence: confidence,
        suggestions: resolution.suggestions,
      );
    }

    return const FoodParseItem(quantity: 1, confidence: ParseConfidence.incomplete);
  }
}
