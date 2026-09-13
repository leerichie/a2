import 'package:a2/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    await tester.tap(find.text('Log food'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Greek yoghurt and berries');
    await tester.tap(find.text('Estimate & add'));
    await tester.pumpAndSettle();
    expect(find.text('420'), findsOneWidget);
  });
}
