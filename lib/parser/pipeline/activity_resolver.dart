import '../aliases/personal_alias.dart';
import '../aliases/personal_alias_repository.dart';
import '../catalogue/activity_catalogue.dart';
import '../catalogue/alias_index.dart';

class ActivityResolution {
  const ActivityResolution({
    this.entry,
    this.matchedAlias,
    this.suggestions = const [],
  });
  final ActivityCatalogueEntry? entry;
  final String? matchedAlias;
  final List<String> suggestions;
}

/// Unlike food, most activities already encode their intensity in the
/// canonical alias itself ("vigorous swimming", "easy cycling"), so this
/// tries the whole remaining phrase directly rather than stripping a
/// generic intensity word first.
ActivityResolution resolveActivity(
  String phrase,
  ActivityCatalogue catalogue,
  AliasIndex aliasIndex, {
  PersonalAliasRepository? personalAliases,
  String locale = 'en',
}) {
  final trimmed = phrase.trim();
  if (trimmed.isEmpty) return const ActivityResolution();

  final byId = {for (final e in catalogue.entries) e.id: e};

  final personalId = personalAliases?.resolve(
    normalizeAlias(trimmed),
    PersonalAliasKind.activity,
    locale,
  );
  if (personalId != null && byId.containsKey(personalId)) {
    return ActivityResolution(entry: byId[personalId], matchedAlias: trimmed);
  }

  final id = aliasIndex.resolve(trimmed);
  if (id != null && byId.containsKey(id)) {
    return ActivityResolution(entry: byId[id], matchedAlias: trimmed);
  }

  // Substring match against the canonical name AND every locale alias
  // (not canonical alone) -- needed so an ambiguous bare word in any
  // supported language ("tenis", "pływanie") still finds its candidate
  // activities, not just an ambiguous bare English word.
  final lower = trimmed.toLowerCase();
  final suggestions = catalogue.entries
      .where((e) {
        final names = [e.canonical, ...e.aliases].map((n) => n.toLowerCase());
        return names.any((n) => n.contains(lower) || lower.contains(n));
      })
      .map((e) => e.id)
      .take(3)
      .toList();
  return ActivityResolution(suggestions: suggestions);
}
