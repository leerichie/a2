# English Food Language Parser Dataset

Purpose: offline natural-language food logging for a nutrition app.

This is designed so the parser can separate:
- quantity / multiplier
- fraction
- size
- household unit / portion
- approximation
- food identity
- food aliases
- preparation
- nutrition-relevant modifiers

Example:
`2 tbsp light mayo`

Expected normalized representation:
```json
{
  "quantity": 2,
  "unit": "tablespoon",
  "food": "mayonnaise",
  "modifiers": ["light"]
}
```

Important design rules:
1. Parse quantity before food lookup.
2. Normalize aliases to canonical food IDs.
3. Preserve nutrition-relevant modifiers such as light, reduced-fat, skinless, sugar-free.
4. Treat household portions as approximate unless standardized.
5. Never hard-code one gram value for `handful`, `bowl`, `slice`, `glass`, etc. Conversion must be food-aware.
6. Support `1x`, `2x`, `x2`, numeric counts, number words, fractions and symbols.
7. Tolerate connector words such as `a`, `an`, `of`.
8. Approximation words should reduce confidence, not disappear.
9. Regional English aliases must be locale/context aware where ambiguous.
10. Add tests whenever a new phrase is supported.

Suggested parse pipeline:
raw text
→ normalize case/punctuation
→ parse multiplier/count/fraction
→ parse size/fullness
→ parse unit/portion
→ identify approximation/connectors
→ identify preparation/modifiers
→ resolve food alias
→ canonical structured result
→ food-aware portion estimate
→ nutrition lookup

This dataset is intentionally separated into files so it can later be mirrored for:
pl / de / fr / es / it

The food alias file is a strong starter set, not a complete worldwide food database. It should be extended over time from real user input and app telemetry/error review.
