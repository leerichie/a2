import 'dart:convert';

import 'asset_reader.dart';

class FoodCatalogueEntry {
  const FoodCatalogueEntry({
    required this.id,
    required this.canonical,
    required this.category,
    this.region,
    this.baseFoodId,
    this.modifiers = const [],
    this.aliases = const [],
  });

  final String id;
  final String canonical;
  final String category;
  final String? region;
  final String? baseFoodId;
  final List<String> modifiers;
  final List<String> aliases;
}

class FoodCatalogue {
  const FoodCatalogue(this.entries);
  final List<FoodCatalogueEntry> entries;

  static Future<FoodCatalogue> load({
    String locale = 'en',
    AssetReader reader = defaultAssetReader,
  }) async {
    final sharedRaw = await reader('assets/parser/shared/food_catalogue.json');
    final aliasesRaw = await reader('assets/parser/$locale/food_aliases.json');
    final shared = json.decode(sharedRaw) as List<dynamic>;
    final aliases = json.decode(aliasesRaw) as Map<String, dynamic>;

    final entries = shared.map((raw) {
      final m = raw as Map<String, dynamic>;
      final id = m['id'] as String;
      return FoodCatalogueEntry(
        id: id,
        canonical: m['canonical'] as String,
        category: m['category'] as String,
        region: m['region'] as String?,
        baseFoodId: m['base_food'] as String?,
        modifiers: (m['modifiers'] as List<dynamic>?)?.cast<String>() ?? const [],
        aliases: (aliases[id] as List<dynamic>?)?.cast<String>() ?? const [],
      );
    }).toList();

    return FoodCatalogue(entries);
  }
}
