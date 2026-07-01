import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../models/color_match.dart';

class DetectionResult {
  final ColorMatch match;
  final int avgR;
  final int avgG;
  final int avgB;

  const DetectionResult({
    required this.match,
    required this.avgR,
    required this.avgG,
    required this.avgB,
  });
}

class ColorDetectionService {
  static const int _sampleSize = 60;
  static const Duration _throttle = Duration(milliseconds: 400);

  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);

  DetectionResult? analyze(CameraImage image) {
    final now = DateTime.now();
    if (now.difference(_lastProcessed) < _throttle) return null;
    _lastProcessed = now;

    try {
      final format = image.format.group;
      if (format == ImageFormatGroup.yuv420) return _processYUV420(image);
      if (format == ImageFormatGroup.bgra8888) return _processBGRA(image);
      if (format == ImageFormatGroup.nv21) return _processNV21(image);
    } catch (e) {
      debugPrint('ColorDetectionService error: $e');
    }
    return null;
  }

  DetectionResult _processYUV420(CameraImage image) {
    final w = image.width;
    final h = image.height;
    final cx = w ~/ 2;
    final cy = h ~/ 2;
    final half = _sampleSize ~/ 2;

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    int totalR = 0, totalG = 0, totalB = 0, count = 0;

    for (int dy = -half; dy < half; dy += 2) {
      for (int dx = -half; dx < half; dx += 2) {
        final px = cx + dx;
        final py = cy + dy;
        if (px < 0 || py < 0 || px >= w || py >= h) continue;

        final yIdx = py * yPlane.bytesPerRow + px;
        if (yIdx >= yPlane.bytes.length) continue;

        final uvRow = py ~/ 2;
        final uvCol = px ~/ 2;
        final uBPP = uPlane.bytesPerPixel ?? 1;
        final vBPP = vPlane.bytesPerPixel ?? 1;
        final uIdx = uvRow * uPlane.bytesPerRow + uvCol * uBPP;
        final vIdx = uvRow * vPlane.bytesPerRow + uvCol * vBPP;

        if (uIdx >= uPlane.bytes.length || vIdx >= vPlane.bytes.length) continue;

        final yVal = yPlane.bytes[yIdx] & 0xFF;
        final uVal = (uPlane.bytes[uIdx] & 0xFF) - 128;
        final vVal = (vPlane.bytes[vIdx] & 0xFF) - 128;

        final r = (yVal + 1.370705 * vVal).round().clamp(0, 255);
        final g = (yVal - 0.337633 * uVal - 0.698001 * vVal).round().clamp(0, 255);
        final b = (yVal + 1.732446 * uVal).round().clamp(0, 255);

        totalR += r;
        totalG += g;
        totalB += b;
        count++;
      }
    }

    return _buildResult(totalR, totalG, totalB, count);
  }

  DetectionResult _processNV21(CameraImage image) {
    final w = image.width;
    final h = image.height;
    final cx = w ~/ 2;
    final cy = h ~/ 2;
    final half = _sampleSize ~/ 2;

    final yPlane = image.planes[0];
    final vuPlane = image.planes[1];

    int totalR = 0, totalG = 0, totalB = 0, count = 0;

    for (int dy = -half; dy < half; dy += 2) {
      for (int dx = -half; dx < half; dx += 2) {
        final px = cx + dx;
        final py = cy + dy;
        if (px < 0 || py < 0 || px >= w || py >= h) continue;

        final yIdx = py * yPlane.bytesPerRow + px;
        if (yIdx >= yPlane.bytes.length) continue;

        final uvRow = py ~/ 2;
        final uvCol = (px ~/ 2) * 2;
        final uvIdx = uvRow * vuPlane.bytesPerRow + uvCol;
        if (uvIdx + 1 >= vuPlane.bytes.length) continue;

        final yVal = yPlane.bytes[yIdx] & 0xFF;
        final vVal = (vuPlane.bytes[uvIdx] & 0xFF) - 128;
        final uVal = (vuPlane.bytes[uvIdx + 1] & 0xFF) - 128;

        final r = (yVal + 1.370705 * vVal).round().clamp(0, 255);
        final g = (yVal - 0.337633 * uVal - 0.698001 * vVal).round().clamp(0, 255);
        final b = (yVal + 1.732446 * uVal).round().clamp(0, 255);

        totalR += r;
        totalG += g;
        totalB += b;
        count++;
      }
    }

    return _buildResult(totalR, totalG, totalB, count);
  }

  DetectionResult _processBGRA(CameraImage image) {
    final w = image.width;
    final h = image.height;
    final cx = w ~/ 2;
    final cy = h ~/ 2;
    final half = _sampleSize ~/ 2;

    final plane = image.planes[0];
    int totalR = 0, totalG = 0, totalB = 0, count = 0;

    for (int dy = -half; dy < half; dy++) {
      for (int dx = -half; dx < half; dx++) {
        final px = cx + dx;
        final py = cy + dy;
        if (px < 0 || py < 0 || px >= w || py >= h) continue;

        final idx = py * plane.bytesPerRow + px * 4;
        if (idx + 3 >= plane.bytes.length) continue;

        totalB += plane.bytes[idx] & 0xFF;
        totalG += plane.bytes[idx + 1] & 0xFF;
        totalR += plane.bytes[idx + 2] & 0xFF;
        count++;
      }
    }

    return _buildResult(totalR, totalG, totalB, count);
  }

  DetectionResult _buildResult(int totalR, int totalG, int totalB, int count) {
    if (count == 0) {
      return DetectionResult(
        match: ColorDatabase.colors.firstWhere((c) => c.name == 'Gray'),
        avgR: 128,
        avgG: 128,
        avgB: 128,
      );
    }

    final avgR = totalR ~/ count;
    final avgG = totalG ~/ count;
    final avgB = totalB ~/ count;
    final match = ColorDatabase.findNearest(avgR, avgG, avgB);

    return DetectionResult(match: match, avgR: avgR, avgG: avgG, avgB: avgB);
  }
}
