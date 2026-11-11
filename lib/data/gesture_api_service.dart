import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum GestureCategory {
  alphabet('alphabet', 'Alfabet A-Z', _alphabetLabels),
  digit('digit', 'Angka 1-9', _digitLabels),
  vocabulary('vocabulary', 'Kosakata BISINDO', _vocabularyLabels);

  const GestureCategory(this.apiValue, this.displayName, this.labels);

  final String apiValue;
  final String displayName;
  final List<String> labels;

  static const _alphabetLabels = [
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
  ];
  static const _digitLabels = ['1', '2', '3', '4', '5', '6', '7', '8', '9'];
  static const _vocabularyLabels = [
    'Air',
    'Belajar',
    'Cari',
    'Hari',
    'Ingat',
    'Lagi',
    'Maaf',
    'Makan',
    'Motor',
    'Saya',
    'Terima kasih',
    'Tuli',
    'Apa',
    'Siapa',
    'Kapan',
    'Di mana',
    'Mengapa',
    'Bagaimana',
    'Merah',
    'Kuning',
    'Hijau',
    'Hitam',
    'Dengar',
    'Berangkat',
    'Datang',
    'Teman',
    'Keluarga',
    'Rumah',
    'Pagi',
    'Siang',
    'Sore',
    'Malam',
  ];
}

class GestureLandmark {
  const GestureLandmark(this.x, this.y);

  final double x;
  final double y;
}

class GestureApiException implements Exception {
  const GestureApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum GestureRequestStage {
  obtainingToken,
  sendingRequest,
  awaitingResponse,
}

class GesturePrediction {
  const GesturePrediction({
    required this.category,
    required this.status,
    required this.label,
    required this.candidate,
    required this.confidence,
    required this.threshold,
    required this.reason,
    required this.sampledFrames,
    required this.detectedFrames,
    required this.hands,
    required this.sequence,
  });

  final GestureCategory category;
  final String status;
  final String? label;
  final String? candidate;
  final double confidence;
  final double threshold;
  final String? reason;
  final int sampledFrames;
  final int detectedFrames;
  final List<List<GestureLandmark>> hands;
  final int sequence;

  bool get recognized => status == 'recognized' && label != null;

  factory GesturePrediction.fromJson(Map<String, dynamic> json) {
    final category = GestureCategory.values.firstWhere(
      (item) => item.apiValue == json['category'],
      orElse: () => throw const FormatException(
        'API mengembalikan kategori model yang tidak dikenal.',
      ),
    );
    final status = json['status'];
    final confidence = json['confidence'];
    final threshold = json['threshold'];
    final sampledFrames = json['sampled_frames'];
    final detectedFrames = json['detected_frames'];
    final sequence = json['sequence'] ?? 0;
    final rawHands = json['hands'] ?? const <dynamic>[];
    if ((status != 'recognized' && status != 'not_recognized') ||
        confidence is! num ||
        threshold is! num ||
        sampledFrames is! int ||
        detectedFrames is! int ||
        sequence is! int ||
        rawHands is! List) {
      throw const FormatException(
          'Format hasil pengenalan dari API tidak valid.');
    }
    final hands = rawHands.map<List<GestureLandmark>>((rawHand) {
      if (rawHand is! List) {
        throw const FormatException('Format landmark tangan tidak valid.');
      }
      return rawHand.map<GestureLandmark>((rawPoint) {
        if (rawPoint is! Map ||
            rawPoint['x'] is! num ||
            rawPoint['y'] is! num) {
          throw const FormatException('Koordinat landmark tidak valid.');
        }
        return GestureLandmark(
          (rawPoint['x'] as num).toDouble(),
          (rawPoint['y'] as num).toDouble(),
        );
      }).toList(growable: false);
    }).toList(growable: false);
    if (hands.any((hand) => hand.length != 21)) {
      throw const FormatException(
        'API harus mengirim 21 titik untuk setiap tangan.',
      );
    }

    return GesturePrediction(
      category: category,
      status: status as String,
      label: json['label'] as String?,
      candidate: json['candidate'] as String?,
      confidence: confidence.toDouble(),
      threshold: threshold.toDouble(),
      reason: json['reason'] as String?,
      sampledFrames: sampledFrames,
      detectedFrames: detectedFrames,
      hands: hands,
      sequence: sequence,
    );
  }
}

class GestureApiService {
  static const defaultBaseUrl = String.fromEnvironment(
    'GESTURA_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );
  static const _baseUrlPreferenceKey = 'gestura_api_base_url';
  static String configuredBaseUrl = defaultBaseUrl;
  static const _timeout = Duration(seconds: 90);
  static const _tokenTimeout = Duration(seconds: 20);
  static final http.Client _client = http.Client();

  static Future<void> loadConfiguredBaseUrl() async {
    final preferences = await SharedPreferences.getInstance();
    configuredBaseUrl =
        preferences.getString(_baseUrlPreferenceKey) ?? defaultBaseUrl;
  }

  static Future<void> saveConfiguredBaseUrl(String baseUrl) async {
    final normalizedUrl = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _baseUrlPreferenceKey,
      normalizedUrl,
    );
    if (!saved) {
      throw StateError('Alamat backend gagal disimpan di perangkat.');
    }
    configuredBaseUrl = normalizedUrl;
  }

  static Uri _endpoint(String baseUrl, String path) {
    final value = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final baseUri = Uri.tryParse(value);
    if (baseUri == null ||
        (baseUri.scheme != 'http' && baseUri.scheme != 'https') ||
        baseUri.host.isEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment) {
      throw const FormatException(
        'Alamat backend harus berupa URL lengkap, misalnya http://192.168.1.5:8000.',
      );
    }
    return Uri.parse('$value$path');
  }

  static Uri simulationVideoUri({
    required String baseUrl,
    required GestureCategory category,
    required String target,
  }) =>
      _endpoint(
        baseUrl,
        '/api/v1/simulation/${category.apiValue}/${Uri.encodeComponent(target)}',
      );

  Future<List<String>> checkHealth(String baseUrl) async {
    final uri = _endpoint(baseUrl, '/health');
    try {
      final response = await _client.get(uri).timeout(_timeout);
      final data = _decodeResponse(response.body);
      if (response.statusCode != 200) {
        throw GestureApiException(_errorMessage(data, response.statusCode));
      }
      if (data['status'] != 'ok' || data['categories'] is! List) {
        throw const FormatException('Respons health API tidak valid.');
      }
      return (data['categories'] as List).whereType<String>().toList();
    } on http.ClientException catch (error) {
      throw GestureApiException('Tidak dapat terhubung ke backend: $error');
    } on SocketException catch (error) {
      throw GestureApiException('Tidak dapat terhubung ke backend: $error');
    } on TimeoutException {
      throw const GestureApiException(
        'Backend tidak merespons. Periksa alamat dan koneksi jaringan.',
      );
    }
  }

  Future<GesturePrediction> predictFrame({
    required String baseUrl,
    required GestureCategory category,
    required Uint8List jpegBytes,
    required String sessionId,
    void Function(GestureRequestStage stage)? onProgress,
  }) async {
    final uri = _endpoint(
      baseUrl,
      '/api/v1/predict/${category.apiValue}/frame',
    );
    var requestStarted = false;
    try {
      onProgress?.call(GestureRequestStage.obtainingToken);
      final token = await _firebaseIdToken().timeout(_tokenTimeout);
      final request = http.MultipartRequest('POST', uri)
        ..headers['Accept'] = 'application/json'
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['session_id'] = sessionId
        ..files.add(
          http.MultipartFile.fromBytes(
            'frame',
            jpegBytes,
            filename: 'frame.jpg',
            contentType: http.MediaType('image', 'jpeg'),
          ),
        );
      onProgress?.call(GestureRequestStage.sendingRequest);
      requestStarted = true;
      final streamedResponse = await _client.send(request).timeout(_timeout);
      onProgress?.call(GestureRequestStage.awaitingResponse);
      final response =
          await http.Response.fromStream(streamedResponse).timeout(_timeout);
      final data = _decodeResponse(response.body);
      if (response.statusCode != 200) {
        throw GestureApiException(_errorMessage(data, response.statusCode));
      }
      final prediction = GesturePrediction.fromJson(data);
      if (prediction.category != category) {
        throw const FormatException(
          'Kategori hasil API tidak sesuai dengan model yang dipilih.',
        );
      }
      return prediction;
    } on http.ClientException catch (error) {
      throw GestureApiException('Tidak dapat menghubungi backend: $error');
    } on SocketException catch (error) {
      throw GestureApiException('Tidak dapat menghubungi backend: $error');
    } on TimeoutException {
      if (!requestStarted) {
        throw const GestureApiException(
          'Firebase terlalu lama menyiapkan token login. Periksa koneksi internet lalu coba lagi.',
        );
      }
      throw const GestureApiException(
        'Proses melewati batas waktu. Periksa koneksi dan coba lagi.',
      );
    }
  }

  Future<void> clearSession({
    required String baseUrl,
    required String sessionId,
  }) async {
    final uri = _endpoint(baseUrl, '/api/v1/session/$sessionId');
    final token = await _firebaseIdToken();
    try {
      final response = await _client.delete(
        uri,
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(_timeout);
      final data = _decodeResponse(response.body);
      if (response.statusCode != 200) {
        throw GestureApiException(_errorMessage(data, response.statusCode));
      }
    } on http.ClientException catch (error) {
      throw GestureApiException('Tidak dapat menghubungi backend: $error');
    } on SocketException catch (error) {
      throw GestureApiException('Tidak dapat menghubungi backend: $error');
    } on TimeoutException {
      throw const GestureApiException(
        'Backend tidak merespons saat sesi ditutup.',
      );
    }
  }

  Future<GesturePrediction> predictVideo({
    required String baseUrl,
    required GestureCategory category,
    required String videoPath,
    void Function(GestureRequestStage stage)? onProgress,
  }) async {
    final uri = _endpoint(
      baseUrl,
      '/api/v1/predict/${category.apiValue}',
    );
    var requestStarted = false;
    try {
      onProgress?.call(GestureRequestStage.obtainingToken);
      final token = await _firebaseIdToken().timeout(_tokenTimeout);
      final request = http.MultipartRequest('POST', uri)
        ..headers['Accept'] = 'application/json'
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(await http.MultipartFile.fromPath('video', videoPath));
      onProgress?.call(GestureRequestStage.sendingRequest);
      requestStarted = true;
      final streamedResponse = await _client.send(request).timeout(_timeout);
      onProgress?.call(GestureRequestStage.awaitingResponse);
      final response =
          await http.Response.fromStream(streamedResponse).timeout(_timeout);
      final data = _decodeResponse(response.body);
      if (response.statusCode != 200) {
        throw GestureApiException(_errorMessage(data, response.statusCode));
      }
      final prediction = GesturePrediction.fromJson(data);
      if (prediction.category != category) {
        throw const FormatException(
          'Kategori hasil API tidak sesuai dengan model yang dipilih.',
        );
      }
      return prediction;
    } on http.ClientException catch (error) {
      throw GestureApiException('Tidak dapat menghubungi backend: $error');
    } on SocketException catch (error) {
      throw GestureApiException('Tidak dapat menghubungi backend: $error');
    } on TimeoutException {
      if (!requestStarted) {
        throw const GestureApiException(
          'Firebase terlalu lama menyiapkan token login. Periksa koneksi internet lalu coba lagi.',
        );
      }
      throw const GestureApiException(
        'Proses melewati batas waktu. Periksa koneksi dan coba lagi.',
      );
    } on FileSystemException catch (error) {
      throw GestureApiException('File rekaman tidak dapat dibaca: $error');
    }
  }

  Future<String> _firebaseIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const GestureApiException(
        'Sesi login berakhir. Login kembali untuk memakai pengenalan gerakan.',
      );
    }
    try {
      final token = await user.getIdToken();
      if (token == null || token.isEmpty) {
        throw const GestureApiException(
          'Firebase tidak menghasilkan ID token. Login kembali.',
        );
      }
      return token;
    } on FirebaseAuthException catch (error) {
      throw GestureApiException(
        error.message ?? 'Token Firebase gagal diperoleh (${error.code}).',
      );
    }
  }

  Map<String, dynamic> _decodeResponse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Respons backend bukan objek JSON.');
    }
    return decoded;
  }

  String _errorMessage(Map<String, dynamic> data, int statusCode) {
    final detail = data['detail'];
    return detail is String
        ? detail
        : 'Permintaan ke backend gagal (HTTP $statusCode).';
  }
}
