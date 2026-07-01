import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/color_match.dart';
import '../services/color_detection_service.dart';
import '../services/haptic_service.dart';
import '../services/sensor_service.dart';
import '../services/speech_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  DetectionResult? _lastResult;
  bool _isProcessing = false;
  bool _isInitialized = false;
  bool _cameraReady = false;
  String _statusText = 'Initializing…';

  final ColorDetectionService _colorService = ColorDetectionService();
  final SpeechService _speechService = SpeechService();
  final SensorService _sensorService = SensorService();
  Timer? _speakTimer;
  String? _lastSpokenColor;

  bool _torchOn = false;
  bool _autoFlash = true;
  LightCondition _lightCondition = LightCondition.normal;
  StreamSubscription<bool>? _shakeSub;
  StreamSubscription<LightCondition>? _lightSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _speakTimer?.cancel();
    _shakeSub?.cancel();
    _lightSub?.cancel();
    _sensorService.dispose();
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _speechService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactiveResume) return;
    if (!_cameraReady || _cameraController == null || !_cameraController!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _cameraController?.stopImageStream();
    } else if (state == AppLifecycleState.resumed) {
      _startImageStream();
    }
  }

  Future<void> _init() async {
    await _speechService.init();
    await HapticService.init();
    _sensorService.startMonitoring();
    _shakeSub = _sensorService.onShake.listen((_) => _onShake());
    _lightSub = _sensorService.onLightChange.listen(_onLightChange);

    final camStatus = await Permission.camera.request();
    if (camStatus != PermissionStatus.granted) {
      setState(() => _statusText = 'Camera permission denied');
      return;
    }

    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() => _statusText = 'No camera found');
        return;
      }

      await _initCamera();
      setState(() => _isInitialized = true);
    } catch (e) {
      setState(() => _statusText = 'Camera error: $e');
    }
  }

  Future<void> _initCamera() async {
    final cam = _cameras!.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras!.first,
    );

    _cameraController = CameraController(
      cam,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    await _cameraController!.initialize();
    _cameraReady = true;

    if (!mounted) return;
    setState(() => _statusText = 'Point at a color');
    _startImageStream();
  }

  void _startImageStream() {
    if (_cameraController == null || !_cameraController!.value.isStreamingImages) {
      _cameraController?.startImageStream(_onImage);
    }
  }

  void _onImage(CameraImage image) {
    if (_isProcessing) return;
    _isProcessing = true;

    final result = _colorService.analyze(image);
    if (result != null) {
      _lastResult = result;
      _sensorService.updateLightFromFrame(
        avgR: result.avgR,
        avgG: result.avgG,
        avgB: result.avgB,
      );
      _onColorDetected(result);

      if (_autoFlash && _lightCondition == LightCondition.dark && !_torchOn) {
        _setTorch(true);
      }
    }

    _isProcessing = false;
  }

  void _onColorDetected(DetectionResult result) {
    final name = result.match.name;
    if (name == _lastSpokenColor) return;
    _lastSpokenColor = name;

    _speakTimer?.cancel();
    _speakTimer = Timer(const Duration(milliseconds: 300), () {
      _speechService.speak(name);
      HapticService.colorDetected();
    });

    setState(() {
      _statusText = name;
    });
  }

  void _onShake() {
    _lastSpokenColor = null;
    HapticService.buttonTap();
    _speechService.speak('Rescanning');
    setState(() {
      _statusText = 'Shake detected – rescanning';
    });
  }

  void _onLightChange(LightCondition condition) {
    setState(() {
      _lightCondition = condition;
    });
  }

  Future<void> _toggleTorch() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    _setTorch(!_torchOn);
  }

  Future<void> _setTorch(bool on) async {
    try {
      await _cameraController!.setFlashMode(on ? FlashMode.torch : FlashMode.off);
      setState(() => _torchOn = on);
    } catch (e) {
      debugPrint('Torch error: $e');
    }
  }

  IconData _lightIcon() {
    switch (_lightCondition) {
      case LightCondition.bright: return Icons.wb_sunny;
      case LightCondition.dim: return Icons.wb_cloudy;
      case LightCondition.dark: return Icons.nights_stay;
      case LightCondition.normal: return Icons.light_mode;
    }
  }

  Color _lightColor() {
    switch (_lightCondition) {
      case LightCondition.bright: return Colors.amber;
      case LightCondition.dim: return Colors.orange;
      case LightCondition.dark: return const Color(0xFF5C6BC0);
      case LightCondition.normal: return Colors.green;
    }
  }

  String _lightLabel() {
    switch (_lightCondition) {
      case LightCondition.bright: return 'Bright';
      case LightCondition.dim: return 'Dim';
      case LightCondition.dark: return 'Dark';
      case LightCondition.normal: return 'Normal';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized && _statusText != 'Camera permission denied') {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_statusText == 'Camera permission denied') {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(_statusText, style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => openAppSettings(),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          if (_cameraReady && _cameraController != null && _cameraController!.value.isInitialized)
            CameraPreview(_cameraController!)
          else
            const Center(child: CircularProgressIndicator()),
          Positioned(
            left: 0,
            right: 0,
            bottom: 80,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                decoration: BoxDecoration(
                  color: _lastResult != null
                      ? _lastResult!.match.displayColor.withValues(alpha: 0.9)
                      : Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _statusText,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: _lastResult != null
                        ? ColorDatabase.contrastTextColor(
                            _lastResult!.match.displayColor)
                        : Colors.white,
                  ),
                ),
              ),
            ),
          ),
          if (_lastResult != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _colorChip('R', _lastResult!.avgR, Colors.red),
                    _colorChip('G', _lastResult!.avgG, Colors.green),
                    _colorChip('B', _lastResult!.avgB, Colors.blue),
                  ],
                ),
              ),
            ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sensorBadge(
                  icon: _lightIcon(),
                  color: _lightColor(),
                  label: _lightLabel(),
                ),
                const SizedBox(height: 8),
                _sensorBadge(
                  icon: Icons.shake,
                  color: Colors.cyanAccent,
                  label: 'Shake to rescan',
                  small: true,
                ),
              ],
            ),
          ),
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _controlButton(
                  icon: _torchOn ? Icons.flash_on : Icons.flash_off,
                  label: _torchOn ? 'Flash On' : 'Flash Off',
                  active: _torchOn,
                  onTap: _toggleTorch,
                ),
                const SizedBox(width: 16),
                _controlButton(
                  icon: _autoFlash ? Icons.flash_auto : Icons.flashlight_on,
                  label: _autoFlash ? 'Auto' : 'Manual',
                  active: _autoFlash,
                  onTap: () {
                    setState(() => _autoFlash = !_autoFlash);
                    HapticService.buttonTap();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.white24,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: active ? Colors.black : Colors.white70),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.black : Colors.white70,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sensorBadge({
    required IconData icon,
    required Color color,
    required String label,
    bool small = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 8 : 10, vertical: small ? 4 : 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: small ? 14 : 16, color: color),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: Colors.white70,
                fontSize: small ? 11 : 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _colorChip(String label, int value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label ', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
          Text('$value', style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}
