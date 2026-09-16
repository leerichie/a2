import 'package:a2/main.dart';
import 'package:a2/parser/food_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _runEdit(WidgetTester tester, FoodEntry entry, String newText) async {
  rootBundle.clear();
  await tester.runAsync(() => FoodParser.load());
  EditEntryResult? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showModalBottomSheet<EditEntryResult>(
                context: context,
                isScrollControlled: true,
                builder: (_) => EditEntrySheet(entry: entry),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));

  await tester.enterText(find.byType(TextField), newText);
  await tester.pump();
  final saveButton = find.ancestor(
    of: find.text('Save'),
    matching: find.byType(FilledButton),
  );
  await tester.runAsync(() async {
    tester.widget<FilledButton>(saveButton).onPressed!();
    await Future<void>.delayed(const Duration(milliseconds: 500));
  });
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }

  final noticeFinder = find.byType(EditEntrySheet);
  if (noticeFinder.evaluate().isNotEmpty) {
    final texts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();
    // ignore: avoid_print
    print('"$newText" -> Sheet STILL OPEN after Save. Visible text: $texts');
  } else {
    // ignore: avoid_print
    print('"$newText" -> Sheet closed. category=${result?.entry?.category} name=${result?.entry?.name} delete=${result?.delete}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('probe: edit avocado entry to add snack word', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final entry = FoodEntry('avocado', '08:00', 240, 3, Icons.restaurant, category: 'Meal', carbs: 12);
    await _runEdit(tester, entry, 'avocado snack');
  });

  testWidgets('probe: edit cadburys-only entry (never added to catalogue) to add snack word', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final entry = FoodEntry('cadburys', '08:00', 240, 3, Icons.restaurant, category: 'Meal', carbs: 30);
    await _runEdit(tester, entry, 'cadburys snack');
  });

  testWidgets('probe: edit entry replacing text with bare "snack" only', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final entry = FoodEntry('avocado', '08:00', 240, 3, Icons.restaurant, category: 'Meal', carbs: 12);
    await _runEdit(tester, entry, 'snack');
  });
}
