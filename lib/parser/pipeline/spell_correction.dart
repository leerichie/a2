import 'text_folding.dart';

/// Classic Levenshtein edit distance between two short words. Words here
/// are always single tokens (a handful of characters), so a full DP
/// table is plenty fast -- no need for a bounded/early-exit variant.
int _editDistance(String a, String b) {
  if (a == b) return 0;
  final la = a.length, lb = b.length;
  if (la == 0) return lb;
  if (lb == 0) return la;
  var prev = List<int>.generate(lb + 1, (j) => j);
  for (var i = 1; i <= la; i++) {
    final curr = List<int>.filled(lb + 1, 0);
    curr[0] = i;
    for (var j = 1; j <= lb; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      curr[j] = [
        prev[j] + 1, // deletion
        curr[j - 1] + 1, // insertion
        prev[j - 1] + cost, // substitution
      ].reduce((x, y) => x < y ? x : y);
    }
    prev = curr;
  }
  return prev[lb];
}

/// How much typo tolerance a word of this length gets. Deliberately
/// conservative: short words (<=3 letters) require an exact match --
/// fuzzing "egg" risks landing on an unrelated 3-letter word -- longer
/// words get 1-2 edits, still small relative to their length.
int _maxAllowedDistance(int wordLength) {
  if (wordLength <= 3) return 0;
  if (wordLength <= 8) return 1;
  return 2;
}

final RegExp _wordPattern = RegExp(r'[\p{L}]+', unicode: true);

/// Corrects near-miss spellings of known vocabulary words ("cofee" ->
/// "coffee", "glas" -> "glass", "duza" -> already folds to a vocabulary
/// hit before this even runs) word-by-word, leaving digits, punctuation
/// and already-known words untouched. A word is only ever corrected when
/// exactly one vocabulary word is closest within its length's threshold
/// -- an ambiguous tie (equally close to two different words) is left
/// alone rather than guessed, so an unknown word never gets silently
/// mapped onto an unrelated food.
String correctSpelling(String text, Set<String> vocabulary) {
  return text.replaceAllMapped(_wordPattern, (match) {
    final word = match.group(0)!;
    final folded = foldDiacritics(word);
    if (vocabulary.contains(folded)) return word;

    final maxDistance = _maxAllowedDistance(folded.length);
    if (maxDistance == 0) return word;

    var bestDistance = maxDistance + 1;
    String? best;
    var ambiguous = false;
    for (final candidate in vocabulary) {
      if ((candidate.length - folded.length).abs() > maxDistance) continue;
      final distance = _editDistance(folded, candidate);
      if (distance > maxDistance) continue;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = candidate;
        ambiguous = false;
      } else if (distance == bestDistance && candidate != best) {
        ambiguous = true;
      }
    }
    if (best == null || ambiguous) return word;
    return best;
  });
}

/// Splits every alias/canonical-name/lexicon phrase into its individual
/// (diacritic-folded) words, building the vocabulary [correctSpelling]
/// corrects against -- the same mechanism for every locale's own data,
/// not an English-only word list.
Set<String> buildVocabulary(Iterable<String> phrases) {
  final vocabulary = <String>{};
  for (final phrase in phrases) {
    for (final match in _wordPattern.allMatches(phrase)) {
      vocabulary.add(foldDiacritics(match.group(0)!));
    }
  }
  return vocabulary;
}
