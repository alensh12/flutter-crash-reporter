import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'crash_reporter_config.dart';

/// Central crash reporter for Flutter-on-Tizen.
///
/// Usage:
/// ```dart
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await CrashReporter.init(
///     config: CrashReporterConfig(
///       endpoint: 'https://your-app.vercel.app/crashes',
///       apiKey: 'your-secret-key',
///       appId: 'com.example.tvapp',
///       appVersion: '1.0.0',
///       deviceType: TizenDeviceType.tv,
///     ),
///   );
///   CrashReporter.installGlobalHandlers();
///   runApp(const MyApp());
/// }
/// ```
class CrashReporter {
  CrashReporter._();

  static CrashReporterConfig? _config;
  static SharedPreferences? _prefs;
  static final List<String> _breadcrumbs = [];
  static final _sessionId = const Uuid().v4();
  static final _sessionStartedAt = DateTime.now().toUtc();
  static bool _initialized = false;
  static bool _flushInProgress = false;

  static const _queueKey = 'tizen_crash_reporter_queue_v1';

  static Future<void> init({required CrashReporterConfig config}) async {
    _config = config;
    _prefs = await SharedPreferences.getInstance();
    _initialized = true;
    await flushQueue();
  }

  static void installGlobalHandlers() {
    _assertInitialized();

    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      unawaited(
        report(
          message: details.exceptionAsString(),
          stackTrace: details.stack?.toString(),
          errorType: 'FlutterError',
          fatal: true,
        ),
      );
      previousFlutterHandler?.call(details);
    };

    final previousPlatformHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(
        report(
          message: error.toString(),
          stackTrace: stack.toString(),
          errorType: error.runtimeType.toString(),
          fatal: true,
        ),
      );
      if (previousPlatformHandler != null) {
        return previousPlatformHandler(error, stack);
      }
      return true;
    };
  }

  static Future<T> runGuarded<T>(FutureOr<T> Function() appRunner) async {
    _assertInitialized();

    return runZonedGuarded(
      () async => appRunner(),
      (error, stack) {
        unawaited(
          report(
            message: error.toString(),
            stackTrace: stack.toString(),
            errorType: error.runtimeType.toString(),
            fatal: true,
          ),
        );
      },
    );
  }

  static void addBreadcrumb(String message) {
    _breadcrumbs.add(message);
    if (_breadcrumbs.length > 50) {
      _breadcrumbs.removeAt(0);
    }
  }

  static Future<void> report({
    required String message,
    String? stackTrace,
    String errorType = 'UnknownError',
    bool fatal = true,
    Map<String, String>? customKeys,
  }) async {
    _assertInitialized();

    final payload = _buildPayload(
      message: message,
      stackTrace: stackTrace,
      errorType: errorType,
      fatal: fatal,
      customKeys: customKeys,
    );

    debugPrint('[CrashReporter] $errorType: $message');

    final delivered = await _sendPayload(payload);
    if (!delivered) {
      await _enqueuePayload(payload);
    }
  }

  static Future<void> flushQueue() async {
    _assertInitialized();
    if (_flushInProgress) {
      return;
    }

    _flushInProgress = true;
    try {
      final queue = _readQueue();
      if (queue.isEmpty) {
        return;
      }

      final remaining = <Map<String, dynamic>>[];
      for (final item in queue) {
        final delivered = await _sendPayload(item, fromQueue: true);
        if (!delivered) {
          remaining.add(item);
        }
      }

      await _writeQueue(remaining);
    } finally {
      _flushInProgress = false;
    }
  }

  static Map<String, dynamic> _buildPayload({
    required String message,
    String? stackTrace,
    required String errorType,
    required bool fatal,
    Map<String, String>? customKeys,
  }) {
    final config = _config!;

    return {
      'platform': 'tizen',
      'deviceType': config.deviceType.value,
      'deviceModel': config.deviceModel,
      'tizenVersion': config.tizenVersion,
      'appId': config.appId,
      'appVersion': config.appVersion,
      'buildNumber': config.buildNumber,
      'fatal': fatal,
      'errorType': errorType,
      'message': message,
      'stackTrace': stackTrace,
      'breadcrumbs': List<String>.from(_breadcrumbs),
      'sessionId': _sessionId,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'customKeys': {
        'sessionAgeSeconds':
            DateTime.now().toUtc().difference(_sessionStartedAt).inSeconds.toString(),
        if (config.userEmail != null) 'userEmail': config.userEmail!,
        if (config.userName != null) 'userName': config.userName!,
        ...?customKeys,
      },
      if (config.userId != null) 'userId': config.userId,
    };
  }

  static Future<bool> _sendPayload(
    Map<String, dynamic> payload, {
    bool fromQueue = false,
  }) async {
    final config = _config!;
    final maxAttempts = fromQueue ? 1 : config.maxRetries;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await http
            .post(
              Uri.parse(config.endpoint),
              headers: {
                'Content-Type': 'application/json',
                'X-Api-Key': config.apiKey,
              },
              body: jsonEncode(payload),
            )
            .timeout(config.timeout);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          return true;
        }

        debugPrint(
          '[CrashReporter] Upload failed (${response.statusCode}): ${response.body}',
        );
      } catch (error) {
        debugPrint('[CrashReporter] Upload error on attempt $attempt: $error');
      }

      if (attempt < maxAttempts) {
        await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
      }
    }

    return false;
  }

  static Future<void> _enqueuePayload(Map<String, dynamic> payload) async {
    final queue = _readQueue()..add(payload);
    final maxSize = _config!.maxQueueSize;

    while (queue.length > maxSize) {
      queue.removeAt(0);
    }

    await _writeQueue(queue);
  }

  static List<Map<String, dynamic>> _readQueue() {
    final raw = _prefs?.getString(_queueKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return [];
      }

      return decoded
          .whereType<Map>()
          .map((item) => item.map((key, value) => MapEntry('$key', value)))
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _writeQueue(List<Map<String, dynamic>> queue) async {
    await _prefs?.setString(_queueKey, jsonEncode(queue));
  }

  static void _assertInitialized() {
    if (!_initialized || _config == null || _prefs == null) {
      throw StateError('CrashReporter.init() must be called before use.');
    }
  }
}
