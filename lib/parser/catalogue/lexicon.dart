import 'dart:convert';

import '../pipeline/text_folding.dart';
import 'alias_index.dart';
import 'asset_reader.dart';
import 'locales.dart';

Map<String, String> _reverseIndex(Map<String, dynamic> canonicalToAliases) {
  final index = <String, String>{};
  for (final entry in canonicalToAliases.entries) {
    for (final alias in (entry.value as List<dynamic>).cast<String>()) {
      index[normalizeAlias(alias)] = entry.key;
    }
  }
  return index;
}

// These raw word lists/keys come straight from the locale's JSON, not
// through `normalizeAlias` -- fold them here so they match the same
// diacritic-folded form the input text is normalized to.
List<String> _foldedList(List<dynamic> raw) =>
    raw.cast<String>().map((w) => foldDiacritics(w.toLowerCase())).toList();

Map<String, T> _foldedKeys<T>(Map<String, T> raw) =>
    raw.map((k, v) => MapEntry(foldDiacritics(k.toLowerCase()), v));

// Merges N locales' versions of the same {canonicalId: [alias words]} map
// (sizes/units/intensity/time-and-distance-units) by unioning the alias
// lists per canonical id -- so "large"/"duży" and "hour"/"godzina" are
// both recognized in the same parse() call, not one parser per language.
Map<String, dynamic> _mergeAliasGroups(Iterable<Map<String, dynamic>> maps) {
  final merged = <String, List<String>>{};
  for (final map in maps) {
    for (final entry in map.entries) {
      final words = (entry.value as List<dynamic>).cast<String>();
      (merged[entry.key] ??= []).addAll(words);
    }
  }
  return merged;
}

// Merges N locales' flat word lists (approximation words, fillers, ...)
// into one deduplicated list.
List<dynamic> _mergeLists(Iterable<List<dynamic>> lists) =>
    {for (final list in lists) ...list.cast<String>()}.toList();

// Merges N locales' scalar maps (word -> number, e.g. cardinals/
// fractions) -- distinct-language word sets, so a plain union is safe.
Map<String, dynamic> _mergeScalarMaps(Iterable<Map<String, dynamic>> maps) {
  final merged = <String, dynamic>{};
  for (final map in maps) {
    merged.addAll(map);
  }
  return merged;
}

class Lexicon {
  const Lexicon({
    required this.cardinals,
    required this.multipliers,
    required this.acceptedMultiplierPatterns,
    required this.fractions,
    required this.sizeByAlias,
    required this.fullnessByAlias,
    required this.unitByAlias,
    required this.approximationWords,
    required this.amountDescriptors,
    required this.connectorWords,
    required this.preparations,
    required this.modifiers,
    required this.intensityByAlias,
    required this.timeUnitByAlias,
    required this.durationPhraseMinutes,
    required this.distanceUnitByAlias,
    required this.stepUnitWords,
    required this.activityFillerWords,
  });

  final Map<String, int> cardinals;
  final Map<String, int> multipliers;
  final List<String> acceptedMultiplierPatterns;
  final Map<String, double> fractions;
  final Map<String, String> sizeByAlias;
  final Map<String, String> fullnessByAlias;
  final Map<String, String> unitByAlias;
  final List<String> approximationWords;
  final List<String> amountDescriptors;
  final List<String> connectorWords;
  final List<String> preparations;
  final List<String> modifiers;
  final Map<String, String> intensityByAlias;
  final Map<String, String> timeUnitByAlias;
  final Map<String, double> durationPhraseMinutes;
  // 'km' or 'm' per alias -- exercise distance, not a food measurement.
  final Map<String, String> distanceUnitByAlias;
  final List<String> stepUnitWords;
  // Generic filler/connector verbs in an activity sentence ("played",
  // "for", "in", ...) -- distinct from `connectorWords` (food-oriented,
  // prefix-only) since these get stripped from anywhere in the phrase.
  final List<String> activityFillerWords;

  /// [locale] is unused -- like the catalogues, every installed locale's
  /// lexicon (units, sizes, numbers, time/distance words, ...) is always
  /// merged into one shared lexicon, so grammar/units from every
  /// installed language pack are recognized in the same input regardless
  /// of the app's UI language.
  static Future<Lexicon> load({
    String locale = 'en',
    AssetReader reader = defaultAssetReader,
  }) async {
    Future<Map<String, dynamic>> obj(String l, String name) async =>
        json.decode(await reader('assets/parser/$l/lexicon/$name.json'))
            as Map<String, dynamic>;

    final numbersByLocale = await Future.wait(
      installedLocales.map((l) => obj(l, 'numbers_and_multipliers')),
    );
    final sizesByLocale = await Future.wait(
      installedLocales.map((l) => obj(l, 'sizes_and_fullness')),
    );
    final unitsByLocale = await Future.wait(
      installedLocales.map((l) => obj(l, 'units_and_portions')),
    );
    final approxByLocale = await Future.wait(
      installedLocales.map((l) => obj(l, 'approximation_and_connectors')),
    );
    final prepModByLocale = await Future.wait(
      installedLocales.map((l) => obj(l, 'preparations_and_modifiers')),
    );
    final intensityByLocale = await Future.wait(
      installedLocales.map((l) => obj(l, 'intensity_modifiers')),
    );
    final durationByLocale = await Future.wait(
      installedLocales.map((l) => obj(l, 'time_and_duration')),
    );

    final numbers = {
      'cardinals': _mergeScalarMaps(numbersByLocale.map((m) => m['cardinals'] as Map<String, dynamic>)),
      'multipliers': _mergeScalarMaps(numbersByLocale.map((m) => m['multipliers'] as Map<String, dynamic>)),
      'accepted_patterns': _mergeLists(numbersByLocale.map((m) => m['accepted_patterns'] as List<dynamic>)),
      'fractions': _mergeScalarMaps(numbersByLocale.map((m) => m['fractions'] as Map<String, dynamic>)),
    };
    final sizesCanonical = _mergeAliasGroups(sizesByLocale.map((m) => m['canonical'] as Map<String, dynamic>));
    final sizesFullness = _mergeAliasGroups(sizesByLocale.map((m) => m['fullness'] as Map<String, dynamic>));
    final unitGroups = _mergeAliasGroups([
      for (final m in unitsByLocale) ...[
        m['standard_volume'] as Map<String, dynamic>,
        m['approx_household'] as Map<String, dynamic>,
        m['count_piece'] as Map<String, dynamic>,
        m['packaging'] as Map<String, dynamic>,
      ],
    ]);
    final approx = {
      'approximation_words': _mergeLists(approxByLocale.map((m) => m['approximation_words'] as List<dynamic>)),
      'amount_descriptors': _mergeLists(approxByLocale.map((m) => m['amount_descriptors'] as List<dynamic>)),
      'connector_words': _mergeLists(approxByLocale.map((m) => m['connector_words'] as List<dynamic>)),
      'activity_filler_words':
          _mergeLists(approxByLocale.map((m) => m['activity_filler_words'] as List<dynamic>)),
    };
    final prepMod = {
      'preparations': _mergeLists(prepModByLocale.map((m) => m['preparations'] as List<dynamic>)),
      'modifiers': _mergeLists(prepModByLocale.map((m) => m['modifiers'] as List<dynamic>)),
    };
    final intensity = _mergeAliasGroups(intensityByLocale);
    final durationUnits = _mergeAliasGroups(durationByLocale.map((m) => m['units'] as Map<String, dynamic>));
    final durationFractions =
        _mergeScalarMaps(durationByLocale.map((m) => m['fractions'] as Map<String, dynamic>));
    final distanceUnits =
        _mergeAliasGroups(durationByLocale.map((m) => m['distance_units'] as Map<String, dynamic>));
    final stepUnits = _mergeLists(durationByLocale.map((m) => m['step_units'] as List<dynamic>));

    return Lexicon(
      cardinals: _foldedKeys(
        (numbers['cardinals'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int)),
      ),
      multipliers: _foldedKeys(
        (numbers['multipliers'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int)),
      ),
      acceptedMultiplierPatterns:
          (numbers['accepted_patterns'] as List<dynamic>).cast<String>(),
      fractions: _foldedKeys(
        (numbers['fractions'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, (v as num).toDouble())),
      ),
      sizeByAlias: _reverseIndex(sizesCanonical),
      fullnessByAlias: _reverseIndex(sizesFullness),
      unitByAlias: _reverseIndex(unitGroups),
      approximationWords: _foldedList(approx['approximation_words'] as List<dynamic>),
      amountDescriptors: _foldedList(approx['amount_descriptors'] as List<dynamic>),
      connectorWords: _foldedList(approx['connector_words'] as List<dynamic>),
      preparations: _foldedList(prepMod['preparations'] as List<dynamic>),
      modifiers: _foldedList(prepMod['modifiers'] as List<dynamic>),
      intensityByAlias: _reverseIndex(intensity),
      timeUnitByAlias: _reverseIndex(durationUnits),
      durationPhraseMinutes: _foldedKeys(
        durationFractions.map((k, v) => MapEntry(k, (v as num).toDouble())),
      ),
      distanceUnitByAlias: _reverseIndex(distanceUnits),
      stepUnitWords: _foldedList(stepUnits),
      activityFillerWords: _foldedList(approx['activity_filler_words'] as List<dynamic>),
    );
  }
}
