import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

class HapticService {
  static bool? _hasVibrator;

  static Future<void> init() async {
    _hasVibrator = await Vibration.hasVibrator();
  }

  static Future<void> colorDetected() async {
    if (_hasVibrator == true) {
      await Vibration.vibrate(
        pattern: [0, 60, 80, 60],
        intensities: [0, 200, 0, 150],
      );
    } else {
      await HapticFeedback.mediumImpact();
    }
  }

  static Future<void> buttonTap() async {
    await HapticFeedback.selectionClick();
  }
}
