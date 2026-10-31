// App-wide crash/error logger for GAnime.
// Writes timestamped, sanitized entries to ganime_debug.log in the app's
// documents directory. Captures Flutter framework errors and uncaught
// async errors globally, and offers AppLogger().log() for manual events.
//
// SECURITY: every message passes through _sanitize() before it is written.
// Tokens, API keys, client secrets, debrid keys, passwords and
// Authorization headers are redacted. Never log full stream URLs — log
// domain + quality only.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class AppLogger {
  static final AppLogger _instance = AppLogger._internal();
  factory AppLogger() => _instance;
  AppLogger._internal();

  static const String _fileName = 'ganime_debug.log';
  static const int _maxBytes = 1024 * 1024; // 1 MB rotation cap

  File? _file;
  bool _ready = false;
  final List<String> _pending = [];
  bool _handlersInstalled = false;

  /// Install global error handlers immediately (synchronous) and kick off
  /// async log-file setup. Safe to call more than once.
  void init() {
    if (!_handlersInstalled) {
      _handlersInstalled = true;
      final prevFlutterOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        _write('FLUTTER-ERROR', _describe(details));
        prevFlutterOnError?.call(details);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        _write('UNCAUGHT', '${_short(error)}\n${_short(stack)}');
        return true; // handled: suppress the red-screen crash dialog
      };
    }
    unawaited(_setupFile());
  }

  Future<void> _setupFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/$_fileName');
      if (!await _file!.exists()) {
        await _file!.create(recursive: true);
      }
      _ready = true;
      _write('LOGGER', 'Log started (${await _sizeLabel()})');
      for (final p in _pending) {
        await _append(p);
      }
      _pending.clear();
    } catch (_) {
      // Logging must never crash the app.
    }
  }

  /// Manual log entry: [tag] like 'PLAYER', 'TRACKER', 'NAV', 'SYNC'.
  void log(String tag, String message, [Object? data]) {
    final msg = data == null ? message : '$message | ${_short(data)}';
    _write(tag.toUpperCase(), msg);
  }

  /// Absolute path of the log file (null until the file is ready).
  String? getLogPath() => _file?.path;

  Future<String> _sizeLabel() async {
    try {
      final n = await _file!.length();
      return n < 1024 ? '$n B' : '${(n / 1024).toStringAsFixed(1)} KB';
    } catch (_) {
      return '?';
    }
  }

  /// Human-readable size for the Settings UI.
  Future<String> sizeLabel() async {
    if (!_ready || _file == null) return '—';
    return _sizeLabel();
  }

  /// Last [n] lines of the log (for preview in Settings).
  Future<List<String>> tail(int n) async {
    try {
      if (!_ready || _file == null) return const [];
      final lines = await _file!.readAsLines();
      return lines.length <= n ? lines : lines.sublist(lines.length - n);
    } catch (_) {
      return const [];
    }
  }

  /// Full log text (for the View dialog).
  Future<String> readAll() async {
    try {
      if (!_ready || _file == null) return '(log not ready yet)';
      final text = await _file!.readAsString();
      return text.isEmpty ? '(log is empty)' : text;
    } catch (e) {
      return '(could not read log: $e)';
    }
  }

  /// Wipe the log file (with a fresh "cleared" marker entry).
  Future<void> clear() async {
    try {
      if (_file != null && await _file!.exists()) {
        await _file!.writeAsString('');
      }
      _write('LOGGER', 'Log cleared by user');
    } catch (_) {}
  }

  // ---------- internals ----------

  void _write(String tag, String rawMessage) {
    final line =
        '[${DateTime.now().toIso8601String()}] [$tag] ${_sanitize(rawMessage)}';
    if (!_ready || _file == null) {
      _pending.add(line);
      if (_pending.length > 200) _pending.removeAt(0);
      return;
    }
    unawaited(_append(line));
  }

  Future<void> _append(String line) async {
    try {
      await _rotateIfNeeded();
      await _file!.writeAsString('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  /// Keep the file under 1 MB: drop the oldest half when over the cap.
  Future<void> _rotateIfNeeded() async {
    try {
      final len = await _file!.length();
      if (len <= _maxBytes) return;
      final lines = await _file!.readAsLines();
      final keep = lines.sublist((lines.length / 2).floor());
      await _file!.writeAsString('${keep.join('\n')}\n[LOGGER] Log rotated (1MB cap)\n');
    } catch (_) {}
  }

  String _short(Object? o) {
    final s = '$o';
    return s.length > 600 ? '${s.substring(0, 600)}…' : s;
  }

  String _describe(FlutterErrorDetails d) {
    final buf = StringBuffer(d.exceptionAsString());
    final ctx = d.context?.toString();
    if (ctx != null && ctx.isNotEmpty && ctx != 'no context') {
      buf.write(' | context: $ctx');
    }
    final lib = d.library;
    if (lib != null && lib.isNotEmpty) buf.write(' | library: $lib');
    return buf.toString();
  }

  // ---------- sanitization ----------

  static final List<RegExp> _keyValuePatterns = [
    // "key": "value" / key=value / key: value for sensitive key names
    RegExp(
        r'''(api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|debrid[_-]?key|password|passwd|authorization|bearer|session[_-]?token|private[_-]?key)\s*["'\s:=]+\s*["']?([^"'\s,};&]+)["']?''',
        caseSensitive: false),
    // Google API keys
    RegExp(r'AIza[0-9A-Za-z_-]{35}'),
    // OpenAI-style keys
    RegExp(r'sk-[a-zA-Z0-9]{20,}'),
    // JWTs (header.payload.signature)
    RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
    // Long hex/base64-ish secrets (32+ chars) after = or :
    RegExp(r'''(?<=[=:])\s*["']?[A-Za-z0-9_\-+/]{32,}={0,2}["']?'''),
  ];

  /// Redact sensitive values, keep the key names so the log stays readable.
  String _sanitize(String input) {
    var out = input;
    // Named key=value pairs: keep the key, redact the value.
    out = out.replaceAllMapped(_keyValuePatterns[0], (m) {
      final key = m.group(1);
      return '$key=[REDACTED]';
    });
    for (var i = 1; i < _keyValuePatterns.length; i++) {
      out = out.replaceAll(_keyValuePatterns[i], '[REDACTED]');
    }
    return out;
  }

  /// Extract just the host (+ optional quality label) from a stream URL.
  /// Never logs the full URL — it may carry tokens.
  static String urlLabel(String url, [String? quality]) {
    try {
      final host = Uri.parse(url).host;
      final h = host.isEmpty ? 'unknown-host' : host;
      return quality == null || quality.isEmpty ? h : '$h ($quality)';
    } catch (_) {
      return 'invalid-url';
    }
  }
}
