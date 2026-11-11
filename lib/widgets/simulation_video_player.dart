import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../core/gestura_theme.dart';
import '../data/gesture_api_service.dart';

class SimulationVideoPlayer extends StatefulWidget {
  const SimulationVideoPlayer({
    required this.category,
    required this.target,
    super.key,
  });

  final GestureCategory category;
  final String target;

  @override
  State<SimulationVideoPlayer> createState() => _SimulationVideoPlayerState();
}

class _SimulationVideoPlayerState extends State<SimulationVideoPlayer> {
  late final TextEditingController _baseUrlController;
  VideoPlayerController? _videoController;
  String? _error;
  bool _loading = false;
  int _loadRequestId = 0;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(
      text: GestureApiService.configuredBaseUrl,
    );
    _loadVideo();
  }

  @override
  void didUpdateWidget(covariant SimulationVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.category != widget.category ||
        oldWidget.target != widget.target) {
      _loadVideo();
    }
  }

  Future<void> _loadVideo() async {
    final requestId = ++_loadRequestId;
    final previousController = _videoController;
    _videoController = null;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    await previousController?.dispose();

    final baseUrl = _baseUrlController.text.trim();
    GestureApiService.configuredBaseUrl = baseUrl;
    VideoPlayerController? controller;
    try {
      final uri = GestureApiService.simulationVideoUri(
        baseUrl: baseUrl,
        category: widget.category,
        target: widget.target,
      );
      controller = VideoPlayerController.networkUrl(uri);
      _videoController = controller;
      await controller.initialize();
      await controller.setLooping(true);
      if (!mounted || requestId != _loadRequestId) {
        await controller.dispose();
        return;
      }
      setState(() => _loading = false);
    } on FormatException catch (error) {
      await _showLoadError(requestId, controller, error.message);
    } on PlatformException catch (error) {
      await _showLoadError(
        requestId,
        controller,
        error.message ?? error.code,
      );
    } on Object catch (error) {
      await _showLoadError(requestId, controller, error.toString());
    }
  }

  Future<void> _showLoadError(
    int requestId,
    VideoPlayerController? controller,
    String message,
  ) async {
    await controller?.dispose();
    if (!mounted || requestId != _loadRequestId) return;
    _videoController = null;
    setState(() {
      _loading = false;
      _error = message;
    });
  }

  Future<void> _togglePlayback(VideoPlayerController controller) async {
    try {
      final value = controller.value;
      if (value.isPlaying) {
        await controller.pause();
      } else {
        if (value.position >= value.duration) {
          await controller.seekTo(Duration.zero);
        }
        await controller.play();
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _error = error.message ?? error.code);
      }
    }
  }

  @override
  void dispose() {
    _loadRequestId++;
    _baseUrlController.dispose();
    final controller = _videoController;
    if (controller != null) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _baseUrlController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            onChanged: (value) =>
                GestureApiService.configuredBaseUrl = value.trim(),
            onSubmitted: (_) => _loadVideo(),
            decoration: InputDecoration(
              labelText: 'Alamat backend video',
              hintText: 'http://192.168.1.5:8000',
              suffixIcon: IconButton(
                tooltip: 'Muat ulang video',
                onPressed: _loading ? null : _loadVideo,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Container(
              height: 330,
              width: double.infinity,
              color: Colors.black,
              child: _videoContent(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${widget.category.displayName} • ${widget.target}',
            style: const TextStyle(
              color: GesturaTheme.muted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );

  Widget _videoContent() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: GesturaTheme.yellow),
      );
    }
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.play_circle_outline_rounded,
                color: Colors.white70,
                size: 52,
              ),
              const SizedBox(height: 10),
              Text(
                _error == null
                    ? 'Video simulasi belum dapat dimuat.'
                    : 'Video tidak dapat dimuat. Pastikan backend aktif dan alamat IP laptop benar.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _loadVideo,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      );
    }

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final ended = value.duration.inMilliseconds > 0 &&
            value.position >= value.duration;
        final icon = value.isPlaying
            ? Icons.pause_rounded
            : ended
                ? Icons.replay_rounded
                : Icons.play_arrow_rounded;
        return Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
            if (value.isBuffering)
              const CircularProgressIndicator(color: GesturaTheme.yellow),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: GesturaTheme.yellow,
                  bufferedColor: Colors.white54,
                  backgroundColor: Colors.white24,
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
            IconButton.filled(
              onPressed: () => _togglePlayback(controller),
              iconSize: 38,
              style: IconButton.styleFrom(
                backgroundColor: GesturaTheme.tealDark.withValues(alpha: .8),
                foregroundColor: Colors.white,
              ),
              icon: Icon(icon),
            ),
          ],
        );
      },
    );
  }
}
