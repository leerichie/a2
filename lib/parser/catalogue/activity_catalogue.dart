import 'dart:convert';

import 'asset_reader.dart';
import 'locales.dart';

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

  /// See [FoodCatalogue.load] -- [locale] is unused for loading: every
  /// installed locale's aliases are always merged so activity input is
  /// never restricted to the app's UI language.
  static Future<ActivityCatalogue> load({
    String locale = 'en',
    AssetReader reader = defaultAssetReader,
  }) async {
    final sharedRaw = await reader(
      'assets/parser/shared/activity_catalogue.json',
    );
    final shared = json.decode(sharedRaw) as List<dynamic>;

    final aliasesByLocale = await Future.wait(
      installedLocales.map(
        (l) => reader('assets/parser/$l/activity_aliases.json'),
      ),
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
      return ActivityCatalogueEntry(
        id: id,
        canonical: m['canonical'] as String,
        category: m['category'] as String,
        intensity: m['intensity'] as String,
        met: (m['met'] as num).toDouble(),
        aliases: mergedAliases[id] ?? const [],
      );
    }).toList();

    return ActivityCatalogue(entries);
  }
}
