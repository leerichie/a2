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
        home: Scaffold(body: HeroCard(calories: 600, target: 1800)),
      ),
    );
    expect(find.text('1200 kcal left for today'), findsOneWidget);
    expect(find.text('1800 daily target'), findsOneWidget);
  });

  testWidgets('shows dashboard and adds a meal', (tester) async {
    await tester.pumpWidget(const A2App(startOnboarding: false));
    expect(find.text('Good afternoon, Ashley'), findsOneWidget);
    expect(find.text('Nothing logged today'), findsOneWidget);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food or drink'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Greek yoghurt and berries');
    await tester.tap(find.text('Estimate & add'));
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

  test('dynamic translations insert their real values', () {
    expect(translateUi('pl', '2 ITEMS'), '2 ELEMENTÓW');
    expect(translateUi('pl', '1680 kcal left for today'), contains('1680'));
    expect(translateUi('pl', '2100 daily target'), contains('2100'));
    expect(translateUi('pl', 'This device: a2-test'), 'To urządzenie: a2-test');
    expect(translateUi('pl', 'Update check failed: test'), contains('test'));
  });
}
