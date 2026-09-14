import 'dart:convert';

import 'alias_index.dart';
import 'asset_reader.dart';

Map<String, String> _reverseIndex(Map<String, dynamic> canonicalToAliases) {
  final index = <String, String>{};
  for (final entry in canonicalToAliases.entries) {
    for (final alias in (entry.value as List<dynamic>).cast<String>()) {
      index[normalizeAlias(alias)] = entry.key;
    }
  }
  return index;
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

  static Future<Lexicon> load({
    String locale = 'en',
    AssetReader reader = defaultAssetReader,
  }) async {
    Future<Map<String, dynamic>> obj(String name) async =>
        json.decode(await reader('assets/parser/$locale/lexicon/$name.json'))
            as Map<String, dynamic>;

    final numbers = await obj('numbers_and_multipliers');
    final sizes = await obj('sizes_and_fullness');
    final units = await obj('units_and_portions');
    final approx = await obj('approximation_and_connectors');
    final prepMod = await obj('preparations_and_modifiers');
    final intensity = await obj('intensity_modifiers');
    final duration = await obj('time_and_duration');

    final unitGroups = <String, dynamic>{
      ...units['standard_volume'] as Map<String, dynamic>,
      ...units['approx_household'] as Map<String, dynamic>,
      ...units['count_piece'] as Map<String, dynamic>,
      ...units['packaging'] as Map<String, dynamic>,
    };

    return Lexicon(
      cardinals: (numbers['cardinals'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as int)),
      multipliers: (numbers['multipliers'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as int)),
      acceptedMultiplierPatterns:
          (numbers['accepted_patterns'] as List<dynamic>).cast<String>(),
      fractions: (numbers['fractions'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toDouble())),
      sizeByAlias: _reverseIndex(sizes['canonical'] as Map<String, dynamic>),
      fullnessByAlias: _reverseIndex(sizes['fullness'] as Map<String, dynamic>),
      unitByAlias: _reverseIndex(unitGroups),
      approximationWords: (approx['approximation_words'] as List<dynamic>).cast<String>(),
      amountDescriptors: (approx['amount_descriptors'] as List<dynamic>).cast<String>(),
      connectorWords: (approx['connector_words'] as List<dynamic>).cast<String>(),
      preparations: (prepMod['preparations'] as List<dynamic>).cast<String>(),
      modifiers: (prepMod['modifiers'] as List<dynamic>).cast<String>(),
      intensityByAlias: _reverseIndex(intensity),
      timeUnitByAlias: _reverseIndex(duration['units'] as Map<String, dynamic>),
      durationPhraseMinutes: (duration['fractions'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toDouble())),
    );
  }
}
