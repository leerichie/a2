import 'package:a2/main.dart';
import 'package:a2/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('calculates resting and maintenance energy from body details', () {
    const profile = BodyProfile(
      age: 42,
      heightCm: 180,
      weightKg: 90,
      sex: 'Male',
      activity: 'Lightly active',
    );
    expect(profile.restingCalories, 1820);
    expect(profile.maintenanceCalories, 2502.5);
  });

  testWidgets('calorie card uses the active plan target', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HeroCard(
            foodCalories: 600,
            exerciseCalories: 0,
            target: 1800,
            headline: 'Looking steady',
          ),
        ),
      ),
    );
    expect(find.text('1200 kcal left for today'), findsOneWidget);
    expect(find.text('1800 daily target'), findsOneWidget);
  });

  testWidgets('calorie card shows exercise-adjusted net energy', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HeroCard(
            foodCalories: 646,
            exerciseCalories: 80,
            target: 2100,
            headline: 'Looking steady',
          ),
        ),
      ),
    );
    expect(find.text('566 net kcal after exercise'), findsOneWidget);
    expect(find.text('1534 kcal left for today'), findsOneWidget);
  });

  testWidgets('shows dashboard and adds a meal', (tester) async {
    await tester.pumpWidget(const A2App(startOnboarding: false));
    expect(find.text('${greetingFor(DateTime.now())}, Ashley'), findsOneWidget);
    expect(find.text('Nothing logged today'), findsOneWidget);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food or drink · counts towards your day'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Greek yoghurt and berries');
    await tester.tap(find.text('Add to day'));
    await tester.pumpAndSettle();
    expect(find.text('80'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 50));
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getKeys().where((key) => key.startsWith('daily_entries_')),
      isNotEmpty,
    );
    final dailyKey = prefs.getKeys().firstWhere(
      (key) => key.startsWith('daily_entries_'),
    );
    expect(prefs.getStringList(dailyKey)!.single, contains('Greek yoghurt'));

    await tester.scrollUntilVisible(
      find.byIcon(Icons.delete_outline),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Delete entry?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Greek yoghurt and berries'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Greek yoghurt and berries'), findsNothing);
    expect(prefs.getStringList(dailyKey), isEmpty);
  });

  test('daily entries persist and remain separated by date', () async {
    const repository = DailyEntryRepository();
    const meal = FoodEntry(
      'Greek yoghurt and berries',
      '08:30',
      180,
      14,
      Icons.restaurant,
    );
    await repository.save(DateTime(2026, 9, 13), [meal]);
    final restored = await repository.load(DateTime(2026, 9, 13));
    expect(restored.single.name, meal.name);
    expect(restored.single.calories, meal.calories);
    expect(await repository.load(DateTime(2026, 9, 14)), isEmpty);
  });

  test('food and exercise entries survive serialization', () {
    const exercise = FoodEntry(
      'Tennis',
      '18:30 · 60 min',
      480,
      0,
      Icons.directions_run,
      isExercise: true,
    );
    final restored = FoodEntry.fromJson(exercise.toJson());
    expect(restored.name, exercise.name);
    expect(restored.calories, 480);
    expect(restored.isExercise, isTrue);
    expect(restored.icon, Icons.directions_run);
  });

  test('food estimates vary with ingredients and quantities', () {
    final breakfast = FoodEstimator.estimate(
      '40g oats with yoghurt and milk, handful of peach and plum',
    );
    final snack = FoodEstimator.estimate(
      '2x 25g walkers crisps, handful of chocolate raisins',
    );
    expect(breakfast.calories, isNot(snack.calories));
    expect(breakfast.protein, greaterThan(snack.protein));
    expect(snack.calories, greaterThan(300));
  });

  test('unknown foods do not receive a fake default estimate', () {
    expect(FoodEstimator.estimate('mystery item').calories, 0);
  });

  test('estimates a measured straight whisky', () {
    final whisky = FoodEstimator.estimate('a straight whisky about 50ml');
    expect(whisky.calories, 110);
    expect(whisky.protein, 0);
  });

  test('detects and orders common meal descriptions', () {
    expect(MealCategory.detect('Bacon breakfast', false), 'Breakfast');
    expect(MealCategory.detect('Quick afternoon snack', false), 'Snack');
    expect(MealCategory.detect('Late supper', false), 'Supper');
    expect(MealCategory.detect('50ml whisky', false), 'Drinks');
    expect(MealCategory.detect('Tennis', true), 'Exercise');
  });

  test('diet styles produce centralized macro targets', () {
    final balanced = NutritionTargets.forPlan(
      calories: 2100,
      style: 'Balanced',
      weightKg: 90,
    );
    final keto = NutritionTargets.forPlan(
      calories: 2100,
      style: 'Keto',
      weightKg: 90,
    );
    expect(balanced.carbs, 263);
    expect(keto.carbs, 30);
    expect(balanced.protein, greaterThanOrEqualTo(108));
  });

  test('dynamic translations insert their real values', () {
    expect(translateUi('pl', '2 ITEMS'), '2 ELEMENTÓW');
    expect(translateUi('pl', '1680 kcal left for today'), contains('1680'));
    expect(translateUi('pl', '2100 daily target'), contains('2100'));
    expect(translateUi('pl', 'This device: a2-test'), 'To urządzenie: a2-test');
    expect(translateUi('pl', 'Update check failed: test'), contains('test'));
  });

  test('label reader scales per-100g values by the printed pack weight', () {
    final reading = LabelParser.parse(
      'Nutrition Information Typical Values Per 100g Per Serving (30g) '
      'Energy 1046kJ / 250kcal 314kJ / 75kcal '
      'Protein 8.0g 2.4g '
      'Carbohydrate 55.0g 16.5g '
      'Net Weight: 250g',
    );
    expect(reading.isConfident, isTrue);
    expect(reading.caloriesPer100, 250);
    expect(reading.proteinPer100, 8.0);
    expect(reading.carbsPer100, 55.0);
    expect(reading.totalGrams, 250);
    final factor = reading.totalGrams! / 100;
    expect((reading.caloriesPer100! * factor).round(), 625);
    expect((reading.proteinPer100! * factor).round(), 20);
    expect((reading.carbsPer100! * factor).round(), 138);
  });

  test('label reader multiplies serving size by servings per container '
      'when no net weight is printed', () {
    final reading = LabelParser.parse(
      'Nutrition Facts Serving Size 30g Servings Per Container 8 '
      'Calories 120kcal Protein 3g Carbohydrate 22g',
    );
    expect(reading.totalGrams, 240);
    expect(reading.caloriesPer100, 120);
  });

  test('label reader reports low confidence without a pack weight', () {
    final reading = LabelParser.parse(
      'Typical Values Per 100g Energy 250kcal Protein 8g Carbohydrate 55g',
    );
    expect(reading.hasNutrition, isTrue);
    expect(reading.isConfident, isFalse);
    expect(reading.totalGrams, isNull);
  });

  test('label reader finds nothing useful in unrelated text', () {
    final reading = LabelParser.parse('Best before end: see lid. Keep cool.');
    expect(reading.hasNutrition, isFalse);
  });

  test('daily nudge encourages breakfast when nothing is logged yet', () {
    final nudge = DailyNudge.forToday(
      entries: const [],
      calories: 0,
      targetCalories: 2100,
      protein: 0,
      targetProtein: 130,
      now: DateTime(2026, 1, 1, 8),
    );
    expect(nudge.title, 'Good time for breakfast');
  });

  test('daily nudge nudges toward lunch later with nothing logged', () {
    final nudge = DailyNudge.forToday(
      entries: const [],
      calories: 0,
      targetCalories: 2100,
      protein: 0,
      targetProtein: 130,
      now: DateTime(2026, 1, 1, 13),
    );
    expect(nudge.title, 'Nothing logged yet');
  });

  test('daily nudge celebrates hitting the calorie target', () {
    final nudge = DailyNudge.forToday(
      entries: [const FoodEntry('Lunch', '12:00', 1000, 50, Icons.restaurant)],
      calories: 1995,
      targetCalories: 2100,
      protein: 120,
      targetProtein: 130,
      now: DateTime(2026, 1, 1, 14),
    );
    expect(nudge.title, 'Right on target');
  });

  test('daily nudge flags going well over the calorie target', () {
    final nudge = DailyNudge.forToday(
      entries: [const FoodEntry('Dinner', '20:00', 2500, 90, Icons.restaurant)],
      calories: 2500,
      targetCalories: 2100,
      protein: 90,
      targetProtein: 130,
      now: DateTime(2026, 1, 1, 21),
    );
    expect(nudge.title, 'A little over today');
  });

  test('daily nudge recognises a balanced day of food and exercise', () {
    final nudge = DailyNudge.forToday(
      entries: const [
        FoodEntry('Lunch', '12:00', 800, 40, Icons.restaurant),
        FoodEntry(
          'Run',
          '18:00 · 30 min',
          300,
          0,
          Icons.directions_run,
          isExercise: true,
        ),
      ],
      calories: 800,
      targetCalories: 2100,
      protein: 40,
      targetProtein: 130,
      now: DateTime(2026, 1, 1, 15),
    );
    expect(nudge.title, 'Nice balance today');
  });

  test('recommended water intake scales with body weight', () {
    expect(recommendedWaterMl(80), 2800);
    expect(recommendedWaterMl(null), 2000);
  });
}
