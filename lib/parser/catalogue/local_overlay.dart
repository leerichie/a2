import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A single "add this food" contribution or synced global-catalogue food,
/// stored in the SAME shape the backend catalogue uses (see
/// server/src/food_catalogue.mjs) so a food a user adds and a food the
/// server later confirms/enriches are literally the same record, not two
/// parallel representations.
class OverlayFoodEntry {
  const OverlayFoodEntry({
    required this.id,
    required this.canonical,
    this.category,
    this.aliasesEn = const [],
    this.aliasesPl = const [],
    required this.kcalPer100g,
    this.proteinPer100g,
    this.carbsPer100g,
    this.fatPer100g,
    this.fibrePer100g,
    this.servingAmount,
    this.servingUnit,
    required this.source,
  });

  final String id;
  final String canonical;
  final String? category;
  final List<String> aliasesEn;
  final List<String> aliasesPl;
  final double kcalPer100g;
  final double? proteinPer100g;
  final double? carbsPer100g;
  final double? fatPer100g;
  final double? fibrePer100g;
  final double? servingAmount;
  final String? servingUnit;
  final String source;

  Map<String, dynamic> toJson() => {
    'id': id,
    'canonical': canonical,
    'category': category,
    'aliasesEn': aliasesEn,
    'aliasesPl': aliasesPl,
    'kcalPer100g': kcalPer100g,
    'proteinPer100g': proteinPer100g,
    'carbsPer100g': carbsPer100g,
    'fatPer100g': fatPer100g,
    'fibrePer100g': fibrePer100g,
    'servingAmount': servingAmount,
    'servingUnit': servingUnit,
    'source': source,
  };

  factory OverlayFoodEntry.fromJson(Map<String, dynamic> j) => OverlayFoodEntry(
    id: j['id'] as String,
    canonical: j['canonical'] as String,
    category: j['category'] as String?,
    aliasesEn: (j['aliasesEn'] as List?)?.cast<String>() ?? const [],
    aliasesPl: (j['aliasesPl'] as List?)?.cast<String>() ?? const [],
    kcalPer100g: (j['kcalPer100g'] as num).toDouble(),
    proteinPer100g: (j['proteinPer100g'] as num?)?.toDouble(),
    carbsPer100g: (j['carbsPer100g'] as num?)?.toDouble(),
    fatPer100g: (j['fatPer100g'] as num?)?.toDouble(),
    fibrePer100g: (j['fibrePer100g'] as num?)?.toDouble(),
    servingAmount: (j['servingAmount'] as num?)?.toDouble(),
    servingUnit: j['servingUnit'] as String?,
    source: j['source'] as String? ?? 'user',
  );

  /// A stable id derived from the food's own name, matching the same
  /// normalization idea the backend uses (see food_catalogue.mjs's
  /// normalizeText) -- so re-adding "Cheddar" twice locally lands on one
  /// entry, not two.
  static String idFor(String name) {
    final normalized = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return 'local_$normalized';
  }
}

/// The local half of the shared canonical system: foods the user has added
/// on this device, plus foods downloaded from the backend's global
/// catalogue (see CatalogueSyncService) -- merged into the parser's
/// in-memory catalogue at load time (see food_parser.dart) as an ADDITIVE
/// layer. It never edits or removes a bundled catalogue/nutrient entry, so
/// the trusted built-in data this app ships with is never at risk.
class LocalCatalogueOverlay {
  const LocalCatalogueOverlay(this.entries);
  final List<OverlayFoodEntry> entries;

  static const _prefsKey = 'local_food_catalogue_overlay';
  static const _versionKey = 'food_catalogue_version';

  static Future<LocalCatalogueOverlay> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return const LocalCatalogueOverlay([]);
    final list = (json.decode(raw) as List<dynamic>)
        .map((e) => OverlayFoodEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    return LocalCatalogueOverlay(list);
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      json.encode(entries.map((e) => e.toJson()).toList()),
    );
  }

  /// Adds/replaces one entry (by id) and saves immediately -- this is what
  /// makes a freshly-added food usable right away, before (or even without)
  /// any network sync.
  Future<LocalCatalogueOverlay> upsert(OverlayFoodEntry entry) async {
    final updated = [...entries.where((e) => e.id != entry.id), entry];
    final overlay = LocalCatalogueOverlay(updated);
    await overlay.save();
    return overlay;
  }

  static Future<int> loadVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_versionKey) ?? 0;
  }

  static Future<void> saveVersion(int version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_versionKey, version);
  }
}
