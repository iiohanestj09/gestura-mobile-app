import 'package:flutter_test/flutter_test.dart';
import 'package:gestura/data/gesture_api_service.dart';

void main() {
  test('exposes only the supported training targets', () {
    expect(GestureCategory.alphabet.labels, hasLength(26));
    expect(GestureCategory.digit.labels,
        ['1', '2', '3', '4', '5', '6', '7', '8', '9']);
    expect(GestureCategory.vocabulary.labels, hasLength(32));
    expect(GestureCategory.digit.labels, isNot(contains('0')));
  });

  group('GesturePrediction', () {
    test('parses a recognized result for the selected category', () {
      final result = GesturePrediction.fromJson({
        'category': 'alphabet',
        'status': 'recognized',
        'label': 'A',
        'candidate': 'A',
        'confidence': 0.96,
        'threshold': 0.7,
        'reason': null,
        'sampled_frames': 12,
        'detected_frames': 12,
        'hands': [
          List.generate(21, (index) => {'x': index / 20, 'y': index / 20}),
        ],
        'sequence': 3,
      });

      expect(result.category, GestureCategory.alphabet);
      expect(result.recognized, isTrue);
      expect(result.label, 'A');
      expect(result.confidence, 0.96);
    });

    test('keeps low-confidence results explicitly unrecognized', () {
      final result = GesturePrediction.fromJson({
        'category': 'vocabulary',
        'status': 'not_recognized',
        'label': null,
        'candidate': 'Merah',
        'confidence': 0.4,
        'threshold': 0.5,
        'reason': 'Confidence di bawah ambang model.',
        'sampled_frames': 12,
        'detected_frames': 8,
        'hands': <List<Map<String, double>>>[],
        'sequence': 3,
      });

      expect(result.recognized, isFalse);
      expect(result.label, isNull);
      expect(result.candidate, 'Merah');
    });

    test('rejects a response without a supported category', () {
      expect(
        () => GesturePrediction.fromJson({
          'category': 'expression',
          'status': 'recognized',
          'label': 'x',
          'candidate': 'x',
          'confidence': 1,
          'threshold': 0,
          'reason': null,
          'sampled_frames': 1,
          'detected_frames': 1,
          'hands': <List<Map<String, double>>>[],
          'sequence': 1,
        }),
        throwsFormatException,
      );
    });
  });
}
