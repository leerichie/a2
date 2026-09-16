class PhraseTable<T> {
  PhraseTable(Map<String, T> byPhrase)
      : _entries = byPhrase.entries.toList()
          ..sort((a, b) => b.key.length.compareTo(a.key.length));

  final List<MapEntry<String, T>> _entries;

  // Unicode-aware so this still works correctly for any locale word that,
  // for whatever reason, wasn't fully folded to plain ASCII.
  static bool _isWordChar(String ch) => RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(ch);

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

/// Drops any whole word in [fillerWords] from anywhere in [text] (not just
/// the start) -- for filler verbs/prepositions in a free-form activity
/// sentence ("played singles tennis **for** 2 hours", "cycled 10km **in**
/// 30min") that aren't meaningful food-style connector words and can
/// appear after other words have already been removed.
String removeFillerWords(String text, List<String> fillerWords) {
  if (fillerWords.isEmpty) return text;
  final fillers = fillerWords.toSet();
  final kept = text
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && !fillers.contains(w));
  return kept.join(' ').trim();
}
