import 'dart:io';

import 'package:a2/l10n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every static app-owned LText and ui string has all six languages', () {
    final source = File('lib/main.dart').readAsStringSync();
    final strings = RegExp(
      r'''(?:LText\s*\(|ui\s*\(\s*context\s*,)\s*(['"])((?:\\.|(?!\1).)*)\1''',
      dotAll: true,
    ).allMatches(source).map((match) => match.group(2)!).toSet();
    const languageNeutral = {'A', 'a²', 'kcal'};
    final missing = strings.where((value) {
      if (languageNeutral.contains(value) || value.contains(r'$')) return false;
      return !hasUiTranslation(value);
    }).toList()..sort();
    expect(missing, isEmpty, reason: 'Add six translations in lib/l10n.dart');
  });
}
