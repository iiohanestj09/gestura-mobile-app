import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../../core/gestura_theme.dart';
import '../../data/firebase_service.dart';
import '../../data/gesture_api_service.dart';
import '../../widgets/gestura_widgets.dart';

class CameraPracticePage extends StatefulWidget {
  const CameraPracticePage({
    this.initialCategory,
    this.initialTarget,
    super.key,
  });

  final GestureCategory? initialCategory;
  final String? initialTarget;

  @override
  State<CameraPracticePage> createState() => _CameraPracticePageState();
}

class _CameraPracticePageState extends State<CameraPracticePage>
    with WidgetsBindingObserver {
  CameraController? cameraController;
  final stopwatch = Stopwatch();
  Timer? elapsedTimer;
  int elapsedSeconds = 0;
  GestureCategory selectedCategory = GestureCategory.alphabet;
  String selectedTarget = 'A';
  GesturePrediction? prediction;
  bool initializing = false;
  bool saving = false;
  bool processingFrame = false;
  bool completing = false;
  bool finished = false;
  String? cameraError;
  String? saveError;
  String? recognitionError;
  String? backendStatus;
  List<String> backendCategories = const [];
  DateTime? lastFrameSentAt;
  DateTime? candidateStartedAt;
  String? activeCandidate;
  int candidateSegment = 0;
  int? savedCandidateSegment;
  int correctHoldMilliseconds = 0;
  List<List<GestureLandmark>> currentHands = const [];
  late String liveSessionId;
  final apiBaseUrlController = TextEditingController(
    text: GestureApiService.defaultBaseUrl,
  );
  final gestureApiService = GestureApiService();

  String get categoryName => switch (selectedCategory) {
        GestureCategory.alphabet => 'Alfabet A-Z',
        GestureCategory.digit => 'Angka 1-9',
        GestureCategory.vocabulary => 'Kosakata',
      };

  @override
  void initState() {
    super.initState();
    selectedCategory = widget.initialCategory ?? GestureCategory.alphabet;
    selectedTarget = widget.initialTarget != null &&
            selectedCategory.labels.contains(widget.initialTarget)
        ? widget.initialTarget!
        : selectedCategory.labels.first;
    liveSessionId = _newSessionId();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  String _newSessionId() {
    final random = Random.secure();
    return List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      stopwatch.stop();
      elapsedTimer?.cancel();
      currentHands = const [];
      unawaited(_disposeCamera());
    } else if (state == AppLifecycleState.resumed &&
        cameraController == null &&
        !finished) {
      liveSessionId = _newSessionId();
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    if (initializing) return;
    setState(() {
      initializing = true;
      cameraError = null;
    });
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('Kamera tidak ditemukan pada perangkat ini.');
      }
      final camera = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      cameraController = controller;
      await controller.startImageStream(_processCameraImage);
      stopwatch.start();
      elapsedTimer?.cancel();
      elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => elapsedSeconds = stopwatch.elapsed.inSeconds);
        }
      });
      setState(() => initializing = false);
    } on CameraException catch (error) {
      cameraController = null;
      await controller?.dispose();
      if (!mounted) return;
      setState(() {
        cameraError = 'Kamera tidak dapat dibuka (${error.code}): '
            '${error.description ?? 'Periksa izin kamera perangkat.'}';
        initializing = false;
      });
    } on StateError catch (error) {
      cameraController = null;
      await controller?.dispose();
      if (!mounted) return;
      setState(() {
        cameraError = error.message;
        initializing = false;
      });
    } on MissingPluginException {
      cameraController = null;
      await controller?.dispose();
      if (!mounted) return;
      setState(() {
        cameraError = 'Preview kamera belum didukung pada platform ini.';
        initializing = false;
      });
    } on PlatformException catch (error) {
      cameraController = null;
      await controller?.dispose();
      if (!mounted) return;
      setState(() {
        cameraError =
            'Kamera tidak dapat dibuka: ${error.message ?? error.code}.';
        initializing = false;
      });
    }
  }

  Future<void> _disposeCamera() async {
    final controller = cameraController;
    cameraController = null;
    unawaited(_clearLiveSession(liveSessionId));
    if (controller != null) {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      await controller.dispose();
    }
  }

  Future<void> _clearLiveSession(String sessionId) async {
    try {
      await gestureApiService.clearSession(
        baseUrl: apiBaseUrlController.text,
        sessionId: sessionId,
      );
    } on GestureApiException catch (error) {
      if (mounted) {
        setState(() {
          recognitionError = 'Sesi backend belum dapat dibersihkan: '
              '${error.message}';
        });
      }
    } on FormatException catch (error) {
      if (mounted) {
        setState(() => recognitionError = error.message);
      }
    }
  }

  Future<void> _checkBackend() async {
    setState(() {
      backendStatus = 'Memeriksa koneksi backend…';
      backendCategories = const [];
      recognitionError = null;
    });
    try {
      final categories =
          await gestureApiService.checkHealth(apiBaseUrlController.text);
      if (!mounted) return;
      setState(() {
        backendCategories = categories;
        backendStatus = categories.contains(selectedCategory.apiValue)
            ? 'Backend terhubung dan model $categoryName tersedia.'
            : 'Backend terhubung, tetapi model $categoryName belum tersedia.';
      });
    } on GestureApiException catch (error) {
      if (!mounted) return;
      setState(() => backendStatus = error.message);
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() => backendStatus = error.message);
    }
  }

  Uint8List _encodeCameraFrame(CameraImage cameraImage) {
    final width = cameraImage.width;
    final height = cameraImage.height;
    final image = img.Image(width: width, height: height);
    if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
      final plane = cameraImage.planes.first;
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final offset = y * plane.bytesPerRow + x * 4;
          image.setPixelRgb(
            x,
            y,
            plane.bytes[offset + 2],
            plane.bytes[offset + 1],
            plane.bytes[offset],
          );
        }
      }
    } else if (cameraImage.format.group == ImageFormatGroup.yuv420 &&
        cameraImage.planes.length >= 3) {
      final yPlane = cameraImage.planes[0];
      final uPlane = cameraImage.planes[1];
      final vPlane = cameraImage.planes[2];
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final yOffset = y * yPlane.bytesPerRow + x;
          final chromaX = x ~/ 2;
          final chromaY = y ~/ 2;
          final uOffset =
              chromaY * uPlane.bytesPerRow + chromaX * uPlane.bytesPerPixel!;
          final vOffset =
              chromaY * vPlane.bytesPerRow + chromaX * vPlane.bytesPerPixel!;
          final luminance = yPlane.bytes[yOffset].toDouble();
          final blueDifference = uPlane.bytes[uOffset] - 128;
          final redDifference = vPlane.bytes[vOffset] - 128;
          final red = (luminance + 1.402 * redDifference).round().clamp(0, 255);
          final green =
              (luminance - 0.344136 * blueDifference - 0.714136 * redDifference)
                  .round()
                  .clamp(0, 255);
          final blue =
              (luminance + 1.772 * blueDifference).round().clamp(0, 255);
          image.setPixelRgb(x, y, red, green, blue);
        }
      }
    } else {
      throw const FormatException('Format frame kamera belum didukung.');
    }

    final orientation = cameraController?.description.sensorOrientation ?? 0;
    final uprightImage =
        orientation == 0 ? image : img.copyRotate(image, angle: orientation);
    return Uint8List.fromList(img.encodeJpg(uprightImage, quality: 75));
  }

  Future<void> _processCameraImage(CameraImage cameraImage) async {
    final now = DateTime.now();
    if (!mounted ||
        processingFrame ||
        completing ||
        finished ||
        now.difference(
              lastFrameSentAt ?? DateTime.fromMillisecondsSinceEpoch(0),
            ) <
            const Duration(milliseconds: 450)) {
      return;
    }
    processingFrame = true;
    lastFrameSentAt = now;
    try {
      final jpegBytes = _encodeCameraFrame(cameraImage);
      final result = await gestureApiService.predictFrame(
        baseUrl: apiBaseUrlController.text,
        category: selectedCategory,
        jpegBytes: jpegBytes,
        sessionId: liveSessionId,
      );
      await _handlePrediction(result);
    } on GestureApiException catch (error) {
      if (mounted) setState(() => recognitionError = error.message);
    } on FormatException catch (error) {
      if (mounted) setState(() => recognitionError = error.message);
    } on RangeError catch (error) {
      if (mounted) {
        setState(() => recognitionError =
            'Data frame kamera tidak valid: ${error.message}');
      }
    } on CameraException catch (error) {
      if (mounted) {
        setState(() =>
            recognitionError = 'Frame kamera gagal dibaca (${error.code}): '
                '${error.description ?? 'Coba lagi.'}');
      }
    } finally {
      processingFrame = false;
    }
  }

  Future<void> _handlePrediction(GesturePrediction result) async {
    if (!mounted || completing) return;
    final candidate = result.recognized ? result.label : null;
    final now = DateTime.now();
    if (candidate == null) {
      activeCandidate = null;
      candidateStartedAt = null;
      savedCandidateSegment = null;
      correctHoldMilliseconds = 0;
    } else if (candidate != activeCandidate) {
      activeCandidate = candidate;
      candidateStartedAt = now;
      savedCandidateSegment = null;
      candidateSegment++;
      correctHoldMilliseconds = 0;
    } else {
      correctHoldMilliseconds =
          now.difference(candidateStartedAt ?? now).inMilliseconds;
    }
    setState(() {
      prediction = result;
      currentHands = result.hands;
      recognitionError = null;
    });

    final heldMilliseconds = correctHoldMilliseconds;
    if (candidate == null) return;
    if (heldMilliseconds < 1000 || savedCandidateSegment == candidateSegment) {
      if (candidate == selectedTarget &&
          heldMilliseconds >= 1500 &&
          savedCandidateSegment == candidateSegment) {
        await _completeCorrectGesture(result, heldMilliseconds);
      }
      return;
    }
    setState(() => saving = true);
    try {
      await FirebaseService.recordGesturePrediction(
        category: selectedCategory.apiValue,
        targetLabel: selectedTarget,
        predictionLabel: candidate,
        confidence: result.confidence,
        stableMilliseconds: heldMilliseconds,
        matchedTarget: candidate == selectedTarget,
      );
      savedCandidateSegment = candidateSegment;
      if (mounted) setState(() => saveError = null);
      if (candidate == selectedTarget && heldMilliseconds >= 1500) {
        await _completeCorrectGesture(result, heldMilliseconds);
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(() {
          saveError =
              error.message ?? 'Prediksi gagal disimpan (${error.code}).';
        });
      }
    } on StateError catch (error) {
      if (mounted) setState(() => saveError = error.message);
    } finally {
      if (mounted && !finished) setState(() => saving = false);
    }
  }

  Future<void> _completeCorrectGesture(
    GesturePrediction result,
    int stableMilliseconds,
  ) async {
    if (completing || result.label != selectedTarget) return;
    completing = true;
    setState(() {
      saving = true;
      saveError = null;
    });
    final controller = cameraController;
    try {
      if (controller?.value.isStreamingImages == true) {
        await controller!.stopImageStream();
      }
      stopwatch.stop();
      elapsedTimer?.cancel();
      final seconds = stopwatch.elapsed.inSeconds;
      await FirebaseService.recordPracticeSession(
        seconds < 1 ? 1 : seconds,
        category: selectedCategory.apiValue,
        targetLabel: selectedTarget,
        predictionLabel: result.label!,
        confidence: result.confidence,
      );
      await _disposeCamera();
      if (!mounted) return;
      setState(() {
        saving = false;
        finished = true;
        correctHoldMilliseconds = stableMilliseconds;
      });
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(() {
          saving = false;
          saveError =
              error.message ?? 'Latihan gagal disimpan (${error.code}).';
        });
      }
      if (controller?.value.isInitialized == true &&
          !controller!.value.isStreamingImages) {
        await controller.startImageStream(_processCameraImage);
      }
    } on StateError catch (error) {
      if (mounted) setState(() => saveError = error.message);
    } on CameraException catch (error) {
      if (mounted) {
        setState(() {
          saving = false;
          saveError = 'Kamera gagal dihentikan (${error.code}).';
        });
      }
      if (controller?.value.isInitialized == true &&
          !controller!.value.isStreamingImages) {
        await controller.startImageStream(_processCameraImage);
      }
    } finally {
      completing = false;
    }
  }

  Future<void> _startAgain() async {
    await _disposeCamera();
    liveSessionId = _newSessionId();
    stopwatch
      ..reset()
      ..start();
    elapsedTimer?.cancel();
    setState(() {
      elapsedSeconds = 0;
      prediction = null;
      finished = false;
      cameraError = null;
      saveError = null;
      recognitionError = null;
      backendStatus = null;
      activeCandidate = null;
      candidateStartedAt = null;
      savedCandidateSegment = null;
      candidateSegment = 0;
      correctHoldMilliseconds = 0;
      currentHands = const [];
    });
    await _initializeCamera();
  }

  String get elapsedLabel {
    final minutes = elapsedSeconds ~/ 60;
    final seconds = elapsedSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    elapsedTimer?.cancel();
    stopwatch.stop();
    unawaited(_disposeCamera());
    apiBaseUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            PageHeading(
              finished ? 'Sesi latihan selesai' : 'Kamera latihan',
              subtitle: finished
                  ? 'Target $selectedTarget berhasil dikenali. Durasi: $elapsedLabel.'
                  : 'Peragakan isyarat $selectedTarget dan tahan sampai sistem mengenalinya.',
            ),
            if (finished) ...[
              SoftCard(
                  child: Text(
                      'Target $selectedTarget berhasil dikenali secara konsisten. Hasil dan durasi latihan tersimpan di akunmu.')),
              const SizedBox(height: 16),
              PrimaryButton('Mulai sesi baru', onPressed: _startAgain),
            ] else ...[
              Container(
                height: 360,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: GesturaTheme.tealDark,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _cameraPreview(),
                    if (currentHands.isNotEmpty)
                      CustomPaint(
                        painter: _HandLandmarkPainter(
                          currentHands,
                          mirror: cameraController?.description.lensDirection ==
                              CameraLensDirection.front,
                        ),
                      ),
                    if (activeCandidate == selectedTarget)
                      Positioned(
                        left: 18,
                        right: 18,
                        bottom: 18,
                        child: LinearProgressIndicator(
                          value: (correctHoldMilliseconds / 1500)
                              .clamp(0, 1)
                              .toDouble(),
                          minHeight: 8,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.timer_outlined, color: GesturaTheme.teal),
                  const SizedBox(width: 8),
                  Text('Durasi: $elapsedLabel',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<GestureCategory>(
                initialValue: selectedCategory,
                decoration: const InputDecoration(labelText: 'Kategori model'),
                items: GestureCategory.values
                    .map(
                      (category) => DropdownMenuItem(
                        value: category,
                        child: Text(category.displayName),
                      ),
                    )
                    .toList(growable: false),
                onChanged: saving || processingFrame
                    ? null
                    : (category) async {
                        if (category == null) return;
                        final controller = cameraController;
                        if (controller?.value.isStreamingImages == true) {
                          await controller!.stopImageStream();
                        }
                        final oldSessionId = liveSessionId;
                        liveSessionId = _newSessionId();
                        unawaited(_clearLiveSession(oldSessionId));
                        setState(() {
                          selectedCategory = category;
                          selectedTarget = category.labels.first;
                          prediction = null;
                          currentHands = const [];
                          activeCandidate = null;
                          candidateStartedAt = null;
                          savedCandidateSegment = null;
                          correctHoldMilliseconds = 0;
                          backendStatus = null;
                        });
                        if (controller?.value.isInitialized == true &&
                            !finished) {
                          await controller!
                              .startImageStream(_processCameraImage);
                        }
                      },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: selectedTarget,
                decoration: InputDecoration(
                  labelText:
                      'Target latihan (${selectedCategory.labels.length} pilihan)',
                ),
                items: selectedCategory.labels
                    .map(
                      (label) => DropdownMenuItem(
                        value: label,
                        child: Text(label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: saving || processingFrame
                    ? null
                    : (label) {
                        if (label == null) return;
                        final oldSessionId = liveSessionId;
                        liveSessionId = _newSessionId();
                        unawaited(_clearLiveSession(oldSessionId));
                        setState(() {
                          selectedTarget = label;
                          prediction = null;
                          currentHands = const [];
                          activeCandidate = null;
                          candidateStartedAt = null;
                          savedCandidateSegment = null;
                          correctHoldMilliseconds = 0;
                        });
                      },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: apiBaseUrlController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Alamat backend FastAPI',
                  hintText: 'http://192.168.1.5:8000',
                  helperText:
                      'Gunakan IP laptop pada Wi-Fi yang sama, atau 127.0.0.1 dengan adb reverse.',
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: processingFrame ? null : _checkBackend,
                  icon: const Icon(Icons.wifi_tethering_rounded),
                  label: const Text('Cek koneksi'),
                ),
              ),
              if (backendStatus != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    backendStatus!,
                    style: TextStyle(
                      color:
                          backendCategories.contains(selectedCategory.apiValue)
                              ? GesturaTheme.teal
                              : Colors.red,
                    ),
                  ),
                ),
              SoftCard(
                child: Text(
                  'Kamera depan aktif. Sistem membaca ${selectedCategory.labels.length} target $categoryName secara real-time, menggambar 21 titik landmark tangan, dan menyelesaikan latihan saat target $selectedTarget dikenali konsisten selama minimal 1,5 detik.',
                ),
              ),
              if (recognitionError != null) ...[
                const SizedBox(height: 10),
                Text(
                  recognitionError!,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
              if (prediction != null) ...[
                const SizedBox(height: 12),
                _predictionCard(prediction!),
                const SizedBox(height: 6),
                Text(
                  prediction!.recognized && prediction!.label == selectedTarget
                      ? 'Target cocok • tahan ${(1.5 - correctHoldMilliseconds / 1000).clamp(0, 1.5).toStringAsFixed(1)} detik lagi'
                      : prediction!.recognized
                          ? 'Terbaca ${prediction!.label}; target latihan $selectedTarget'
                          : 'Menunggu isyarat yang jelas…',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: GesturaTheme.tealDark,
                  ),
                ),
              ],
              if (saveError != null) ...[
                const SizedBox(height: 10),
                Text(saveError!, style: const TextStyle(color: Colors.red)),
              ],
              if (cameraError == null && !initializing) ...[
                const SizedBox(height: 16),
                Text(
                  saving
                      ? 'Menyimpan prediksi dan progres…'
                      : 'Analisis kamera aktif • target berhenti otomatis saat cocok',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: GesturaTheme.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ],
        ),
      );

  Widget _cameraPreview() {
    if (initializing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined,
                  color: Colors.white, size: 42),
              const SizedBox(height: 12),
              Text(cameraError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 12),
              OutlinedButton(
                  onPressed: _initializeCamera, child: const Text('Coba lagi')),
            ],
          ),
        ),
      );
    }
    final controller = cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
          child: Text('Preview kamera tidak tersedia.',
              style: TextStyle(color: Colors.white)));
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(controller),
        Center(
          child: Container(
            width: 190,
            height: 220,
            decoration: BoxDecoration(
              border: Border.all(color: GesturaTheme.yellow, width: 2),
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
      ],
    );
  }

  Widget _predictionCard(GesturePrediction result) {
    final background =
        result.recognized ? GesturaTheme.mint : const Color(0xFFFFF1D6);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.recognized ? 'Prediksi model' : 'Gerakan belum dikenali',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            result.recognized
                ? result.label!
                : result.candidate == null
                    ? 'Tidak ada kandidat'
                    : 'Kandidat: ${result.candidate}',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'Confidence ${(result.confidence * 100).toStringAsFixed(1)}% '
            '(ambang ${(result.threshold * 100).toStringAsFixed(1)}%)',
          ),
          if (result.reason != null) ...[
            const SizedBox(height: 6),
            Text(result.reason!),
          ],
          const SizedBox(height: 6),
          Text(
            'Tangan terdeteksi pada ${result.detectedFrames} dari '
            '${result.sampledFrames} frame.',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _HandLandmarkPainter extends CustomPainter {
  const _HandLandmarkPainter(this.hands, {required this.mirror});

  final List<List<GestureLandmark>> hands;
  final bool mirror;

  static const _connections = [
    [0, 1, 2, 3, 4],
    [0, 5, 6, 7, 8],
    [5, 9, 13, 17, 5],
    [0, 9, 10, 11, 12],
    [0, 13, 14, 15, 16],
    [0, 17, 18, 19, 20],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = GesturaTheme.yellow
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final pointPaint = Paint()..color = Colors.white;
    final outlinePaint = Paint()
      ..color = GesturaTheme.tealDark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final hand in hands) {
      if (hand.length != 21) continue;
      Offset pointAt(int index) {
        final point = hand[index];
        final x = mirror ? 1 - point.x : point.x;
        return Offset(x * size.width, point.y * size.height);
      }

      for (final connection in _connections) {
        for (var index = 0; index < connection.length - 1; index++) {
          canvas.drawLine(
            pointAt(connection[index]),
            pointAt(connection[index + 1]),
            linePaint,
          );
        }
      }
      for (var index = 0; index < hand.length; index++) {
        final point = pointAt(index);
        canvas.drawCircle(point, 4, pointPaint);
        canvas.drawCircle(point, 4, outlinePaint);
      }
    }
  }

  @override
  bool shouldRepaint(_HandLandmarkPainter oldDelegate) =>
      oldDelegate.hands != hands || oldDelegate.mirror != mirror;
}
