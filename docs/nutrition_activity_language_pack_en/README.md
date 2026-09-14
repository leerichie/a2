# Nutrition + Activity English Language Pack

This package contains two independent offline datasets:

## food_drink/
A generic global food/drink taxonomy with strong European/Polish coverage.
Use canonical IDs as the stable identity. Later language packs should translate/map
Polish, German, French, Spanish and Italian names to the same IDs.

It intentionally focuses on generic foods, drinks and meal types rather than branded SKUs.

## exercise_activity/
Exercise/activity names, aliases, time expressions and intensity modifiers.

Important calorie rule:
Estimated exercise calories depend on:
- activity
- duration
- intensity
- user body weight
and sometimes speed/distance/terrain.

A common estimate is:
kcal = MET × body_weight_kg × duration_hours

Do not present exercise calories as exact. Watches, machines and MET formulas can differ materially.

Examples the parser should understand:
- 20 min HIIT
- half an hour brisk walking
- 2 hours tennis singles
- 90 mins doubles tennis
- 45 min easy cycling
- about 40 min gardening

The food taxonomy and exercise taxonomy should be separate from the parser logic.
