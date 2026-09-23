import 'dart:convert';

import 'asset_reader.dart';
import 'locales.dart';

class FoodCatalogueEntry {
  const FoodCatalogueEntry({
    required this.id,
    required this.canonical,
    required this.category,
    this.region,
    this.baseFoodId,
    this.modifiers = const [],
    this.aliases = const [],
    this.genericParent,
  });

  final String id;
  final String canonical;
  final String category;
  final String? region;
  final String? baseFoodId;
  final List<String> modifiers;
  final List<String> aliases;
  // A taxonomic fact ("cheddar is a cheese"), not an invented value: when
  // this subtype has no nutrient record of its own, its generic parent's
  // real data may be used as a fallback (always flagged Low confidence by
  // the caller, since it's an approximation, not the subtype's own data).
  final String? genericParent;
}

class FoodCatalogue {
  const FoodCatalogue(this.entries);
  final List<FoodCatalogueEntry> entries;

  /// [locale] is unused for catalogue loading -- input recognition is
  /// never restricted to one language: aliases from every installed
  /// locale pack (see [installedLocales]) are always merged into one
  /// shared vocabulary, so "kromka chleba" and "slice of bread" both
  /// resolve in the same parse() call regardless of the app's UI
  /// language. The parameter stays for API compatibility with callers
  /// that still pass it (e.g. for future locale-scoped personal aliases).
  static Future<FoodCatalogue> load({
    String locale = 'en',
    AssetReader reader = defaultAssetReader,
  }) async {
    final sharedRaw = await reader('assets/parser/shared/food_catalogue.json');
    final shared = json.decode(sharedRaw) as List<dynamic>;

    final aliasesByLocale = await Future.wait(
      installedLocales.map((l) => reader('assets/parser/$l/food_aliases.json')),
    );
    final mergedAliases = <String, List<String>>{};
    for (final raw in aliasesByLocale) {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        final words = (entry.value as List<dynamic>).cast<String>();
        (mergedAliases[entry.key] ??= []).addAll(words);
      }
    }

    final entries = shared.map((raw) {
      final m = raw as Map<String, dynamic>;
      final id = m['id'] as String;
      return FoodCatalogueEntry(
        id: id,
        canonical: m['canonical'] as String,
        category: m['category'] as String,
        region: m['region'] as String?,
        baseFoodId: m['base_food'] as String?,
        modifiers:
            (m['modifiers'] as List<dynamic>?)?.cast<String>() ?? const [],
        aliases: mergedAliases[id] ?? const [],
        genericParent: m['genericParent'] as String?,
      );
    }).toList();

    return FoodCatalogue(entries);
  }
}
