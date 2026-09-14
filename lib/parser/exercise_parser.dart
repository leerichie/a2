import 'aliases/personal_alias_repository.dart';
import 'catalogue/activity_catalogue.dart';
import 'catalogue/alias_index.dart';
import 'catalogue/asset_reader.dart';
import 'catalogue/lexicon.dart';
import 'models/exercise_parse_item.dart';
import 'models/parse_confidence.dart';
import 'pipeline/activity_resolver.dart';
import 'pipeline/confidence_engine.dart';
import 'pipeline/duration_parser.dart';
import 'pipeline/text_normalizer.dart';

class ExerciseParser {
  const ExerciseParser({
    required this.catalogue,
    required this.aliasIndex,
    required this.lexicon,
    this.personalAliases,
    this.locale = 'en',
  });

  final ActivityCatalogue catalogue;
  final AliasIndex aliasIndex;
  final Lexicon lexicon;
  final PersonalAliasRepository? personalAliases;
  final String locale;

  static Future<ExerciseParser> load({
    String locale = 'en',
    AssetReader reader = defaultAssetReader,
    PersonalAliasRepository? personalAliases,
  }) async {
    final catalogue = await ActivityCatalogue.load(locale: locale, reader: reader);
    final lexicon = await Lexicon.load(locale: locale, reader: reader);
    final aliasIndex = AliasIndex.build({
      for (final e in catalogue.entries) e.id: [...e.aliases, e.canonical],
    });
    if (aliasIndex.collisions.isNotEmpty) {
      throw StateError('Activity alias collisions: ${aliasIndex.collisions}');
    }
    return ExerciseParser(
      catalogue: catalogue,
      aliasIndex: aliasIndex,
      lexicon: lexicon,
      personalAliases: personalAliases,
      locale: locale,
    );
  }

  /// [bodyWeightKg] is a required parameter, not read from app state, so the
  /// parser has no implicit dependency on where the caller keeps the user's
  /// profile -- Phase 3 passes `BodyProfile.weightKg` explicitly.
  ExerciseParseItem parse(String input, {required double? bodyWeightKg}) {
    final normalized = normalizeParserText(input);
    final duration = parseDuration(normalized, lexicon);
    final remaining = duration.remainder.trim();

    final resolution = resolveActivity(remaining, catalogue, aliasIndex,
        personalAliases: personalAliases, locale: locale);

    if (resolution.entry == null) {
      return ExerciseParseItem(
        durationMinutes: duration.minutes,
        approximate: duration.approximate,
        confidence: ParseConfidence.incomplete,
        suggestions: resolution.suggestions,
      );
    }

    final entry = resolution.entry!;
    final durationKnown = duration.minutes != null;
    final bodyWeightKnown = bodyWeightKg != null && bodyWeightKg > 0;

    double? calorieEstimate;
    if (durationKnown && bodyWeightKnown) {
      calorieEstimate = entry.met * bodyWeightKg * (duration.minutes! / 60.0);
    }

    final confidence = deriveExerciseConfidence(
      activityResolved: true,
      durationKnown: durationKnown,
      bodyWeightKnown: bodyWeightKnown,
      approximate: duration.approximate,
    );

    return ExerciseParseItem(
      activityId: entry.id,
      canonicalActivity: entry.canonical,
      matchedAlias: resolution.matchedAlias,
      durationMinutes: duration.minutes,
      intensity: entry.intensity,
      met: entry.met,
      approximate: duration.approximate,
      calorieEstimateKcal: calorieEstimate,
      confidence: confidence,
    );
  }
}
