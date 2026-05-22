import 'package:flutter/services.dart';

class TorService {
  static const _channel = MethodChannel('com.xunkal1.xuncode/tor');
  static bool _running = false;

  static bool get isRunning => _running;

  static Future<void> start() async {
    try {
      await _channel.invokeMethod('startTor');
      _running = true;
    } catch (_) {
      _running = false;
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stopTor');
    } finally {
      _running = false;
    }
  }

  static Future<bool> checkStatus() async {
    try {
      _running = await _channel.invokeMethod('isRunning') ?? false;
    } catch (_) {
      _running = false;
    }
    return _running;
  }
}
