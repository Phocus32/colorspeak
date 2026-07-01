import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/color_match.dart';
import '../services/color_detection_service.dart';
import '../services/haptic_service.dart';
import '../services/speech_service.dart';
import '../widgets/scan_overlay.dart';

enum _AppState { initializing, permissionDenied, ready, error }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _detector = ColorDetectionService();
  final _speech = SpeechService();

  CameraController? _controller;
  List<CameraDescription> _cameras = [];

  _AppState _appState = _AppState.initializing;
  ColorMatch? _currentMatch;
  String _statusText = 'Initializing…';
  bool _isStreaming = false;

  String? _lastSpokenColor;
  Timer? _repeatTimer;
  static const Duration _repeatInterval = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _speech.init();
    await HapticService.init();
    await _requestAndStart();
  }

  Future<void> _requestAndStart() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() {
        _appState = _AppState.permissionDenied;
        _statusText = 'Camera permission required.';
      });
      return;
    }
    await _startCamera();
  }

  Future<void> _startCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _appState = _AppState.error;
          _statusText = 'No camera found on this device.';
        });
        return;
      }

      final back = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      _controller = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();

      if (!mounted) return;

      setState(() {
        _appState = _AppState.ready;
        _statusText = 'Scanning…';
      });

      _startStream();
      _startRepeatTimer();
    } catch (e) {
      setState(() {
        _appState = _AppState.error;
        _statusText = 'Camera error: $e';
      });
    }
  }

  void _startStream() {
    if (_isStreaming || _controller == null) return;
    _isStreaming = true;
    _controller!.startImageStream(_onFrame);
  }

  void _stopStream() {
    if (!_isStreaming || _controller == null) return;
    _isStreaming = false;
    _controller!.stopImageStream();
  }

  void _onFrame(CameraImage image) {
    final result = _detector.analyze(image);
    if (result == null) return;

    final isNew = result.match.name != _lastSpokenColor;

    if (mounted) {
      setState(() {
        _currentMatch = result.match;
        _statusText = 'Scanning…';
      });
    }

    if (isNew) {
      _announceColor(result.match.name);
    }
  }

  Future<void> _announceColor(String name) async {
    _lastSpokenColor = name;
    _resetRepeatTimer();
    await HapticService.colorDetected();
    await _speech.speak(name);
  }

  void _startRepeatTimer() {
    _repeatTimer?.cancel();
    _repeatTimer = Timer.periodic(_repeatInterval, (_) {
      if (_lastSpokenColor != null && mounted) {
        _speech.speak(_lastSpokenColor!);
      }
    });
  }

  void _resetRepeatTimer() {
    _repeatTimer?.cancel();
    _startRepeatTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      _stopStream();
    } else if (state == AppLifecycleState.resumed) {
      _startStream();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _repeatTimer?.cancel();
    _stopStream();
    _controller?.dispose();
    _speech.dispose();
    super.dispose();
  }

  Future<void> _onSpeakAgain() async {
    await HapticService.buttonTap();
    if (_lastSpokenColor != null) {
      await _speech.speak(_lastSpokenColor!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: switch (_appState) {
          _AppState.initializing => _buildLoading(),
          _AppState.permissionDenied => _buildPermissionError(),
          _AppState.error => _buildGenericError(),
          _AppState.ready => _buildMain(),
        },
      ),
    );
  }

  Widget _buildMain() {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return _buildLoading();

    final detectedColor =
        _currentMatch?.displayColor ?? const Color(0xFF2A2A2A);
    final textOnDetected = ColorDatabase.contrastTextColor(detectedColor);

    return Stack(
      fit: StackFit.expand,
      children: [
        _CameraView(controller: ctrl),
        ScanOverlay(ringColor: detectedColor, isScanning: _isStreaming),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _TopBar(),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _BottomPanel(
            currentMatch: _currentMatch,
            detectedColor: detectedColor,
            textOnDetected: textOnDetected,
            statusText: _statusText,
            onSpeakAgain: _onSpeakAgain,
          ),
        ),
      ],
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 20),
          Text('Starting camera…',
              style: TextStyle(color: Colors.white70, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildPermissionError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt_outlined,
                color: Colors.white54, size: 64),
            const SizedBox(height: 24),
            const Text(
              'Camera Access Required',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'ColorSpeak needs camera access to detect colors.',
              style:
                  TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            _ActionButton(
              label: 'Open Settings',
              icon: Icons.settings_outlined,
              onTap: () => openAppSettings(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenericError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 64),
            const SizedBox(height: 24),
            Text(
              _statusText,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 16, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            _ActionButton(
              label: 'Retry',
              icon: Icons.refresh,
              onTap: () {
                setState(() => _appState = _AppState.initializing);
                _startCamera();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraView extends StatelessWidget {
  final CameraController controller;
  const _CameraView({required this.controller});

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) return const SizedBox.expand();

    return LayoutBuilder(builder: (context, constraints) {
      final screenW = constraints.maxWidth;
      final screenH = constraints.maxHeight;

      final camW = previewSize.height;
      final camH = previewSize.width;
      final camAspect = camW / camH;
      final screenAspect = screenW / screenH;

      double scaleW, scaleH;
      if (camAspect > screenAspect) {
        scaleH = screenH;
        scaleW = screenH * camAspect;
      } else {
        scaleW = screenW;
        scaleH = screenW / camAspect;
      }

      return OverflowBox(
        maxWidth: scaleW,
        maxHeight: scaleH,
        child: CameraPreview(controller),
      );
    });
  }
}

class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withOpacity(0.85), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24, width: 1.5),
            ),
            child: const Icon(Icons.colorize, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          const Text(
            'ColorSpeak',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  final ColorMatch? currentMatch;
  final Color detectedColor;
  final Color textOnDetected;
  final String statusText;
  final VoidCallback onSpeakAgain;

  const _BottomPanel({
    required this.currentMatch,
    required this.detectedColor,
    required this.textOnDetected,
    required this.statusText,
    required this.onSpeakAgain,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withOpacity(0.95), Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ColorCard(
            match: currentMatch,
            detectedColor: detectedColor,
            textOnDetected: textOnDetected,
          ),
          const SizedBox(height: 16),
          _ActionButton(
            label: 'Speak Again',
            icon: Icons.volume_up_rounded,
            onTap: onSpeakAgain,
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PulsingDot(),
              const SizedBox(width: 8),
              Text(
                statusText,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ColorCard extends StatelessWidget {
  final ColorMatch? match;
  final Color detectedColor;
  final Color textOnDetected;

  const _ColorCard({
    required this.match,
    required this.detectedColor,
    required this.textOnDetected,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      height: 90,
      decoration: BoxDecoration(
        color: match != null ? detectedColor : const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(match != null ? 0.12 : 0.08),
          width: 1,
        ),
        boxShadow: [
          if (match != null)
            BoxShadow(
              color: detectedColor.withOpacity(0.4),
              blurRadius: 20,
              spreadRadius: 2,
            ),
        ],
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DETECTED',
                  style: TextStyle(
                    color: match != null
                        ? textOnDetected.withOpacity(0.6)
                        : Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.8,
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: Text(
                    match?.name.toUpperCase() ?? '—',
                    key: ValueKey(match?.name),
                    style: TextStyle(
                      color: match != null ? textOnDetected : Colors.white24,
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      height: 1.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: match != null
                    ? textOnDetected.withOpacity(0.15)
                    : Colors.white10,
                border: Border.all(
                  color: match != null
                      ? textOnDetected.withOpacity(0.4)
                      : Colors.white12,
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.circle,
                color: match != null
                    ? textOnDetected.withOpacity(0.7)
                    : Colors.white24,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 22),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl),
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF4CD964),
        ),
      ),
    );
  }
}
