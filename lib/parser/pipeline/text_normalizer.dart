import 'text_folding.dart';

// A leading meal-name label (typed as part of one free-text description,
// e.g. "breakfast half avocado, ...") isn't a food and isn't in any food
// catalogue -- it's the same kind of always-strippable word across every
// installed locale as a connector/filler word, just for meal time instead
// of quantity. Folded/lowercased forms only, matched here before segmenting.
const _mealTimeWords = {
  'breakfast',
  'brunch',
  'lunch',
  'dinner',
  'supper',
  'snack',
  'sniadanie',
  'obiad',
  'kolacja',
  'przekaska',
  'fruhstuck',
  'mittagessen',
  'abendessen',
  'abendbrot',
  'imbiss',
  'petit-dejeuner',
  'dejeuner',
  'diner',
  'gouter',
  'souper',
  'desayuno',
  'almuerzo',
  'cena',
  'tentempie',
  'colazione',
  'pranzo',
  'spuntino',
};

String normalizeParserText(String input) {
  var text = input.trim().toLowerCase();
  text = text
      .replaceAll('‘', "'")
      .replaceAll('’', "'")
      .replaceAll('“', '"')
      .replaceAll('”', '"');
  text = text.replaceAll(RegExp(r'\s+'), ' ');
  // Diacritic folding is applied to the whole pipeline this same way --
  // both the input and every lexicon/alias key -- so "duza"/"duża" and
  // "cafe"/"café" land on one canonical form, for any locale.
  text = foldDiacritics(text);
  text = _stripLeadingMealLabel(text);
  return text;
}

String _stripLeadingMealLabel(String text) {
  final match = RegExp(r'^([a-z]+)\s+(.+)$').firstMatch(text);
  if (match != null && _mealTimeWords.contains(match.group(1))) {
    return match.group(2)!;
  }
  return text;
}
