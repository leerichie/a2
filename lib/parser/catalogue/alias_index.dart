import '../pipeline/text_folding.dart';

class AliasCollision {
  const AliasCollision(this.alias, this.ids);
  final String alias;
  final List<String> ids;

  @override
  String toString() => '"$alias" -> $ids';
}

String normalizeAlias(String s) => foldDiacritics(s.trim().toLowerCase());

class AliasIndex {
  AliasIndex._(this._byAlias, this.collisions);

  final Map<String, String> _byAlias;
  final List<AliasCollision> collisions;

  static AliasIndex build(Map<String, List<String>> aliasesById) {
    final byAlias = <String, String>{};
    final seenBy = <String, Set<String>>{};
    for (final entry in aliasesById.entries) {
      for (final alias in entry.value) {
        final key = normalizeAlias(alias);
        seenBy.putIfAbsent(key, () => {}).add(entry.key);
        byAlias[key] = entry.key;
      }
    }
    final collisions = [
      for (final e in seenBy.entries)
        if (e.value.length > 1) AliasCollision(e.key, e.value.toList()..sort()),
    ];
    return AliasIndex._(byAlias, collisions);
  }

  String? resolve(String phrase) => _byAlias[normalizeAlias(phrase)];
}
