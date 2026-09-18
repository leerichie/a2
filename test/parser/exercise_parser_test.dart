import 'package:a2/parser/exercise_parser.dart';
import 'package:a2/parser/models/parse_confidence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ExerciseParser parser;
  const weight = 70.0;

  setUpAll(() async {
    parser = await ExerciseParser.load();
  });

  // Every fixture from exercise_activity/exercise_parser_tests.json, plus
  // the calorie estimate (met * bodyWeightKg * hours) that fixture doesn't
  // itself assert (it predates the MET-based calculation being wired up).
  group('exercise_parser_tests.json fixtures', () {
    test('20 min HIIT', () {
      final r = parser.parse('20 min HIIT', bodyWeightKg: weight);
      expect(r.activityId, 'hiit');
      expect(r.durationMinutes, 20);
      expect(r.intensity, 'vigorous');
      expect(r.calorieEstimateKcal, closeTo(210, 0.01));
      expect(r.confidence, ParseConfidence.high);
    });

    test('2 hours tennis singles', () {
      final r = parser.parse('2 hours tennis singles', bodyWeightKg: weight);
      expect(r.activityId, 'singles_tennis');
      expect(r.durationMinutes, 120);
      expect(r.calorieEstimateKcal, closeTo(1120, 0.01));
    });

    test('90 mins doubles tennis', () {
      final r = parser.parse('90 mins doubles tennis', bodyWeightKg: weight);
      expect(r.activityId, 'doubles_tennis');
      expect(r.durationMinutes, 90);
      expect(r.calorieEstimateKcal, closeTo(630, 0.01));
    });

    test('half an hour brisk walking', () {
      final r = parser.parse(
        'half an hour brisk walking',
        bodyWeightKg: weight,
      );
      expect(r.activityId, 'brisk_walking');
      expect(r.durationMinutes, 30);
      expect(r.calorieEstimateKcal, closeTo(168, 0.01));
    });

    test('45 min easy cycling', () {
      final r = parser.parse('45 min easy cycling', bodyWeightKg: weight);
      expect(r.activityId, 'easy_cycling');
      expect(r.durationMinutes, 45);
      expect(r.intensity, 'light');
      expect(r.calorieEstimateKcal, closeTo(210, 0.01));
    });

    test('1h vigorous swimming', () {
      final r = parser.parse('1h vigorous swimming', bodyWeightKg: weight);
      expect(r.activityId, 'vigorous_swimming');
      expect(r.durationMinutes, 60);
      expect(r.intensity, 'vigorous');
      expect(r.calorieEstimateKcal, closeTo(686, 0.01));
    });

    test('30 minutes weights', () {
      final r = parser.parse('30 minutes weights', bodyWeightKg: weight);
      expect(r.activityId, 'weight_training');
      expect(r.durationMinutes, 30);
      expect(r.calorieEstimateKcal, closeTo(122.5, 0.01));
    });

    test('15 min stair climbing', () {
      final r = parser.parse('15 min stair climbing', bodyWeightKg: weight);
      expect(r.activityId, 'stairs');
      expect(r.durationMinutes, 15);
      expect(r.calorieEstimateKcal, closeTo(140, 0.01));
    });

    test('about 40 min gardening -- approximate downgrades to low', () {
      final r = parser.parse('about 40 min gardening', bodyWeightKg: weight);
      expect(r.activityId, 'gardening');
      expect(r.durationMinutes, 40);
      expect(r.approximate, true);
      expect(r.calorieEstimateKcal, closeTo(186.67, 0.01));
      expect(r.confidence, ParseConfidence.low);
    });
  });

  test('missing body weight -> incomplete, never a guessed calorie number', () {
    final r = parser.parse('20 min HIIT', bodyWeightKg: null);
    expect(r.activityId, 'hiit');
    expect(r.calorieEstimateKcal, null);
    expect(r.confidence, ParseConfidence.incomplete);
  });

  test('unresolved activity', () {
    final r = parser.parse(
      '30 min underwater basket weaving',
      bodyWeightKg: weight,
    );
    expect(r.activityId, null);
    expect(r.confidence, ParseConfidence.incomplete);
  });

  group('horse riding gaits and groundwork', () {
    test('30 min horse riding walk', () {
      final r = parser.parse('30 min horse riding walk', bodyWeightKg: weight);
      expect(r.activityId, 'horse_riding_walk');
      expect(r.durationMinutes, 30);
    });

    test('45 min trotting', () {
      final r = parser.parse('45 min trotting', bodyWeightKg: weight);
      expect(r.activityId, 'horse_riding_trot');
      expect(r.durationMinutes, 45);
    });

    test('20 min cantering', () {
      final r = parser.parse('20 min cantering', bodyWeightKg: weight);
      expect(r.activityId, 'horse_riding_canter');
    });

    test('10 min galloping', () {
      final r = parser.parse('10 min galloping', bodyWeightKg: weight);
      expect(r.activityId, 'horse_riding_gallop');
    });

    test('1 hour horse jumping', () {
      final r = parser.parse('1 hour horse jumping', bodyWeightKg: weight);
      expect(r.activityId, 'horse_jumping');
      expect(r.calorieEstimateKcal, closeTo(665, 0.01));
    });

    test('30 min horse groundwork (training/handling, not mounted)', () {
      final r = parser.parse('30 min horse groundwork', bodyWeightKg: weight);
      expect(r.activityId, 'horse_groundwork');
    });

    test('lungeing is recognized as groundwork', () {
      final r = parser.parse('20 min lungeing', bodyWeightKg: weight);
      expect(r.activityId, 'horse_groundwork');
    });

    test('a typo\'d "horze jumping" still resolves via spell correction', () {
      final r = parser.parse('30 min horze jumping', bodyWeightKg: weight);
      expect(r.activityId, 'horse_jumping');
    });
  });

  group('walking/running variations', () {
    test('30 min walk uphill resolves to hill walking', () {
      final r = parser.parse('30 min walk uphill', bodyWeightKg: weight);
      expect(r.activityId, 'hill_walking');
    });

    test('30 min walk downhill is distinct from uphill', () {
      final r = parser.parse('30 min walk downhill', bodyWeightKg: weight);
      expect(r.activityId, 'downhill_walking');
    });

    test('30 min interval walk and run', () {
      final r = parser.parse(
        '30 min interval walk and run',
        bodyWeightKg: weight,
      );
      expect(r.activityId, 'run_walk_intervals');
      expect(r.durationMinutes, 30);
    });
  });

  group('swimming strokes', () {
    test(
      '20 min breaststroke is its own (higher-effort) stroke, not "easy"',
      () {
        final r = parser.parse('20 min breaststroke', bodyWeightKg: weight);
        expect(r.activityId, 'breaststroke_swimming');
        expect(r.met, greaterThan(9.0));
      },
    );

    test('15 min butterfly', () {
      final r = parser.parse('15 min butterfly', bodyWeightKg: weight);
      expect(r.activityId, 'butterfly_swimming');
    });

    test('30 min front crawl resolves to lap swimming', () {
      final r = parser.parse('30 min front crawl', bodyWeightKg: weight);
      expect(r.activityId, 'lap_swimming');
    });

    test('a bare distance with no duration stays incomplete rather than '
        'guessing a pace', () {
      final r = parser.parse('50m breaststroke', bodyWeightKg: weight);
      expect(r.activityId, 'breaststroke_swimming');
      expect(r.durationMinutes, null);
      expect(r.calorieEstimateKcal, null);
      expect(r.confidence, ParseConfidence.incomplete);
    });
  });

  group('mixed language and near-miss suggestions', () {
    test('Polish horse gaits are recognized regardless of UI locale', () {
      final trot = parser.parse('30 min jazda kłusem', bodyWeightKg: weight);
      expect(trot.activityId, 'horse_riding_trot');
      final breaststroke = parser.parse('20 min żabka', bodyWeightKg: weight);
      expect(breaststroke.activityId, 'breaststroke_swimming');
    });

    test('an unrecognized near-miss word still offers suggestions', () {
      final r = parser.parse(
        '30 min horse riding trotting fast',
        bodyWeightKg: weight,
      );
      expect(r.activityId, null);
      expect(r.suggestions, isNotEmpty);
    });
  });

  group('sport format/variant names resolve to their base sport', () {
    test('T20, ODI and Test cricket all resolve to cricket, not blocked', () {
      expect(
        parser.parse('2 hours t20 cricket', bodyWeightKg: weight).activityId,
        'cricket',
      );
      expect(
        parser.parse('3 hours odi cricket', bodyWeightKg: weight).activityId,
        'cricket',
      );
      expect(
        parser.parse('1 hour test cricket', bodyWeightKg: weight).activityId,
        'cricket',
      );
      expect(
        parser
            .parse('90 min franchise cricket', bodyWeightKg: weight)
            .activityId,
        'cricket',
      );
    });

    test('rugby sevens and rugby fifteens both resolve to rugby, with '
        'duration intact', () {
      final sevens = parser.parse('40 min rugby sevens', bodyWeightKg: weight);
      expect(sevens.activityId, 'rugby');
      expect(sevens.durationMinutes, 40);
      final fifteens = parser.parse(
        '80 min rugby fifteens',
        bodyWeightKg: weight,
      );
      expect(fifteens.activityId, 'rugby');
      expect(fifteens.durationMinutes, 80);
    });

    // Regression: the quantity parser reads a bare digit glued to "s" as
    // SECONDS (it has no way to know "7s"/"15s" means the rugby format,
    // not a duration) -- "rugby 7s"/"rugby 15s" are deliberately NOT
    // registered as aliases because they'd silently turn "40 min rugby
    // 7s" into a 7-*second* entry instead of 40 minutes. "sevens"/
    // "fifteens" (above) are the safe, unambiguous way to say the same
    // thing.
    test('a glued digit+s is read as seconds, not a format suffix', () {
      final r = parser.parse('40 min rugby 7s', bodyWeightKg: weight);
      expect(r.durationMinutes, isNot(40));
    });

    test('5-a-side football resolves to football', () {
      final r = parser.parse('1 hour 5-a-side', bodyWeightKg: weight);
      expect(r.activityId, 'football');
    });

    test('tennis singles and doubles already resolve to distinct METs', () {
      final singles = parser.parse(
        '1 hour tennis singles',
        bodyWeightKg: weight,
      );
      final doubles = parser.parse(
        '1 hour doubles tennis',
        bodyWeightKg: weight,
      );
      expect(singles.activityId, 'singles_tennis');
      expect(doubles.activityId, 'doubles_tennis');
      expect(singles.met, isNot(doubles.met));
    });
  });

  group('broader sports pass from the full myvocabulary.com sweep', () {
    test('boxing, judo and field hockey are recognized', () {
      expect(
        parser.parse('30 min boxing', bodyWeightKg: weight).activityId,
        'boxing',
      );
      expect(
        parser.parse('45 min judo', bodyWeightKg: weight).activityId,
        'martial_arts',
      );
      expect(
        parser.parse('1 hour field hockey', bodyWeightKg: weight).activityId,
        'field_hockey',
      );
    });

    test('golf, archery and bowling (low-intensity precision sports)', () {
      expect(
        parser.parse('2 hours golf', bodyWeightKg: weight).activityId,
        'golf',
      );
      expect(
        parser.parse('30 min archery', bodyWeightKg: weight).activityId,
        'archery',
      );
      expect(
        parser.parse('45 min bowling', bodyWeightKg: weight).activityId,
        'bowling',
      );
    });

    test('kayaking, canoeing and water skiing', () {
      expect(
        parser.parse('1 hour kayaking', bodyWeightKg: weight).activityId,
        'kayaking',
      );
      expect(
        parser.parse('45 min canoeing', bodyWeightKg: weight).activityId,
        'canoeing',
      );
      expect(
        parser.parse('20 min water skiing', bodyWeightKg: weight).activityId,
        'water_skiing',
      );
    });
  });

  group('Polish sports vocabulary (user is in Poland)', () {
    test('popular Polish team sports resolve to the same entries as their '
        'English names', () {
      expect(
        parser.parse('1 godz piłka nożna', bodyWeightKg: weight).activityId,
        'football',
      );
      expect(
        parser.parse('45 min siatkówka', bodyWeightKg: weight).activityId,
        'volleyball',
      );
      expect(
        parser.parse('30 min koszykówka', bodyWeightKg: weight).activityId,
        'basketball',
      );
    });

    test('ski jumping (skoki narciarskie) -- newly added, no English-list '
        'source, but genuinely popular in Poland', () {
      expect(
        parser.parse('20 min ski jumping', bodyWeightKg: weight).activityId,
        'ski_jumping',
      );
      expect(
        parser
            .parse('20 min skoki narciarskie', bodyWeightKg: weight)
            .activityId,
        'ski_jumping',
      );
    });

    test('canoeing and kayaking use distinct, non-colliding Polish terms', () {
      expect(
        parser.parse('30 min kajak', bodyWeightKg: weight).activityId,
        'kayaking',
      );
      expect(
        parser.parse('30 min kanadyjka', bodyWeightKg: weight).activityId,
        'canoeing',
      );
    });

    test('Polish "rower" (bicycle) does not collide with the English '
        '"rower" (rowing machine)', () {
      final r = parser.parse('30 min jazda na rowerze', bodyWeightKg: weight);
      expect(r.activityId, 'moderate_cycling');
    });
  });

  group('cross country running -- distinct from cross country skiing', () {
    test('"cross country" alone resolves to running, not skiing', () {
      final r = parser.parse('30 min cross country', bodyWeightKg: weight);
      expect(r.activityId, 'cross_country_running');
    });

    test('the American school/college "XC" shorthand is recognized', () {
      expect(
        parser.parse('20 min xc', bodyWeightKg: weight).activityId,
        'cross_country_running',
      );
      expect(
        parser
            .parse('45 min cross country meet', bodyWeightKg: weight)
            .activityId,
        'cross_country_running',
      );
    });

    test('cross-country skiing still resolves separately, unaffected', () {
      final r = parser.parse(
        '1 hour cross-country skiing',
        bodyWeightKg: weight,
      );
      expect(r.activityId, 'cross_country_skiing');
    });

    test('Polish "bieg przełajowy" resolves to cross country running', () {
      final r = parser.parse('30 min bieg przełajowy', bodyWeightKg: weight);
      expect(r.activityId, 'cross_country_running');
    });
  });
}
