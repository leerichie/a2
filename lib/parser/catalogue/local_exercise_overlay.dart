import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A single AI-contributed activity or synced global-catalogue activity,
/// stored in the SAME shape the backend catalogue uses (see
/// server/src/exercise_catalogue.mjs) -- the exercise counterpart of
/// OverlayFoodEntry (see local_overlay.dart).
class OverlayExerciseEntry {
  const OverlayExerciseEntry({
    required this.id,
    required this.canonical,
    this.category,
    this.aliasesEn = const [],
    this.aliasesPl = const [],
    required this.met,
    required this.source,
  });

  final String id;
  final String canonical;
  final String? category;
  final List<String> aliasesEn;
  final List<String> aliasesPl;
  final double met;
  final String source;

  Map<String, dynamic> toJson() => {
    'id': id,
    'canonical': canonical,
    'category': category,
    'aliasesEn': aliasesEn,
    'aliasesPl': aliasesPl,
    'met': met,
    'source': source,
  };

  factory OverlayExerciseEntry.fromJson(Map<String, dynamic> j) =>
      OverlayExerciseEntry(
        id: j['id'] as String,
        canonical: j['canonical'] as String,
        category: j['category'] as String?,
        aliasesEn: (j['aliasesEn'] as List?)?.cast<String>() ?? const [],
        aliasesPl: (j['aliasesPl'] as List?)?.cast<String>() ?? const [],
        met: (j['met'] as num).toDouble(),
        source: j['source'] as String? ?? 'user',
      );

  /// Mirrors OverlayFoodEntry.idFor -- a stable id derived from the
  /// activity's own name, so re-contributing "kickboxing" twice locally
  /// lands on one entry, not two.
  static String idFor(String name) {
    final normalized = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return 'local_$normalized';
  }
}

/// The local half of the shared canonical system for exercise: activities
/// AI has identified on this device, plus activities downloaded from the
/// backend's global exercise catalogue (see ExerciseCatalogueSyncService) --
/// merged into the parser's in-memory catalogue at load time (see
/// exercise_parser.dart) as an ADDITIVE layer, mirroring exactly how
/// LocalCatalogueOverlay works for food.
class LocalExerciseCatalogueOverlay {
  const LocalExerciseCatalogueOverlay(this.entries);
  final List<OverlayExerciseEntry> entries;

  static const _prefsKey = 'local_exercise_catalogue_overlay';
  static const _versionKey = 'exercise_catalogue_version';

  static Future<LocalExerciseCatalogueOverlay> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return const LocalExerciseCatalogueOverlay([]);
    final list = (json.decode(raw) as List<dynamic>)
        .map((e) => OverlayExerciseEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    return LocalExerciseCatalogueOverlay(list);
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      json.encode(entries.map((e) => e.toJson()).toList()),
    );
  }

  Future<LocalExerciseCatalogueOverlay> upsert(
    OverlayExerciseEntry entry,
  ) async {
    final updated = [
      ...entries.where((e) => e.id != entry.id),
      entry,
    ];
    final overlay = LocalExerciseCatalogueOverlay(updated);
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
