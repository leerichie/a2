import 'dart:convert';
import 'dart:io';

import 'package:a2/parser/catalogue/alias_index.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _readAliases(String path) =>
    json.decode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  const path = 'assets/parser/en/food_aliases.json';

  test('zero alias collisions in the shipped food catalogue', () {
    final aliases = _readAliases(path);
    final index = AliasIndex.build(
      aliases.map((k, v) => MapEntry(k, (v as List<dynamic>).cast<String>())),
    );
    expect(index.collisions, isEmpty, reason: index.collisions.join('\n'));
  });

  test('bare "cola" and branded "coca_cola" are kept separate (not merged, not colliding)', () {
    final aliases = _readAliases(path);
    expect((aliases['cola'] as List<dynamic>).cast<String>(), ['cola']);
    final cocaColaAliases = (aliases['coca_cola'] as List<dynamic>).cast<String>();
    expect(cocaColaAliases, isNot(contains('cola')));
    expect(cocaColaAliases, containsAll(['coke', 'coca cola', 'coca-cola']));
  });

  test('gherkin absorbed the duplicate pickled_cucumber id', () {
    final aliases = _readAliases(path);
    expect(aliases.containsKey('pickled_cucumber'), false);
    final gherkinAliases = (aliases['gherkin'] as List<dynamic>).cast<String>();
    expect(gherkinAliases, containsAll(['gherkin', 'pickle', 'pickled cucumber']));
  });

  test('all 9 generated-plural typos are fixed', () {
    final aliases = _readAliases(path);
    final allAliases = aliases.values
        .expand((v) => (v as List<dynamic>).cast<String>())
        .map((s) => s.toLowerCase())
        .toSet();
    const typos = [
      'blackberrys', 'blueberrys', 'cherrys', 'cranberrys', 'gooseberrys',
      'raspberrys', 'strawberrys', 'elderberrys', 'mulberrys',
    ];
    const correctPlurals = [
      'blackberries', 'blueberries', 'cherries', 'cranberries', 'gooseberries',
      'raspberries', 'strawberries', 'elderberries', 'mulberries',
    ];
    for (final typo in typos) {
      expect(allAliases.contains(typo), false, reason: '"$typo" should have been fixed');
    }
    for (final correct in correctPlurals) {
      expect(allAliases.contains(correct), true, reason: '"$correct" should be present');
    }
  });
}
