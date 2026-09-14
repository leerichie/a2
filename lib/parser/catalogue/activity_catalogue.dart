import 'dart:convert';

import 'asset_reader.dart';

class ActivityCatalogueEntry {
  const ActivityCatalogueEntry({
    required this.id,
    required this.canonical,
    required this.category,
    required this.intensity,
    required this.met,
    this.aliases = const [],
  });

  final String id;
  final String canonical;
  final String category;
  final String intensity;
  final double met;
  final List<String> aliases;
}

class ActivityCatalogue {
  const ActivityCatalogue(this.entries);
  final List<ActivityCatalogueEntry> entries;

  static Future<ActivityCatalogue> load({
    String locale = 'en',
    AssetReader reader = defaultAssetReader,
  }) async {
    final sharedRaw = await reader('assets/parser/shared/activity_catalogue.json');
    final aliasesRaw = await reader('assets/parser/$locale/activity_aliases.json');
    final shared = json.decode(sharedRaw) as List<dynamic>;
    final aliases = json.decode(aliasesRaw) as Map<String, dynamic>;

    final entries = shared.map((raw) {
      final m = raw as Map<String, dynamic>;
      final id = m['id'] as String;
      return ActivityCatalogueEntry(
        id: id,
        canonical: m['canonical'] as String,
        category: m['category'] as String,
        intensity: m['intensity'] as String,
        met: (m['met'] as num).toDouble(),
        aliases: (aliases[id] as List<dynamic>?)?.cast<String>() ?? const [],
      );
    }).toList();

    return ActivityCatalogue(entries);
  }
}
