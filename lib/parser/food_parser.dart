import 'package:shared_preferences/shared_preferences.dart';

import 'aliases/personal_alias.dart';
import 'aliases/personal_alias_repository.dart';
import 'catalogue/alias_index.dart';
import 'catalogue/asset_reader.dart';
import 'catalogue/food_catalogue.dart';
import 'catalogue/lexicon.dart';
import 'catalogue/local_overlay.dart';
import 'catalogue/nutrition_catalogue.dart';
import 'catalogue/portion_catalogue.dart';
import 'catalogue/recipe_catalogue.dart';
import 'models/food_parse_item.dart';
import 'models/nutrient_totals.dart';
import 'models/unresolved_span.dart';
import 'pipeline/confidence_engine.dart';
import 'pipeline/food_resolver.dart';
import 'pipeline/household_portion_parser.dart';
import 'pipeline/measurement_parser.dart';
import 'pipeline/modifier_preparation_parser.dart';
import 'pipeline/quantity_parser.dart';
import 'pipeline/segmenter.dart';
import 'pipeline/size_fullness_parser.dart';
import 'pipeline/spell_correction.dart';
import 'pipeline/text_normalizer.dart';

/// Categories liquid enough that a household container word (glass/mug/
/// cup/bottle/carton) should fall back to a standard volume conversion
/// rather than staying incomplete: drinks proper, plus dairy (milk,
/// drinking yoghurt) which is routinely poured the same way.
const pourableCategories = {'drink', 'dairy'};

class FoodParser {
  const FoodParser({
    required this.catalogue,
    required this.aliasIndex,
    required this.lexicon,
    required this.nutrition,
    required this.portions,
    required this.drinkContainers,
    required this.genericVolume,
    required this.vocabulary,
    this.personalAliases,
    this.locale = 'en',
  });

  final FoodCatalogue catalogue;
  final AliasIndex aliasIndex;
  final Lexicon lexicon;
  final NutritionCatalogue nutrition;
  final PortionCatalogue portions;
  final DrinkContainerCatalogue drinkContainers;
  final GenericVolumeCatalogue genericVolume;
  // Every known word (catalogue aliases/canonical names + lexicon units/
  // sizes/modifiers/preparations/...), diacritic-folded, for this locale --
  // what typo correction is allowed to land on. Built once at load time,
  // not per parse() call.
  final Set<String> vocabulary;
  final PersonalAliasRepository? personalAliases;
  final String locale;

  static Future<FoodParser> load({
    String locale = 'en',
    AssetReader reader = defaultAssetReader,
    PersonalAliasRepository? personalAliases,
  }) async {
    personalAliases ??= PersonalAliasRepository(
      await SharedPreferences.getInstance(),
    );
    final bundledCatalogue = await FoodCatalogue.load(
      locale: locale,
      reader: reader,
    );
    final lexicon = await Lexicon.load(locale: locale, reader: reader);
    final bundledNutrition = await NutritionCatalogue.load(reader: reader);
    final bundledPortions = await PortionCatalogue.load(reader: reader);
    final drinkContainers = await DrinkContainerCatalogue.load(reader: reader);
    final genericVolume = await GenericVolumeCatalogue.load(reader: reader);

    // The local overlay (foods the user added, plus anything synced down
    // from the backend's global catalogue -- see CatalogueSyncService) is
    // merged in ADDITIVELY here: it can only fill a gap (an id the bundled
    // catalogue doesn't already have), never override bundled/trusted data,
    // mirroring the exact same precedence rule the backend enforces.
    final overlay = await LocalCatalogueOverlay.load();
    final bundledIds = bundledCatalogue.entries.map((e) => e.id).toSet();
    final newOverlayEntries = overlay.entries.where(
      (e) => !bundledIds.contains(e.id),
    );
    final catalogue = FoodCatalogue([
      ...bundledCatalogue.entries,
      for (final o in newOverlayEntries)
        FoodCatalogueEntry(
          id: o.id,
          canonical: o.canonical,
          category: o.category ?? 'other',
          aliases: [...o.aliasesEn, ...o.aliasesPl],
        ),
    ]);
    final nutrition = NutritionCatalogue({
      for (final e in bundledCatalogue.entries)
        if (bundledNutrition.forFoodId(e.id) != null)
          e.id: bundledNutrition.forFoodId(e.id)!,
      for (final o in newOverlayEntries)
        o.id: NutrientRecord(
          foodId: o.id,
          kcalPer100g: o.kcalPer100g,
          proteinPer100g: o.proteinPer100g ?? 0,
          carbsPer100g: o.carbsPer100g ?? 0,
          fatPer100g: o.fatPer100g,
          fibrePer100g: o.fibrePer100g,
          source: o.source,
        ),
    });
    final portions = PortionCatalogue([
      ...bundledPortions.rules,
      for (final o in newOverlayEntries)
        if (o.servingAmount != null)
          PortionRule(
            foodId: o.id,
            foodNameAsGiven: o.canonical,
            unit: null,
            size: null,
            grams: o.servingAmount!,
            confidence: 'medium',
          ),
    ]);

    // A prepared/composite dish with no nutrient record of its own (and no
    // genericParent to borrow from -- see `catalogue` above) can still get
    // a real bare-mention default: compose one from a typical recipe of
    // already-real ingredients (see food_recipes.json), the same real per-
    // ingredient data any explicitly-spelled-out sentence already uses. If
    // any listed ingredient is itself missing nutrient/portion data, the
    // whole recipe is skipped rather than guessing a partial total -- this
    // only ever fills a genuine gap, never invents a number.
    final recipes = await RecipeCatalogue.load(reader: reader);
    final catalogueById = {for (final e in catalogue.entries) e.id: e};
    final recipeNutrients = <String, NutrientRecord>{};
    final recipePortions = <PortionRule>[];
    for (final recipe in recipes.recipes) {
      if (nutrition.forFoodId(recipe.foodId) != null) continue;
      final parent = catalogueById[recipe.foodId]?.genericParent;
      if (parent != null && nutrition.forFoodId(parent) != null) continue;

      var totalGrams = 0.0;
      var totalKcal = 0.0;
      var totalProtein = 0.0;
      var totalCarbs = 0.0;
      double? totalFat;
      double? totalFibre;
      var complete = true;
      for (final ingredient in recipe.ingredients) {
        final record = nutrition.forFoodId(ingredient.foodId);
        // Same fallback order as a real sentence gets in _parseSegment: a
        // food-specific portion rule first, then the standard-volume
        // conversion (teaspoon/tablespoon/...) shared by any food -- e.g.
        // mayonnaise only has its own "tablespoon" rule, so "1 teaspoon
        // mayonnaise" in a recipe has to resolve the same way a user
        // typing that phrase directly would.
        final rule = portions.lookup(
          foodId: ingredient.foodId,
          unit: ingredient.unit,
        );
        final gramsPerUnit =
            rule?.grams ??
            (ingredient.unit == null
                ? null
                : genericVolume.lookup(ingredient.unit!)?.ml);
        if (record == null || gramsPerUnit == null) {
          complete = false;
          break;
        }
        final grams = gramsPerUnit * ingredient.quantity;
        final factor = grams / 100.0;
        totalGrams += grams;
        totalKcal += record.kcalPer100g * factor;
        totalProtein += record.proteinPer100g * factor;
        totalCarbs += record.carbsPer100g * factor;
        if (record.fatPer100g != null) {
          totalFat = (totalFat ?? 0) + record.fatPer100g! * factor;
        }
        if (record.fibrePer100g != null) {
          totalFibre = (totalFibre ?? 0) + record.fibrePer100g! * factor;
        }
      }
      if (!complete || totalGrams <= 0) continue;

      recipeNutrients[recipe.foodId] = NutrientRecord(
        foodId: recipe.foodId,
        kcalPer100g: totalKcal / totalGrams * 100,
        proteinPer100g: totalProtein / totalGrams * 100,
        carbsPer100g: totalCarbs / totalGrams * 100,
        fatPer100g: totalFat == null ? null : totalFat / totalGrams * 100,
        fibrePer100g: totalFibre == null ? null : totalFibre / totalGrams * 100,
        source: recipe.source ?? 'derived from default recipe composition',
      );
      recipePortions.add(
        PortionRule(
          foodId: recipe.foodId,
          foodNameAsGiven:
              catalogueById[recipe.foodId]?.canonical ?? recipe.foodId,
          unit: null,
          size: null,
          grams: totalGrams,
          // A composed default, not a food-specific measurement someone
          // actually recorded -- deliberately lower confidence than a real
          // authored portion rule (see deriveFoodConfidence).
          confidence: 'low',
        ),
      );
    }
    final nutritionWithRecipes = NutritionCatalogue({
      for (final e in catalogue.entries)
        if (nutrition.forFoodId(e.id) != null) e.id: nutrition.forFoodId(e.id)!,
      ...recipeNutrients,
    });
    final portionsWithRecipes = PortionCatalogue([
      ...portions.rules,
      ...recipePortions,
    ]);
    // Bundled entries are listed first (see `catalogue` above), and
    // AliasIndex.build resolves a collision by first registration -- so a
    // synced/contributed overlay food that happens to reuse a bundled
    // word (a bad global-catalogue contribution, a personal "add this
    // food" that collides with something already in the app) never wins
    // and, critically, never takes the whole parser down: this used to
    // throw here, which meant one bad word anywhere in a user's synced
    // catalogue permanently broke adding ANY food for them, with no
    // recovery short of clearing app data. Dataset-quality checks for the
    // BUNDLED catalogue alone still run separately (see
    // test/parser/alias_collision_test.dart), unaffected by this.
    final aliasIndex = AliasIndex.build({
      for (final e in catalogue.entries) e.id: [...e.aliases, e.canonical],
    });
    final vocabulary = buildVocabulary([
      for (final e in catalogue.entries) ...[...e.aliases, e.canonical],
      ...lexicon.unitByAlias.keys,
      ...lexicon.sizeByAlias.keys,
      ...lexicon.fullnessByAlias.keys,
      ...lexicon.preparations,
      ...lexicon.modifiers,
      ...lexicon.approximationWords,
      ...lexicon.amountDescriptors,
      ...lexicon.connectorWords,
      ...lexicon.cardinals.keys,
      ...lexicon.multipliers.keys,
      ...lexicon.fractions.keys,
    ]);
    return FoodParser(
      catalogue: catalogue,
      aliasIndex: aliasIndex,
      lexicon: lexicon,
      nutrition: nutritionWithRecipes,
      portions: portionsWithRecipes,
      drinkContainers: drinkContainers,
      genericVolume: genericVolume,
      vocabulary: vocabulary,
      personalAliases: personalAliases,
      locale: locale,
    );
  }

  /// Remembers wording that AI mapped to an existing canonical food so the
  /// same input resolves locally next time without another API call.
  Future<void> rememberAlias(String phrase, String canonicalId) async {
    final repository = personalAliases;
    final normalized = normalizeAlias(phrase);
    if (repository == null || normalized.isEmpty) return;
    if (repository.resolve(normalized, PersonalAliasKind.food, locale) ==
        canonicalId) {
      return;
    }
    await repository.add(
      locale: locale,
      kind: PersonalAliasKind.food,
      phrase: phrase.trim(),
      normalizedPhrase: normalized,
      canonicalId: canonicalId,
    );
  }

  FoodParseResult parse(String input) {
    final normalized = normalizeParserText(input);
    final segments = segmentPhrases(normalized, lexicon, aliasIndex);
    final items = <FoodParseItem>[];
    final unresolved = <UnresolvedSpan>[];
    var cursor = 0;

    for (final segment in segments) {
      final item = _parseSegment(segment);
      if (item != null) {
        items.add(item);
      } else {
        unresolved.add(
          UnresolvedSpan(segment, cursor, cursor + segment.length),
        );
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

    // Typo/fuzzy correction runs once, here -- after quantities and any
    // exact "500ml"/"2x25g" measurement have already been extracted from
    // the untouched text (so a fuzzy match can never change a quantity),
    // and before every remaining exact-match stage (size/unit/modifier/
    // preparation/food) that follows, so a near-miss spelling of any of
    // those word kinds gets fixed generically in one place rather than
    // patched per phrase.
    remaining = correctSpelling(remaining, vocabulary);

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
      // Some household-portion units are self-referential meat-cut words
      // ("sausage", "steak", "fillet", ...) that are *also* valid food
      // names in their own right. If consuming it as a unit left nothing
      // else to resolve as food ("sausage", "3 sausages"), it was actually
      // the food -- try resolving the unit word itself before giving up.
      if (unit != null && remaining.trim().isEmpty) {
        final asFood = resolveFood(
          unit,
          catalogue,
          aliasIndex,
          personalAliases: personalAliases,
          locale: locale,
        );
        if (asFood.entry != null) {
          remaining = unit;
          unit = null;
        }
      }
    }

    // Modifiers (fat-content/attribute words: "light", "low fat", ...) are
    // always stripped unconditionally -- the dataset's own fixtures require
    // "light mayo" to resolve to generic mayonnaise + modifier, even though
    // a dedicated "light_mayonnaise" catalogue entry also exists.
    final modifierResult = stripModifiers(remaining, lexicon);
    remaining = modifierResult.remainder;

    var preparations = const <String>[];
    var resolution = const FoodResolution();
    if (remaining.trim().isNotEmpty) {
      // Try the whole phrase first, preparation word(s) still attached
      // ("smoked salmon", "boiled egg") -- some catalogue entries are
      // deliberately compound because the cooking method materially
      // changes nutrition, and must win over generically stripping the
      // word and losing that more specific identity.
      resolution = resolveFood(
        remaining,
        catalogue,
        aliasIndex,
        personalAliases: personalAliases,
        locale: locale,
      );
      if (resolution.entry == null) {
        final prepResult = stripPreparations(remaining, lexicon);
        preparations = prepResult.preparations;
        remaining = prepResult.remainder;
        if (remaining.trim().isNotEmpty) {
          resolution = resolveFood(
            remaining,
            catalogue,
            aliasIndex,
            personalAliases: personalAliases,
            locale: locale,
          );
        }
      }
    }

    if (remaining.trim().isNotEmpty) {
      if (resolution.entry == null) return null;

      final entry = resolution.entry!;
      final baseEntry = entry.baseFoodId != null
          ? catalogue.entries.firstWhere(
              (e) => e.id == entry.baseFoodId,
              orElse: () => entry,
            )
          : entry;
      final nutrientLookupId = baseEntry.id;
      var record = nutrition.forFoodId(nutrientLookupId);
      var usedGenericParentFallback = false;
      if (record == null && baseEntry.genericParent != null) {
        record = nutrition.forFoodId(baseEntry.genericParent!);
        if (record != null) usedGenericParentFallback = true;
      }

      double? gramsPerUnit;
      bool exactMeasurement = false;
      String? portionRuleConfidence;
      if (measurement.grams != null) {
        gramsPerUnit = measurement.grams;
        exactMeasurement = true;
      } else if (measurement.millilitres != null) {
        gramsPerUnit =
            measurement.millilitres; // density-neutral: ml treated 1:1 for now
        exactMeasurement = true;
      } else {
        // `unit == null` here looks up the bare-mention default portion
        // ("egg", "banana" with no unit at all) -- food-specific, not a
        // global assumption (see PortionCatalogue.lookup).
        final rule = portions.lookup(
          foodId: nutrientLookupId,
          unit: unit,
          size: sizeFullness.size,
        );
        if (rule != null) {
          gramsPerUnit = rule.grams;
          portionRuleConfidence = rule.confidence;
        } else if (unit != null &&
            pourableCategories.contains(baseEntry.category)) {
          // No food-specific rule for this drink+unit -- fall back to the
          // standard container volume (glass/mug/cup/bottle/carton) shared
          // with WaterIntakeParser. Covers both `drink` (beer, wine, ...)
          // and `dairy` (milk, drinking yoghurt) since both are routinely
          // poured into a glass/mug -- never applies to a bare mention
          // with no unit at all (the old universal "25ml" default is gone).
          final containerMl = drinkContainers.millilitresFor(unit);
          if (containerMl != null) {
            gramsPerUnit = containerMl;
            portionRuleConfidence = 'medium';
          }
        }
        if (gramsPerUnit == null && unit != null) {
          // Standard-volume unit (teaspoon/tablespoon/dessertspoon/cup/
          // fluid_ounce/spoonful) applicable to ANY food, not just drinks --
          // e.g. "spoon light cottage cheese". Density-neutral ml-as-grams,
          // same simplification as the drink-container fallback above.
          final generic = genericVolume.lookup(unit);
          if (generic != null) {
            gramsPerUnit = generic.ml;
            portionRuleConfidence = generic.confidence;
          }
        }
      }

      final totalGrams = gramsPerUnit == null
          ? null
          : gramsPerUnit * quantityResult.quantity;
      final gramsKnown = totalGrams != null;

      NutrientTotals? nutritionTotals;
      if (record != null && gramsKnown) {
        final factor = totalGrams / 100.0;
        nutritionTotals = NutrientTotals(
          kcal: record.kcalPer100g * factor,
          proteinG: record.proteinPer100g * factor,
          carbsG: record.carbsPer100g * factor,
          fatG: record.fatPer100g == null ? null : record.fatPer100g! * factor,
          fibreG: record.fibrePer100g == null
              ? null
              : record.fibrePer100g! * factor,
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
        nutrientDataIsFallback: usedGenericParentFallback,
      );

      return FoodParseItem(
        quantity: quantityResult.quantity,
        approximate: quantityResult.approximate,
        unit: unit,
        size: sizeFullness.size,
        fullness: sizeFullness.fullness,
        canonicalId: baseEntry.id,
        canonicalName: baseEntry.canonical,
        category: baseEntry.category,
        matchedAlias: resolution.matchedAlias,
        modifiers: modifierResult.modifiers,
        preparations: preparations,
        grams: totalGrams,
        nutrition: nutritionTotals,
        confidence: confidence,
        suggestions: resolution.suggestions,
      );
    }

    // Grammar words consumed the whole segment (a bare number, a lone
    // approximation word, ...) with no food identity left at all -- that's
    // genuinely unresolved, not a placeholder item with no canonical id.
    return null;
  }
}
