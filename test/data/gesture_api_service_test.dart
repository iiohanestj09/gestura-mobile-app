import 'package:flutter_test/flutter_test.dart';
import 'package:gestura/data/gesture_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('persists and restores the backend URL', () async {
    SharedPreferences.setMockInitialValues({});

    await GestureApiService.saveConfiguredBaseUrl(
        ' http://192.168.1.10:8000/ ');
    expect(GestureApiService.configuredBaseUrl, 'http://192.168.1.10:8000');

    GestureApiService.configuredBaseUrl = GestureApiService.defaultBaseUrl;
    await GestureApiService.loadConfiguredBaseUrl();

    expect(GestureApiService.configuredBaseUrl, 'http://192.168.1.10:8000');
  });

  test('exposes only the supported training targets', () {
    expect(GestureCategory.alphabet.labels, hasLength(26));
    expect(GestureCategory.digit.labels,
        ['1', '2', '3', '4', '5', '6', '7', '8', '9']);
    expect(GestureCategory.vocabulary.labels, hasLength(32));
    expect(GestureCategory.digit.labels, isNot(contains('0')));
  });

  test('builds the simulation video URL for a target with spaces', () {
    final uri = GestureApiService.simulationVideoUri(
      baseUrl: 'http://192.168.1.10:8000/',
      category: GestureCategory.vocabulary,
      target: 'Terima kasih',
    );

    expect(
      uri.toString(),
      'http://192.168.1.10:8000/api/v1/simulation/vocabulary/Terima%20kasih',
    );
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

    test('parses a video result without live-frame landmarks', () {
      final result = GesturePrediction.fromJson({
        'category': 'alphabet',
        'status': 'recognized',
        'label': 'A',
        'candidate': 'A',
        'confidence': 0.96,
        'threshold': 0.7,
        'reason': null,
        'model': 'alphabet',
        'sampled_frames': 12,
        'detected_frames': 12,
      });

      expect(result.recognized, isTrue);
      expect(result.hands, isEmpty);
      expect(result.sequence, 0);
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
