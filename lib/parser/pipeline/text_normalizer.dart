String normalizeParserText(String input) {
  var text = input.trim().toLowerCase();
  text = text
      .replaceAll('‘', "'")
      .replaceAll('’', "'")
      .replaceAll('“', '"')
      .replaceAll('”', '"');
  text = text.replaceAll(RegExp(r'\s+'), ' ');
  return text;
}
