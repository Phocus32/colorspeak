import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class SpeechService {
  late final FlutterTts _tts;
  bool _initialized = false;

  Future<void> init() async {
    try {
      _tts = FlutterTts();
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.45);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      _initialized = true;
    } catch (e) {
      debugPrint('SpeechService init error: $e');
    }
  }

  Future<void> speak(String text) async {
    if (!_initialized) return;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('SpeechService speak error: $e');
    }
  }

  Future<void> stop() async {
    if (!_initialized) return;
    try {
      await _tts.stop();
    } catch (e) {
      debugPrint('SpeechService stop error: $e');
    }
  }

  Future<void> dispose() async {
    if (!_initialized) return;
    try {
      await _tts.stop();
    } catch (e) {
      debugPrint('SpeechService dispose error: $e');
    }
  }
}
