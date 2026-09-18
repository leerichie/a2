import 'aliases/personal_alias_repository.dart';
import 'catalogue/activity_catalogue.dart';
import 'catalogue/alias_index.dart';
import 'catalogue/asset_reader.dart';
import 'catalogue/lexicon.dart';
import 'models/exercise_parse_item.dart';
import 'models/parse_confidence.dart';
import 'pipeline/activity_resolver.dart';
import 'pipeline/confidence_engine.dart';
import 'pipeline/exercise_quantity_parser.dart';
import 'pipeline/spell_correction.dart';
import 'pipeline/text_normalizer.dart';
import 'pipeline/token_matching.dart';

// A single mention of "steps" with no other duration/activity information
// implies walking, converted via a standard, commonly-cited walking
// cadence (~100 steps/minute) -- a real reference figure, not a guessed
// pace, the same way earlier portion defaults reused known constants
// rather than inventing one.
const _stepsPerMinute = 100.0;

class ExerciseParser {
  const ExerciseParser({
    required this.catalogue,
    required this.aliasIndex,
    required this.lexicon,
    required this.vocabulary,
    this.personalAliases,
    this.locale = 'en',
  });

  final ActivityCatalogue catalogue;
  final AliasIndex aliasIndex;
  final Lexicon lexicon;
  // Every known word (activity aliases/canonical names + lexicon time/
  // distance/step units + filler/approximation words), diacritic-folded --
  // the same typo-correction mechanism food uses, built once per locale.
  final Set<String> vocabulary;
  final PersonalAliasRepository? personalAliases;
  final String locale;

  static Future<ExerciseParser> load({
    String locale = 'en',
    AssetReader reader = defaultAssetReader,
    PersonalAliasRepository? personalAliases,
  }) async {
    final catalogue = await ActivityCatalogue.load(locale: locale, reader: reader);
    final lexicon = await Lexicon.load(locale: locale, reader: reader);
    // See FoodParser.load for why this no longer throws: a colliding
    // overlay/contributed alias must never take the whole parser down --
    // AliasIndex.build's first-registration-wins rule (bundled entries
    // listed first, above) already keeps bundled/trusted data authoritative.
    final aliasIndex = AliasIndex.build({
      for (final e in catalogue.entries) e.id: [...e.aliases, e.canonical],
    });
    final vocabulary = buildVocabulary([
      for (final e in catalogue.entries) ...[...e.aliases, e.canonical],
      ...lexicon.timeUnitByAlias.keys,
      ...lexicon.distanceUnitByAlias.keys,
      ...lexicon.stepUnitWords,
      ...lexicon.approximationWords,
      ...lexicon.activityFillerWords,
      ...lexicon.connectorWords,
    ]);
    return ExerciseParser(
      catalogue: catalogue,
      aliasIndex: aliasIndex,
      lexicon: lexicon,
      vocabulary: vocabulary,
      personalAliases: personalAliases,
      locale: locale,
    );
  }

  /// [bodyWeightKg] is a required parameter, not read from app state, so the
  /// parser has no implicit dependency on where the caller keeps the user's
  /// profile -- Phase 3 passes `BodyProfile.weightKg` explicitly.
  ///
  /// Unlike food, a duration/distance/step count can appear anywhere in a
  /// natural activity sentence ("played singles tennis for 2 hours"), not
  /// just at the front, and there can be more than one ("cycled 10km in
  /// 30min") -- [parseExerciseQuantity] finds and removes all of them
  /// before the remaining words (typo-corrected, filler words dropped)
  /// are matched against the activity catalogue.
  ExerciseParseItem parse(String input, {required double? bodyWeightKg}) {
    final normalized = normalizeParserText(input);
    final quantity = parseExerciseQuantity(normalized, lexicon);
    var remaining = correctSpelling(quantity.remainder, vocabulary);
    remaining = removeFillerWords(remaining, lexicon.activityFillerWords);
    remaining = remaining.trim();

    var resolution = resolveActivity(remaining, catalogue, aliasIndex,
        personalAliases: personalAliases, locale: locale);

    var minutes = quantity.minutes;
    var approximate = quantity.approximate;
    // Bare step count with no activity named at all defaults to walking --
    // steps are inherently a walking measure, not a guess at which sport.
    if (resolution.entry == null && remaining.isEmpty && quantity.steps != null) {
      resolution = resolveActivity('walking', catalogue, aliasIndex,
          personalAliases: personalAliases, locale: locale);
    }
    if (minutes == null && quantity.steps != null && resolution.entry?.id == 'walking') {
      minutes = quantity.steps! / _stepsPerMinute;
      approximate = true;
    }

    if (resolution.entry == null) {
      return ExerciseParseItem(
        durationMinutes: minutes,
        approximate: approximate,
        confidence: ParseConfidence.incomplete,
        suggestions: resolution.suggestions,
      );
    }

    final entry = resolution.entry!;
    final durationKnown = minutes != null;
    final bodyWeightKnown = bodyWeightKg != null && bodyWeightKg > 0;

    double? calorieEstimate;
    if (durationKnown && bodyWeightKnown) {
      calorieEstimate = entry.met * bodyWeightKg * (minutes / 60.0);
    }

    final confidence = deriveExerciseConfidence(
      activityResolved: true,
      durationKnown: durationKnown,
      bodyWeightKnown: bodyWeightKnown,
      approximate: approximate,
    );

    return ExerciseParseItem(
      activityId: entry.id,
      canonicalActivity: entry.canonical,
      matchedAlias: resolution.matchedAlias,
      durationMinutes: minutes,
      intensity: entry.intensity,
      met: entry.met,
      approximate: approximate,
      calorieEstimateKcal: calorieEstimate,
      confidence: confidence,
    );
  }
}
