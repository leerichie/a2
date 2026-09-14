/// Splits a sentence into independent food/exercise phrases on top-level
/// commas, semicolons and the standalone word "and". This is a heuristic,
/// not a full grammar: a compound food name that itself contains "and"
/// (there are none in the current catalogue) would be mis-split. Refine
/// this once real user input shows it matters.
List<String> segmentPhrases(String normalizedText) {
  final parts = normalizedText.split(RegExp(r'\s*[,;]\s*|\s+and\s+'));
  return parts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
}
