/// Generic diacritic folding, shared by every locale rather than an
/// English-only or Polish-only special case: applied to both the input
/// text and every lexicon/alias key at load time, so "duza" and "duża"
/// (or "cafe" and "café") land on the same canonical key. This is a
/// lossless canonicalization step (like lowercasing), not a fuzzy match.
const Map<String, String> _diacriticFold = {
  // Polish
  'ą': 'a', 'ć': 'c', 'ę': 'e', 'ł': 'l', 'ń': 'n',
  'ó': 'o', 'ś': 's', 'ź': 'z', 'ż': 'z',
  'Ą': 'A', 'Ć': 'C', 'Ę': 'E', 'Ł': 'L', 'Ń': 'N',
  'Ó': 'O', 'Ś': 'S', 'Ź': 'Z', 'Ż': 'Z',
  // Common Western European (French/German/Spanish/Italian/Portuguese/...)
  'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ñ': 'n', 'ç': 'c', 'ý': 'y', 'ÿ': 'y',
  'š': 's', 'č': 'c', 'ž': 'z', 'ď': 'd', 'ť': 't', 'ň': 'n', 'ě': 'e',
  'æ': 'ae', 'œ': 'oe', 'ß': 'ss',
  'Á': 'A', 'À': 'A', 'Â': 'A', 'Ä': 'A', 'Ã': 'A', 'Å': 'A',
  'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E',
  'Í': 'I', 'Ì': 'I', 'Î': 'I', 'Ï': 'I',
  'Ò': 'O', 'Ô': 'O', 'Ö': 'O', 'Õ': 'O', 'Ø': 'O',
  'Ú': 'U', 'Ù': 'U', 'Û': 'U', 'Ü': 'U',
  'Ñ': 'N', 'Ç': 'C', 'Ý': 'Y',
};

String foldDiacritics(String s) {
  final buffer = StringBuffer();
  for (final ch in s.split('')) {
    buffer.write(_diacriticFold[ch] ?? ch);
  }
  return buffer.toString();
}
