/// Persistent ring-buffer logger for app-level events (BT, trip lifecycle,
/// HTTP send, motion changes, settings toggles).
///
/// Lives next to Tracelet's own SDK log; the Status screen merges both.
/// Backed by `SharedPreferences` so logs survive app restarts. Capped at
/// `_maxEntries` to keep storage bounded.
library;

import 'dart:async';
import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';

class AppLogger {
  static const _key = 'app_log';
  static const _maxEntries = 500;

  static final List<String> _buffer = <String>[];
  static bool _loaded = false;
  static Future<void>? _persistInFlight;

  static Future<void> _load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_key);
    if (stored != null) {
      _buffer
        ..clear()
        ..addAll(stored);
    }
    _loaded = true;
  }

  static Future<void> log(String message, {String level = 'INFO'}) async {
    final entry = '[${DateTime.now().toIso8601String()}] [$level] $message';
    developer.log(entry);
    await _load();
    _buffer.add(entry);
    while (_buffer.length > _maxEntries) {
      _buffer.removeAt(0);
    }
    _persistInFlight ??= _persist().whenComplete(() => _persistInFlight = null);
  }

  static Future<void> info(String message) => log(message, level: 'INFO');
  static Future<void> warn(String message) => log(message, level: 'WARN');
  static Future<void> error(String message) => log(message, level: 'ERROR');

  static Future<String> read() async {
    await _load();
    return _buffer.reversed.join('\n');
  }

  static Future<void> clear() async {
    _buffer.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, List<String>.from(_buffer));
  }
}
