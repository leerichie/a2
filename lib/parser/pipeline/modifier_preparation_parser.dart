import '../catalogue/lexicon.dart';
import 'token_matching.dart';

class ModifierStripResult {
  const ModifierStripResult({required this.modifiers, required this.remainder});
  final List<String> modifiers;
  final String remainder;
}

class PreparationStripResult {
  const PreparationStripResult({
    required this.preparations,
    required this.remainder,
  });
  final List<String> preparations;
  final String remainder;
}

/// Peels off leading modifier words (fat-content/attribute descriptors:
/// "light", "low fat", "skinless", ...) so the food resolver sees just the
/// food noun -- matching the dataset's own expectation that "light mayo"
/// resolves to the *base* food ("mayonnaise") plus a preserved
/// `modifiers: ["light"]`, not a separate "light mayonnaise" entity, even
/// though a "light_mayonnaise" catalogue entry also exists (its own alias
/// list is not meant to win over this generic stripping -- confirmed by
/// the dataset's own supplied test fixtures).
ModifierStripResult stripModifiers(String text, Lexicon lexicon) {
  var remaining = text.trimLeft();
  final modifiers = <String>[];
  final modifierTable = PhraseTable({for (final w in lexicon.modifiers) w: w});
  while (true) {
    final match = modifierTable.matchAtStart(remaining);
    if (match == null) break;
    modifiers.add(match.$1);
    remaining = remaining.substring(match.$2).trimLeft();
  }
  return ModifierStripResult(modifiers: modifiers, remainder: remaining);
}

/// Peels off leading preparation/cooking-method words ("smoked", "boiled",
/// "grilled", ...). Unlike modifiers, a preparation word is NOT stripped
/// unconditionally by the caller -- some catalogue entries are
/// deliberately compound ("smoked_salmon", "boiled_egg") because the
/// cooking method materially changes nutrition, and the caller tries
/// resolving the whole phrase (preparation word still attached) first;
/// this function is only reached as the fallback once that direct match
/// fails, so a generic "grilled chicken breast" (no dedicated compound
/// entry) still correctly reduces to chicken_breast + preparation:
/// ["grilled"].
PreparationStripResult stripPreparations(String text, Lexicon lexicon) {
  var remaining = text.trimLeft();
  final preparations = <String>[];
  final preparationTable = PhraseTable({
    for (final w in lexicon.preparations) w: w,
  });
  while (true) {
    final match = preparationTable.matchAtStart(remaining);
    if (match == null) break;
    preparations.add(match.$1);
    remaining = remaining.substring(match.$2).trimLeft();
  }
  return PreparationStripResult(
    preparations: preparations,
    remainder: remaining,
  );
}
