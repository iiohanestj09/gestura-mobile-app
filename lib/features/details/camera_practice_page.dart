import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:flutter/material.dart';

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
  static const _maximumRecordingDuration = Duration(seconds: 10);

  CameraController? cameraController;
  final stopwatch = Stopwatch();
  final apiBaseUrlController = TextEditingController(
    text: GestureApiService.configuredBaseUrl,
  );
  final gestureApiService = GestureApiService();
  Timer? elapsedTimer;
  Timer? recordingLimitTimer;
  int elapsedSeconds = 0;
  GestureCategory selectedCategory = GestureCategory.alphabet;
  String selectedTarget = 'A';
  bool initializing = false;
  bool recording = false;
  bool saving = false;
  bool exposureLockedForRecording = false;
  String recordingStatus = 'Siap merekam';
  String? cameraError;
  String? recognitionError;
  String? saveError;
  String? backendStatus;
  List<String> backendCategories = const [];

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
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      elapsedTimer?.cancel();
      recordingLimitTimer?.cancel();
      stopwatch.stop();
      unawaited(_disposeCamera());
    } else if (state == AppLifecycleState.resumed && cameraController == null) {
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
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      cameraController = controller;
      setState(() {
        initializing = false;
        recordingStatus = 'Siap merekam';
      });
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
    } on Object catch (error) {
      cameraController = null;
      await controller?.dispose();
      if (!mounted) return;
      setState(() {
        cameraError = 'Kamera tidak dapat dibuka: $error';
        initializing = false;
      });
    }
  }

  Future<void> _disposeCamera() async {
    final controller = cameraController;
    cameraController = null;
    if (controller != null) {
      try {
        if (controller.value.isRecordingVideo) {
          await controller.stopVideoRecording();
        }
        await _restoreAutoExposure(controller);
        await controller.dispose();
      } on CameraException catch (error) {
        debugPrint(
            'Camera dispose failed (${error.code}): ${error.description}');
      }
    }
    if (mounted) {
      setState(() => recording = false);
    }
  }

  Future<void> _checkBackend() async {
    GestureApiService.configuredBaseUrl = apiBaseUrlController.text.trim();
    setState(() {
      backendStatus = 'Memeriksa koneksi backend…';
      backendCategories = const [];
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
      if (mounted) setState(() => backendStatus = error.message);
    } on FormatException catch (error) {
      if (mounted) setState(() => backendStatus = error.message);
    }
  }

  Future<void> _startRecording() async {
    final controller = cameraController;
    if (controller == null ||
        !controller.value.isInitialized ||
        recording ||
        saving) {
      return;
    }
    setState(() {
      recognitionError = null;
      saveError = null;
      elapsedSeconds = 0;
      recordingStatus = 'Mulai merekam…';
    });
    try {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      try {
        await controller.setExposureMode(ExposureMode.locked);
        exposureLockedForRecording = true;
      } on CameraException catch (error) {
        debugPrint(
          'Could not lock camera exposure (${error.code}): ${error.description}',
        );
        if (mounted) {
          setState(() {
            recognitionError =
                'Kamera tidak dapat mengunci kecerahan otomatis; rekaman tetap dilanjutkan.';
          });
        }
      }
      await controller.startVideoRecording();
      stopwatch
        ..reset()
        ..start();
      if (!mounted) return;
      setState(() {
        recording = true;
        recordingStatus = 'Merekam isyarat…';
      });
      elapsedTimer?.cancel();
      elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => elapsedSeconds = stopwatch.elapsed.inSeconds);
        }
      });
      recordingLimitTimer?.cancel();
      recordingLimitTimer = Timer(
        _maximumRecordingDuration,
        _stopRecordingAndSend,
      );
    } on CameraException catch (error) {
      stopwatch.stop();
      await _restoreAutoExposure(controller);
      if (mounted) {
        setState(() {
          recording = false;
          recognitionError = 'Video gagal direkam (${error.code}): '
              '${error.description ?? 'Coba lagi.'}';
          recordingStatus = 'Gagal merekam video';
        });
      }
    }
  }

  Future<void> _stopRecordingAndSend() async {
    final controller = cameraController;
    if (!recording || saving || controller == null) return;
    recordingLimitTimer?.cancel();
    elapsedTimer?.cancel();
    stopwatch.stop();
    final durationSeconds = stopwatch.elapsed.inSeconds.clamp(1, 10);
    setState(() {
      recording = false;
      saving = true;
      recordingStatus = 'Mengirim video untuk dianalisis…';
      recognitionError = null;
      saveError = null;
    });

    XFile? video;
    try {
      video = await controller.stopVideoRecording();
      await _restoreAutoExposure(controller);
      GestureApiService.configuredBaseUrl = apiBaseUrlController.text.trim();
      final result = await gestureApiService.predictVideo(
        baseUrl: apiBaseUrlController.text,
        category: selectedCategory,
        videoPath: video.path,
        onProgress: (stage) {
          if (!mounted) return;
          setState(() {
            recordingStatus = switch (stage) {
              GestureRequestStage.obtainingToken => 'Menyiapkan sesi login…',
              GestureRequestStage.sendingRequest => 'Mengunggah video latihan…',
              GestureRequestStage.awaitingResponse =>
                'Video diterima, menunggu hasil analisis…',
            };
          });
        },
      );
      if (!mounted) return;
      setState(() {
        recordingStatus = result.recognized
            ? 'Video selesai dianalisis'
            : 'Isyarat belum dikenali';
      });
      await _savePrediction(result, durationSeconds);
      if (!mounted) return;
      final matchedTarget = result.recognized && result.label == selectedTarget;
      final navigator = Navigator.of(context);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PracticeResultPage(
            category: selectedCategory,
            target: selectedTarget,
            prediction: result,
            matchedTarget: matchedTarget,
            onRetry: () {
              Navigator.of(context).pop();
              _resetPractice();
            },
            onFinish: () {
              navigator.popUntil((route) => route.isFirst);
            },
          ),
        ),
      );
    } on GestureApiException catch (error) {
      if (mounted) {
        setState(() {
          recognitionError = error.message;
          recordingStatus = 'Pengiriman video gagal';
        });
      }
    } on FormatException catch (error) {
      if (mounted) {
        setState(() {
          recognitionError = error.message;
          recordingStatus = 'Hasil video tidak valid';
        });
      }
    } on CameraException catch (error) {
      if (mounted) {
        setState(() {
          recognitionError = 'Video gagal dihentikan (${error.code}): '
              '${error.description ?? 'Coba lagi.'}';
          recordingStatus = 'Gagal merekam video';
        });
      }
    } on FileSystemException catch (error) {
      if (mounted) {
        setState(() {
          recognitionError =
              'File rekaman tidak dapat dibaca: ${error.message}';
          recordingStatus = 'Gagal membaca video';
        });
      }
    } on Object catch (error, stackTrace) {
      debugPrint('Video prediction failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          recognitionError = 'Video gagal diproses: $error';
          recordingStatus = 'Analisis video gagal';
        });
      }
    } finally {
      if (video != null) {
        try {
          await File(video.path).delete();
        } on FileSystemException catch (error) {
          debugPrint('Temporary recording cleanup failed: $error');
        }
      }
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _restoreAutoExposure(CameraController controller) async {
    if (!exposureLockedForRecording) return;
    try {
      await controller.setExposureMode(ExposureMode.auto);
      exposureLockedForRecording = false;
    } on CameraException catch (error) {
      debugPrint(
        'Could not restore automatic exposure (${error.code}): ${error.description}',
      );
      if (mounted) {
        setState(() {
          recognitionError =
              'Kecerahan otomatis kamera tidak dapat dipulihkan (${error.code}).';
        });
      }
    }
  }

  Future<void> _savePrediction(
    GesturePrediction result,
    int durationSeconds,
  ) async {
    final predictedLabel = result.label ?? result.candidate;
    if (predictedLabel == null) return;
    final matchedTarget = result.recognized && result.label == selectedTarget;
    try {
      await FirebaseService.recordGesturePrediction(
        category: selectedCategory.apiValue,
        targetLabel: selectedTarget,
        predictionLabel: predictedLabel,
        confidence: result.confidence,
        stableMilliseconds: 0,
        matchedTarget: matchedTarget,
      );
      if (matchedTarget) {
        await FirebaseService.recordPracticeSession(
          durationSeconds,
          category: selectedCategory.apiValue,
          targetLabel: selectedTarget,
          predictionLabel: result.label!,
          confidence: result.confidence,
        );
        if (mounted) setState(() => saveError = null);
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(() {
          saveError =
              error.message ?? 'Hasil latihan gagal disimpan (${error.code}).';
        });
      }
    } on StateError catch (error) {
      if (mounted) setState(() => saveError = error.message);
    }
  }

  void _resetPractice() {
    setState(() {
      recognitionError = null;
      saveError = null;
      elapsedSeconds = 0;
      recordingStatus = 'Siap merekam';
    });
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
    recordingLimitTimer?.cancel();
    stopwatch.stop();
    final controller = cameraController;
    cameraController = null;
    if (controller != null) unawaited(controller.dispose());
    apiBaseUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            PageHeading(
              'Latihan $selectedTarget',
              subtitle: 'Rekam isyarat, lalu kirim video untuk dinilai.',
            ),
            Container(
              height: 470,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: GesturaTheme.tealDark,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _cameraPreview(),
                  if (recording)
                    const Positioned(
                      top: 16,
                      left: 16,
                      child: Icon(
                        Icons.fiber_manual_record,
                        color: Colors.red,
                        size: 20,
                      ),
                    ),
                  Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        recordingStatus,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                        ),
                      ),
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
                Text(
                  'Durasi rekaman: $elapsedLabel / 00:10',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            ExpansionTile(
              title: const Text('Pengaturan koneksi'),
              tilePadding: EdgeInsets.zero,
              children: [
                TextField(
                  controller: apiBaseUrlController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enabled: !recording && !saving,
                  onChanged: (value) =>
                      GestureApiService.configuredBaseUrl = value.trim(),
                  decoration: const InputDecoration(
                    labelText: 'Alamat backend FastAPI',
                    hintText: 'http://192.168.1.5:8000',
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: saving || recording ? null : _checkBackend,
                    icon: const Icon(Icons.wifi_tethering_rounded),
                    label: const Text('Cek koneksi'),
                  ),
                ),
                if (backendStatus != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        backendStatus!,
                        style: TextStyle(
                          color: backendCategories
                                  .contains(selectedCategory.apiValue)
                              ? GesturaTheme.teal
                              : Colors.red,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SoftCard(
              child: Text(
                'Tekan Mulai rekam, peragakan isyarat di depan kamera, lalu tekan Stop & kirim video. Rekaman maksimal 10 detik dan akan dianalisis oleh backend.',
              ),
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              saving
                  ? 'Mengirim video…'
                  : recording
                      ? 'Stop & kirim video'
                      : 'Mulai rekam',
              onPressed: initializing ||
                      cameraController == null ||
                      saving ||
                      cameraError != null
                  ? null
                  : recording
                      ? _stopRecordingAndSend
                      : _startRecording,
              icon: recording
                  ? Icons.stop_circle_outlined
                  : Icons.fiber_manual_record,
            ),
            if (recognitionError != null) ...[
              const SizedBox(height: 10),
              Text(
                recognitionError!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            if (saveError != null) ...[
              const SizedBox(height: 10),
              Text(saveError!, style: const TextStyle(color: Colors.red)),
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
              const Icon(
                Icons.no_photography_outlined,
                color: Colors.white,
                size: 42,
              ),
              const SizedBox(height: 12),
              Text(
                cameraError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _initializeCamera,
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      );
    }
    final controller = cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: Text(
          'Preview kamera tidak tersedia.',
          style: TextStyle(color: Colors.white),
        ),
      );
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
}

class PracticeResultPage extends StatelessWidget {
  const PracticeResultPage({
    required this.category,
    required this.target,
    required this.prediction,
    required this.matchedTarget,
    required this.onRetry,
    required this.onFinish,
    super.key,
  });

  final GestureCategory category;
  final String target;
  final GesturePrediction prediction;
  final bool matchedTarget;
  final VoidCallback onRetry;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final title = matchedTarget ? 'Benar!' : 'Belum tepat';
    final resultLabel = prediction.label ?? prediction.candidate;
    return Scaffold(
      appBar: AppBar(title: Text('Hasil ${category.displayName}')),
      body: SafeArea(
        child: Center(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Icon(
                matchedTarget
                    ? Icons.check_circle_rounded
                    : Icons.refresh_rounded,
                size: 92,
                color: matchedTarget ? GesturaTheme.teal : GesturaTheme.yellow,
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: GesturaTheme.ink,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                matchedTarget
                    ? 'Isyarat $target berhasil dikenali.'
                    : resultLabel == null
                        ? 'Isyarat $target belum dikenali. Pastikan tangan terlihat jelas saat merekam.'
                        : 'Target $target, tetapi sistem membaca $resultLabel. Coba lagi, ya.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: GesturaTheme.muted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              if (!matchedTarget)
                PrimaryButton(
                  'Ulangi latihan',
                  onPressed: onRetry,
                  icon: Icons.replay_rounded,
                )
              else
                PrimaryButton(
                  'Selesai',
                  onPressed: onFinish,
                  icon: Icons.check_rounded,
                ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: onFinish,
                child: const Text('Kembali ke pilihan latihan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
