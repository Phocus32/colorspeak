import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

enum LightCondition { bright, normal, dim, dark }

class SensorService {
  StreamSubscription<AccelerometerEvent>? _accelSub;
  LightCondition _lightCondition = LightCondition.normal;
  bool _isShaking = false;
  bool _monitoring = false;

  final _shakeController = StreamController<bool>.broadcast();
  final _lightController = StreamController<LightCondition>.broadcast();

  Stream<bool> get onShake => _shakeController.stream;
  Stream<LightCondition> get onLightChange => _lightController.stream;
  LightCondition get currentLight => _lightCondition;

  static const double _shakeThreshold = 20.0;
  static const int _shakeMinCount = 3;
  static const Duration _shakeWindow = Duration(milliseconds: 600);

  DateTime _lastShakeCheck = DateTime.now();
  int _shakeCount = 0;

  void startMonitoring() {
    if (_monitoring) return;
    _monitoring = true;

    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 100),
    ).listen(_onAccelerometer, onError: (e) {
      debugPrint('SensorService accel error: $e');
    });
  }

  void _onAccelerometer(AccelerometerEvent event) {
    final mag = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    final now = DateTime.now();

    if (mag > _shakeThreshold) {
      if (now.difference(_lastShakeCheck) > _shakeWindow) {
        _shakeCount = 1;
      } else {
        _shakeCount++;
      }
      _lastShakeCheck = now;

      if (_shakeCount >= _shakeMinCount && !_isShaking) {
        _isShaking = true;
        _shakeController.add(true);
        Future.delayed(const Duration(milliseconds: 500), () {
          _isShaking = false;
        });
      }
    }
  }

  void updateLightFromFrame({
    required int avgR,
    required int avgG,
    required int avgB,
  }) {
    final luminance = (0.299 * avgR + 0.587 * avgG + 0.114 * avgB);
    final newCondition = _classifyLight(luminance);
    if (newCondition != _lightCondition) {
      _lightCondition = newCondition;
      _lightController.add(newCondition);
    }
  }

  LightCondition _classifyLight(double lum) {
    if (lum < 30) return LightCondition.dark;
    if (lum < 60) return LightCondition.dim;
    if (lum > 200) return LightCondition.bright;
    return LightCondition.normal;
  }

  void stopMonitoring() {
    _monitoring = false;
    _accelSub?.cancel();
    _accelSub = null;
  }

  void dispose() {
    stopMonitoring();
    _shakeController.close();
    _lightController.close();
  }
}
