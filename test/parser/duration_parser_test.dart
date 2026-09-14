import 'package:a2/parser/catalogue/lexicon.dart';
import 'package:a2/parser/pipeline/duration_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Lexicon lexicon;

  setUpAll(() async {
    lexicon = await Lexicon.load();
  });

  test('minutes with space', () {
    final r = parseDuration('20 min hiit', lexicon);
    expect(r.minutes, 20);
    expect(r.remainder, 'hiit');
  });

  test('hours glued to number', () {
    final r = parseDuration('1h vigorous swimming', lexicon);
    expect(r.minutes, 60);
    expect(r.remainder, 'vigorous swimming');
  });

  test('mins abbreviation', () {
    final r = parseDuration('90 mins doubles tennis', lexicon);
    expect(r.minutes, 90);
    expect(r.remainder, 'doubles tennis');
  });

  test('hours plural', () {
    final r = parseDuration('2 hours tennis singles', lexicon);
    expect(r.minutes, 120);
    expect(r.remainder, 'tennis singles');
  });

  test('phrase "half an hour"', () {
    final r = parseDuration('half an hour brisk walking', lexicon);
    expect(r.minutes, 30);
    expect(r.remainder, 'brisk walking');
  });

  test('approximation word sets approximate', () {
    final r = parseDuration('about 40 min gardening', lexicon);
    expect(r.approximate, true);
    expect(r.minutes, 40);
    expect(r.remainder, 'gardening');
  });

  test('no duration present', () {
    final r = parseDuration('gardening', lexicon);
    expect(r.minutes, null);
    expect(r.remainder, 'gardening');
  });
}
