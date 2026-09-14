class PhraseTable<T> {
  PhraseTable(Map<String, T> byPhrase)
      : _entries = byPhrase.entries.toList()
          ..sort((a, b) => b.key.length.compareTo(a.key.length));

  final List<MapEntry<String, T>> _entries;

  static bool _isWordChar(String ch) => RegExp(r'[a-z0-9]').hasMatch(ch);

  /// Matches the longest known phrase at the start of [text] (already
  /// lowercased/trimmed), requiring a word boundary right after it so
  /// "art" can't match inside "artichoke".
  (T value, int length)? matchAtStart(String text) {
    for (final entry in _entries) {
      final phrase = entry.key;
      if (!text.startsWith(phrase)) continue;
      if (text.length > phrase.length) {
        final next = text[phrase.length];
        if (_isWordChar(next)) continue;
      }
      return (entry.value, phrase.length);
    }
    return null;
  }
}

String consumeConnectorsAndWhitespace(String text, List<String> connectorWords) {
  var remaining = text.trimLeft();
  final table = PhraseTable({for (final w in connectorWords) w: true});
  while (true) {
    final match = table.matchAtStart(remaining);
    if (match == null) return remaining;
    remaining = remaining.substring(match.$2).trimLeft();
  }
}
