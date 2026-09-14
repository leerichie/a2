import '../aliases/personal_alias.dart';
import '../aliases/personal_alias_repository.dart';
import '../catalogue/alias_index.dart';
import '../catalogue/food_catalogue.dart';

class FoodResolution {
  const FoodResolution({this.entry, this.matchedAlias, this.suggestions = const []});
  final FoodCatalogueEntry? entry;
  final String? matchedAlias;
  final List<String> suggestions;
}

FoodResolution resolveFood(
  String phrase,
  FoodCatalogue catalogue,
  AliasIndex aliasIndex, {
  PersonalAliasRepository? personalAliases,
  String locale = 'en',
}) {
  final trimmed = phrase.trim();
  if (trimmed.isEmpty) return const FoodResolution();

  final byId = {for (final e in catalogue.entries) e.id: e};

  final personalId = personalAliases?.resolve(
    normalizeAlias(trimmed),
    PersonalAliasKind.food,
    locale,
  );
  if (personalId != null && byId.containsKey(personalId)) {
    return FoodResolution(entry: byId[personalId], matchedAlias: trimmed);
  }

  final id = aliasIndex.resolve(trimmed);
  if (id != null && byId.containsKey(id)) {
    return FoodResolution(entry: byId[id], matchedAlias: trimmed);
  }

  final lower = trimmed.toLowerCase();
  final suggestions = catalogue.entries
      .where((e) =>
          e.canonical.toLowerCase().contains(lower) ||
          lower.contains(e.canonical.toLowerCase()))
      .map((e) => e.id)
      .take(3)
      .toList();
  return FoodResolution(suggestions: suggestions);
}
