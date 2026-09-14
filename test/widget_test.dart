import 'dart:convert';

import 'package:a2/main.dart';
import 'package:a2/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
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

  test('body profiles produce different default dashboard targets', () {
    const ania = BodyProfile(
      age: 42,
      heightCm: 175,
      weightKg: 70,
      sex: 'Female',
      activity: 'Lightly active',
    );
    const ashley = BodyProfile(
      age: 42,
      heightCm: 180,
      weightKg: 90,
      sex: 'Male',
      activity: 'Lightly active',
    );
    expect(
      resolvedDailyTarget(ania, storedTarget: 2100, customized: false),
      1956,
    );
    expect(
      resolvedDailyTarget(ashley, storedTarget: 2100, customized: false),
      2503,
    );
    expect(
      resolvedDailyTarget(ashley, storedTarget: 1800, customized: true),
      1800,
    );
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
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const A2App(startOnboarding: false));
    expect(find.text(greetingFor(DateTime.now())), findsOneWidget);
    expect(find.text('Nothing logged today'), findsOneWidget);
    await tester.tap(find.text('Add'));
    await tester.pump(const Duration(milliseconds: 500));
    final foodOption = find.ancestor(
      of: find.text('Food or drink'),
      matching: find.byType(ListTile),
    );
    tester.widget<ListTile>(foodOption).onTap!();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byType(TextField), 'Greek yoghurt and berries');
    final addButton = find.ancestor(
      of: find.text('Add to day'),
      matching: find.byType(FilledButton),
    );
    tester.widget<FilledButton>(addButton).onPressed!();
    await tester.pump(const Duration(milliseconds: 500));
    // The hero ring's total and the single entry's own tile can coincide
    // (both read "80" when it's the only entry logged), so accept either.
    expect(find.text('80'), findsWidgets);
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
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Delete entry?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Greek yoghurt and berries'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Greek yoghurt and berries'), findsNothing);
    expect(prefs.getStringList(dailyKey), isEmpty);

    // Signing out must replace the whole app with the sign-in gate, not just
    // clear the account while leaving the tab bar usable. Checked here,
    // reusing this test's single A2App mount, rather than as its own
    // testWidgets — flutter_test hangs pumpAndSettle on a *second* full
    // A2App mount in the same file for reasons unrelated to this app (a
    // pre-existing test-harness quirk, confirmed by a throwaway test that
    // hung on a second mount doing nothing at all).
    tester.widget<AppShell>(find.byType(AppShell)).onSignedOut();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Save your progress'), findsOneWidget);
  });

  testWidgets('exercise entry uses the offline MET parser and body weight', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'body_profile': jsonEncode(const BodyProfile(weightKg: 70).toJson()),
    });
    rootBundle.clear();
    await tester.pumpWidget(const A2App(startOnboarding: false));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Add'));
    await tester.pump(const Duration(milliseconds: 500));
    tester
        .widget<ListTile>(
          find.ancestor(
            of: find.text('Exercise'),
            matching: find.byType(ListTile),
          ),
        )
        .onTap!();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.enterText(find.byType(TextField).first, 'HIIT');
    await tester.enterText(find.byType(TextField).last, '20');
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Add exercise')).onPressed!();
    // The offline parser loads its JSON assets asynchronously; pump
    // several times to robustly drain that regardless of prior test timing.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(find.textContaining('210'), findsWidgets); // 9.0 MET x 70kg x (20/60)h

    final prefs = await SharedPreferences.getInstance();
    final dailyKey = prefs
        .getKeys()
        .firstWhere((key) => key.startsWith('daily_entries_'));
    final saved =
        jsonDecode(prefs.getStringList(dailyKey)!.single) as Map<String, dynamic>;
    expect(saved['exerciseActivityId'], 'hiit');
    expect(saved['exerciseMet'], 9.0);
    expect(saved['exerciseBodyWeightKg'], 70.0);
    expect(saved['exerciseDurationMinutes'], 20.0);
    expect(saved['exerciseApproximate'], false);
  });

  testWidgets('unresolved activity is surfaced, not silently guessed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'body_profile': jsonEncode(const BodyProfile(weightKg: 70).toJson()),
    });
    rootBundle.clear();
    await tester.pumpWidget(const A2App(startOnboarding: false));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Add'));
    await tester.pump(const Duration(milliseconds: 500));
    tester
        .widget<ListTile>(
          find.ancestor(
            of: find.text('Exercise'),
            matching: find.byType(ListTile),
          ),
        )
        .onTap!();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.enterText(
      find.byType(TextField).first,
      'underwater basket weaving',
    );
    await tester.enterText(find.byType(TextField).last, '20');
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Add exercise')).onPressed!();
    // The offline parser loads its JSON assets asynchronously; pump
    // several times to robustly drain that regardless of prior test timing.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(
      find.textContaining('don\'t recognize "underwater basket weaving"'),
      findsOneWidget,
    );
    expect(find.text('Nothing logged today'), findsOneWidget);
  });

  testWidgets('missing body weight blocks the estimate instead of guessing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    rootBundle.clear();
    await tester.pumpWidget(const A2App(startOnboarding: false));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Add'));
    await tester.pump(const Duration(milliseconds: 500));
    tester
        .widget<ListTile>(
          find.ancestor(
            of: find.text('Exercise'),
            matching: find.byType(ListTile),
          ),
        )
        .onTap!();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.enterText(find.byType(TextField).first, 'HIIT');
    await tester.enterText(find.byType(TextField).last, '20');
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Add exercise')).onPressed!();
    // The offline parser loads its JSON assets asynchronously; pump
    // several times to robustly drain that regardless of prior test timing.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(
      find.textContaining('Add your weight in your profile'),
      findsOneWidget,
    );
    expect(find.text('Nothing logged today'), findsOneWidget);
  });

  testWidgets('dashboard greeting uses the signed-in account name', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'account_user':
          '{"id":"ania-id","email":"ania@example.com","name":"Ania"}',
    });
    await tester.pumpWidget(const A2App(startOnboarding: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('${greetingFor(DateTime.now())}, Ania'), findsOneWidget);
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

  test('exercise calculation evidence survives serialization', () {
    const exercise = FoodEntry(
      'HIIT',
      '18:30 · 20 min',
      210,
      0,
      Icons.directions_run,
      isExercise: true,
      exerciseActivityId: 'hiit',
      exerciseDurationMinutes: 20,
      exerciseMet: 9.0,
      exerciseBodyWeightKg: 70,
      exerciseApproximate: false,
    );
    final restored = FoodEntry.fromJson(exercise.toJson());
    expect(restored.exerciseActivityId, 'hiit');
    expect(restored.exerciseDurationMinutes, 20);
    expect(restored.exerciseMet, 9.0);
    expect(restored.exerciseBodyWeightKg, 70);
    expect(restored.exerciseApproximate, false);
  });

  test('an older exercise entry with no evidence fields still round-trips', () {
    const legacy = FoodEntry(
      'Running',
      '07:00 · 30 min',
      300,
      0,
      Icons.directions_run,
      isExercise: true,
    );
    final restored = FoodEntry.fromJson(legacy.toJson());
    expect(restored.exerciseActivityId, null);
    expect(restored.exerciseDurationMinutes, null);
    expect(restored.exerciseApproximate, false);
  });

  test('shared-entry identity and deletion marker survive locally', () async {
    const entry = FoodEntry(
      'Shared breakfast',
      '08:30',
      444,
      27,
      Icons.restaurant,
      carbs: 51,
      sharedFrom: 'Lee',
      sharedEntryId: 'shared-123',
    );
    final restored = FoodEntry.fromJson(entry.toJson());
    expect(restored.sharedFrom, 'Lee');
    expect(restored.sharedEntryId, 'shared-123');
    await const AccountService().recordDeletedEntry(
      entry,
      DateTime(2026, 9, 14),
    );
    final prefs = await SharedPreferences.getInstance();
    final marker = jsonDecode(
      prefs.getStringList('deleted_daily_entries')!.single,
    ) as Map<String, dynamic>;
    expect(marker['dateKey'], 'daily_entries_2026-09-14');
    expect(
      (marker['entry'] as Map<String, dynamic>)['sharedEntryId'],
      'shared-123',
    );
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

  test('counts a plain quantity with no explicit measure', () {
    final one = FoodEstimator.estimate('a whisky');
    final two = FoodEstimator.estimate('2 whiskies');
    expect(two.calories, 2 * one.calories);
  });

  test(
    'a named fast-food order sums each item instead of one stray ingredient',
    () {
      final order = FoodEstimator.estimate(
        "McDonald's Big Mac, large fries, large coke, 2x cheeseburgers",
      );
      // Previously this only matched "cheese" inside "cheeseburgers" (~105
      // kcal) — a realistic order should land well over 1000 kcal.
      expect(order.calories, greaterThan(1500));
    },
  );

  test('does not double count an ingredient inside a composite item name', () {
    final order = FoodEstimator.estimate('a cheeseburger');
    // Should be the whole-burger estimate, not that plus a separate "cheese"
    // match from the same substring.
    expect(order.calories, 300);
  });

  test('does not discard components of a vague multi-item breakfast', () {
    final breakfast = FoodEstimator.estimate(
      'coleslaw, egg, bell pepper, pickle, cheese, cottage cheese breakfast and fruit smoothie',
    );
    expect(breakfast.calories, inInclusiveRange(500, 600));
    expect(breakfast.protein, greaterThanOrEqualTo(25));
    expect(breakfast.carbs, greaterThanOrEqualTo(45));
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

  test('water descriptions resolve to dashboard millilitres', () {
    expect(WaterIntakeParser.parse('500ml water')!.millilitres, 500);
    expect(WaterIntakeParser.parse('2 bottles of water')!.millilitres, 1000);
    expect(WaterIntakeParser.parse('glass of water')!.millilitres, 250);
    expect(WaterIntakeParser.parse('glass water')!.millilitres, 250);
    expect(WaterIntakeParser.parse('half glass water')!.millilitres, 125);
    expect(WaterIntakeParser.parse('half bottle water')!.millilitres, 250);
    expect(WaterIntakeParser.parse('butelka wody')!.millilitres, 500);
    expect(WaterIntakeParser.parse('une bouteille d eau')!.millilitres, 500);
    expect(WaterIntakeParser.parse('coffee'), isNull);
    expect(WaterIntakeParser.parse('breakfast and water'), isNull);
  });

  test('half a glass of water is understood in all six languages', () {
    final descriptions = [
      'half a glass of water',
      'pół szklanki wody',
      'ein halbes Glas Wasser',
      "un demi-verre d'eau",
      'medio vaso de agua',
      "mezzo bicchiere d'acqua",
    ];
    for (final description in descriptions) {
      expect(
        WaterIntakeParser.parse(description)?.millilitres,
        125,
        reason: description,
      );
    }
  });

  test('common drink words receive nutrition and the drinks category', () {
    final juice = FoodEstimator.estimate('a glass of orange juice');
    expect(juice.calories, greaterThan(100));
    expect(juice.carbs, greaterThan(20));
    expect(MealCategory.detect('orange juice', false), 'Drinks');
    expect(MealCategory.detect('coffee', false), 'Drinks');
  });
}
