import '../catalogue/lexicon.dart';

class ExerciseQuantityResult {
  const ExerciseQuantityResult({
    this.minutes,
    this.distanceKm,
    this.steps,
    required this.approximate,
    required this.remainder,
  });
  final double? minutes;
  final double? distanceKm;
  final int? steps;
  final bool approximate;
  final String remainder;
}

/// Finds every duration/distance/step quantity ANYWHERE in [text] --
/// unlike food quantities, which always lead their segment, a natural
/// exercise sentence routinely puts the number at the end ("played
/// singles tennis for 2 hours") or has more than one ("cycled 10km in
/// 30min") -- and removes each one, leaving the activity words behind in
/// their original order. All unit words come from the locale's own
/// lexicon (time/distance/step units), so this generalizes across
/// languages the same way the rest of the parser does; it does not
/// itself do typo correction or activity resolution.
ExerciseQuantityResult parseExerciseQuantity(String text, Lexicon lexicon) {
  // Named multi-word duration phrases ("half an hour", "quarter of an
  // hour") have no leading digit at all, so the number+unit scan below
  // can't find them -- remove any that appear anywhere first.
  double? phraseMinutes;
  var working = text;
  if (lexicon.durationPhraseMinutes.isNotEmpty) {
    final phrases = lexicon.durationPhraseMinutes.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final phraseAlternation = phrases.map(RegExp.escape).join('|');
    final phrasePattern = RegExp(
      '(?<![\\p{L}\\p{N}])(?:$phraseAlternation)(?![\\p{L}\\p{N}])',
      unicode: true,
    );
    final match = phrasePattern.firstMatch(working);
    if (match != null) {
      phraseMinutes = lexicon.durationPhraseMinutes[match.group(0)];
      working =
          '${working.substring(0, match.start)} ${working.substring(match.end)}'
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
    }
  }

  final unitToKind = <String, String>{
    for (final u in lexicon.timeUnitByAlias.keys) u: 'time',
    for (final u in lexicon.distanceUnitByAlias.keys) u: 'distance',
    for (final u in lexicon.stepUnitWords) u: 'steps',
  };
  if (unitToKind.isEmpty) {
    return ExerciseQuantityResult(
      minutes: phraseMinutes,
      approximate: false,
      remainder: working.trim(),
    );
  }
  final units = unitToKind.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  final unitAlternation = units.map(RegExp.escape).join('|');
  final approxAlternation = lexicon.approximationWords.isEmpty
      ? null
      : lexicon.approximationWords.map(RegExp.escape).join('|');
  final pattern = RegExp(
    (approxAlternation == null ? '' : '(?:(?:$approxAlternation)\\s+)?') +
        r'(\d+(?:\.\d+)?)\s*' +
        '($unitAlternation)(?![\\p{L}\\p{N}])',
    unicode: true,
  );

  double? minutes = phraseMinutes;
  double? distanceKm;
  int? steps;
  var approximate = false;
  final keptSegments = <String>[];
  var cursor = 0;
  for (final match in pattern.allMatches(working)) {
    keptSegments.add(working.substring(cursor, match.start));
    cursor = match.end;

    final value = double.parse(match.group(1)!);
    final unit = match.group(2)!;
    if (approxAlternation != null &&
        RegExp('^(?:$approxAlternation)\\b').hasMatch(match.group(0)!)) {
      approximate = true;
    }
    switch (unitToKind[unit]) {
      case 'time':
        final kind = lexicon.timeUnitByAlias[unit];
        minutes = switch (kind) {
          'hour' => value * 60,
          'second' => value / 60,
          _ => value,
        };
      case 'distance':
        distanceKm = lexicon.distanceUnitByAlias[unit] == 'km'
            ? value
            : value / 1000.0;
      case 'steps':
        steps = value.round();
    }
  }
  keptSegments.add(working.substring(cursor));

  final remainder = keptSegments
      .join(' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return ExerciseQuantityResult(
    minutes: minutes,
    distanceKm: distanceKm,
    steps: steps,
    approximate: approximate,
    remainder: remainder,
  );
}
