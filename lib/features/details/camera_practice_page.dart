import 'dart:async';

import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/gestura_theme.dart';
import '../../data/firebase_service.dart';
import '../../widgets/gestura_widgets.dart';

class CameraPracticePage extends StatefulWidget {
  const CameraPracticePage({super.key});

  @override
  State<CameraPracticePage> createState() => _CameraPracticePageState();
}

class _CameraPracticePageState extends State<CameraPracticePage>
    with WidgetsBindingObserver {
  CameraController? cameraController;
  final stopwatch = Stopwatch();
  Timer? elapsedTimer;
  int elapsedSeconds = 0;
  bool initializing = false;
  bool saving = false;
  bool finished = false;
  String? cameraError;
  String? saveError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      stopwatch.stop();
      elapsedTimer?.cancel();
      unawaited(_disposeCamera());
    } else if (state == AppLifecycleState.resumed &&
        cameraController == null &&
        !finished) {
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
        (item) => item.lensDirection == CameraLensDirection.back,
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
      stopwatch.start();
      elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => elapsedSeconds = stopwatch.elapsed.inSeconds);
        }
      });
      setState(() => initializing = false);
    } on CameraException catch (error) {
      await controller?.dispose();
      if (!mounted) return;
      setState(() {
        cameraError = 'Kamera tidak dapat dibuka (${error.code}): '
            '${error.description ?? 'Periksa izin kamera perangkat.'}';
        initializing = false;
      });
    } on StateError catch (error) {
      await controller?.dispose();
      if (!mounted) return;
      setState(() {
        cameraError = error.message;
        initializing = false;
      });
    } on MissingPluginException {
      if (!mounted) return;
      setState(() {
        cameraError = 'Preview kamera belum didukung pada platform ini.';
        initializing = false;
      });
    } on PlatformException catch (error) {
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
    if (controller != null) await controller.dispose();
  }

  Future<void> _finishPractice() async {
    if (saving || elapsedSeconds < 1) return;
    stopwatch.stop();
    elapsedTimer?.cancel();
    setState(() {
      saving = true;
      saveError = null;
    });
    try {
      await FirebaseService.recordPracticeSession(elapsedSeconds);
      await _disposeCamera();
      if (!mounted) return;
      setState(() {
        saving = false;
        finished = true;
      });
    } on FirebaseException catch (error) {
      if (!mounted) return;
      setState(() {
        saving = false;
        saveError = error.message ?? 'Sesi gagal disimpan (${error.code}).';
      });
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() {
        saving = false;
        saveError = error.message;
      });
    }
  }

  Future<void> _startAgain() async {
    await _disposeCamera();
    stopwatch
      ..reset()
      ..start();
    setState(() {
      elapsedSeconds = 0;
      finished = false;
      cameraError = null;
      saveError = null;
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
                  ? 'Durasi latihan: $elapsedLabel.'
                  : 'Arahkan tangan ke dalam area panduan dan berlatih mandiri.',
            ),
            if (finished) ...[
              const SoftCard(
                  child: Text(
                      'Durasi sesi tersimpan di akunmu. Aplikasi tidak merekam gambar atau mengenali gerakan.')),
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
                child: _cameraPreview(),
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
              const SoftCard(
                  child: Text(
                      'Kamera menampilkan preview langsung saja. Tidak ada foto/video yang disimpan dan Gestura belum dapat menilai ketepatan gerakan.')),
              if (saveError != null) ...[
                const SizedBox(height: 10),
                Text(saveError!, style: const TextStyle(color: Colors.red)),
              ],
              if (cameraError == null && !initializing) ...[
                const SizedBox(height: 16),
                PrimaryButton(
                  saving ? 'Menyimpan sesi…' : 'Selesaikan sesi latihan',
                  onPressed:
                      saving || elapsedSeconds < 1 ? null : _finishPractice,
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
}
