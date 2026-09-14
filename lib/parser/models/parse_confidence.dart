enum ParseConfidence { high, medium, low, incomplete }

ParseConfidence parseConfidenceFromString(String value) {
  switch (value) {
    case 'high':
      return ParseConfidence.high;
    case 'medium':
      return ParseConfidence.medium;
    case 'low':
      return ParseConfidence.low;
    case 'incomplete':
      return ParseConfidence.incomplete;
    default:
      throw ArgumentError('Unknown confidence value: $value');
  }
}
