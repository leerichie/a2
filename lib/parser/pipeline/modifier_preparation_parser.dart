import '../catalogue/lexicon.dart';
import 'token_matching.dart';

class ModifierPreparationResult {
  const ModifierPreparationResult({
    required this.modifiers,
    required this.preparations,
    required this.remainder,
  });
  final List<String> modifiers;
  final List<String> preparations;
  final String remainder;
}

/// Peels off leading preparation/modifier words so the food resolver sees
/// just the food noun -- matching the dataset's own expectation that
/// "light mayo" resolves to the *base* food ("mayonnaise") plus a preserved
/// `modifiers: ["light"]`, not a separate "light mayonnaise" entity.
ModifierPreparationResult parseModifiersAndPreparations(String text, Lexicon lexicon) {
  var remaining = text.trimLeft();
  final modifiers = <String>[];
  final preparations = <String>[];
  final modifierTable = PhraseTable({for (final w in lexicon.modifiers) w: w});
  final preparationTable = PhraseTable({for (final w in lexicon.preparations) w: w});

  while (true) {
    final modMatch = modifierTable.matchAtStart(remaining);
    if (modMatch != null) {
      modifiers.add(modMatch.$1);
      remaining = remaining.substring(modMatch.$2).trimLeft();
      continue;
    }
    final prepMatch = preparationTable.matchAtStart(remaining);
    if (prepMatch != null) {
      preparations.add(prepMatch.$1);
      remaining = remaining.substring(prepMatch.$2).trimLeft();
      continue;
    }
    break;
  }

  return ModifierPreparationResult(
    modifiers: modifiers,
    preparations: preparations,
    remainder: remaining,
  );
}
