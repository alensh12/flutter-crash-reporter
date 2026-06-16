import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'crash_reporter_config.dart';
import 'native_crash_bridge.dart';

/// Central crash reporter for Flutter-on-Tizen.
///
/// Usage:
/// ```dart
/// Future<void> main() async {
///   await CrashReporter.runGuarded(() async {
///     WidgetsFlutterBinding.ensureInitialized();
///     await CrashReporter.init(
///       config: CrashReporterConfig(
///         endpoint: 'https://your-app.vercel.app/crashes',
///         appId: 'com.example.tvapp',
///         appVersion: '1.0.0',
///         deviceType: TizenDeviceType.tv,
///       ),
///     );
///     CrashReporter.installGlobalHandlers();
///     runApp(const MyApp());
///   });
/// }
/// ```
class CrashReporter {
  CrashReporter._();

  static CrashReporterConfig? _config;
  static SharedPreferences? _prefs;
  static NativeCrashBridge? _nativeBridge;
  static final List<String> _breadcrumbs = [];
  static final _sessionId = const Uuid().v4();
  static final _sessionStartedAt = DateTime.now().toUtc();
  static bool _initialized = false;
  static bool _flushInProgress = false;

  static const _queueKey = 'tizen_crash_reporter_queue_v1';

  static Future<void> init({required CrashReporterConfig config}) async {
    _config = config;
    _prefs = await SharedPreferences.getInstance();
    _nativeBridge = NativeCrashBridge(config.nativeCrashChannel);
    _initialized = true;
    debugPrint(
      '[CrashReporter] init: channel=${config.nativeCrashChannel} '
      'enableNativeCrashFlush=${config.enableNativeCrashFlush}',
    );
    await flushQueue();
    if (config.enableNativeCrashFlush) {
      await flushNativeCrashes();
    }
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
          errorSource: 'flutter',
          fatal: false,
        ),
      );
      if (_config!.showFlutterErrorOnScreen) {
        FlutterError.presentError(details);
      }
      previousFlutterHandler?.call(details);
    };

    final previousPlatformHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(
        report(
          message: error.toString(),
          stackTrace: stack.toString(),
          errorType: error.runtimeType.toString(),
          errorSource: 'dart',
          fatal: true,
        ),
      );
      if (previousPlatformHandler != null) {
        return previousPlatformHandler(error, stack);
      }
      return true;
    };
  }

  static Future<T> runGuarded<T>(FutureOr<T> Function() appRunner) {
    final result = runZonedGuarded<Future<T>>(
      () => Future<T>.sync(appRunner),
      (error, stack) {
        if (!_initialized) {
          return;
        }

        unawaited(
          report(
            message: error.toString(),
            stackTrace: stack.toString(),
            errorType: error.runtimeType.toString(),
            errorSource: 'dart',
            fatal: true,
          ),
        );
      },
    );

    if (result == null) {
      throw StateError('Failed to start guarded zone.');
    }
    return result;
  }

  static void addBreadcrumb(String message) {
    _breadcrumbs.add(message);
    if (_breadcrumbs.length > 50) {
      _breadcrumbs.removeAt(0);
    }
  }

  /// Debug-only: ask App.cs to throw an unhandled .NET exception on a worker thread.
  ///
  /// The crash is persisted to disk and uploaded on the next app launch via
  /// [flushNativeCrashes]. The current process may terminate shortly after this call.
  static Future<void> simulateManagedCrashForTesting() async {
    _assertInitialized();
    debugPrint('[CrashReporter] simulateManagedCrashForTesting →');
    await _nativeBridge?.simulateManagedCrash();
    debugPrint('[CrashReporter] simulateManagedCrashForTesting ← done (relaunch app to flush)');
  }

  /// Debug-only: trigger a native SIGSEGV via the host signal handler.
  ///
  /// The process should terminate immediately. Relaunch the app to upload the
  /// pending `native_cpp` crash file via [flushNativeCrashes].
  static Future<void> simulateNativeCppCrashForTesting() async {
    _assertInitialized();
    debugPrint('[CrashReporter] simulateNativeCppCrashForTesting →');
    await _nativeBridge?.simulateNativeCppCrash();
    debugPrint('[CrashReporter] simulateNativeCppCrashForTesting ← process may exit');
  }

  static String? _resolveNativeCrashId(Map<String, dynamic> crash) {
    final id = crash['id']?.toString();
    if (id != null && id.isNotEmpty) {
      return id;
    }

    final nativeCrashId = crash['nativeCrashId']?.toString();
    if (nativeCrashId != null && nativeCrashId.isNotEmpty) {
      return nativeCrashId;
    }

    return null;
  }

  static String? _normalizeNativeTimestamp(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final parsed = DateTime.tryParse(raw);
    if (parsed != null) {
      return parsed.toUtc().toIso8601String();
    }

    final epochSeconds = int.tryParse(raw);
    if (epochSeconds != null) {
      return DateTime.fromMillisecondsSinceEpoch(
        epochSeconds * 1000,
        isUtc: true,
      ).toIso8601String();
    }

    return null;
  }

  static Future<bool> report({
    required String message,
    String? stackTrace,
    String errorType = 'UnknownError',
    String errorSource = 'dart',
    bool fatal = true,
    Map<String, String>? customKeys,
    String? timestamp,
  }) async {
    _assertInitialized();

    final payload = await _buildPayload(
      message: message,
      stackTrace: stackTrace,
      errorType: errorType,
      errorSource: errorSource,
      fatal: fatal,
      customKeys: customKeys,
      timestamp: timestamp,
    );

    debugPrint('[CrashReporter] $errorType ($errorSource): $message');

    final delivered = await _sendPayload(payload);
    if (!delivered) {
      await _enqueuePayload(payload);
    }
    return delivered;
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

  static Future<void> flushNativeCrashes() async {
    _assertInitialized();

    final bridge = _nativeBridge;
    if (bridge == null) {
      debugPrint('[CrashReporter] flushNativeCrashes: skipped (no bridge)');
      return;
    }

    debugPrint('[CrashReporter] flushNativeCrashes: start');
    final pending = await bridge.getPendingNativeCrashes();
    debugPrint('[CrashReporter] flushNativeCrashes: found ${pending.length} pending');
    if (pending.isEmpty) {
      debugPrint('[CrashReporter] flushNativeCrashes: done (nothing to upload)');
      return;
    }

    for (final crash in pending) {
      final id = _resolveNativeCrashId(crash);
      if (id == null || id.isEmpty) {
        debugPrint('[CrashReporter] flushNativeCrashes: skipping crash without id');
        continue;
      }

      final errorSource = crash['errorSource']?.toString() ??
          (crash['signal'] != null ? 'native_cpp' : 'native_managed');

      debugPrint('[CrashReporter] flushNativeCrashes: uploading id=$id');
      final delivered = await report(
        message: crash['message']?.toString() ?? 'Native crash',
        stackTrace: crash['stackTrace']?.toString(),
        errorType: crash['errorType']?.toString() ?? 'NativeCrash',
        errorSource: errorSource,
        fatal: crash['fatal'] != false,
        timestamp: _normalizeNativeTimestamp(crash['timestamp']?.toString()),
        customKeys: {
          'nativeCrashId': id,
          if (crash['signal'] != null) 'signal': crash['signal'].toString(),
        },
      );

      if (delivered) {
        debugPrint('[CrashReporter] flushNativeCrashes: uploaded id=$id, clearing file');
        await bridge.clearPendingNativeCrash(id);
      } else {
        debugPrint('[CrashReporter] flushNativeCrashes: upload failed for id=$id');
      }
    }

    debugPrint('[CrashReporter] flushNativeCrashes: done');
  }

  static Future<Map<String, dynamic>> _buildPayload({
    required String message,
    String? stackTrace,
    required String errorType,
    required String errorSource,
    required bool fatal,
    Map<String, String>? customKeys,
    String? timestamp,
  }) async {
    final config = _config!;
    final metadata = await _resolveMetadata();

    return {
      'platform': 'tizen',
      'deviceType': metadata['deviceType'] ?? config.deviceType.value,
      'deviceModel': metadata['deviceModel'] ?? config.deviceModel,
      'deviceId': metadata['deviceId'] ?? config.deviceId,
      'tizenVersion': metadata['tizenVersion'] ?? config.tizenVersion,
      'appId': metadata['appId'] ?? config.appId,
      'appVersion': metadata['appVersion'] ?? config.appVersion,
      'buildNumber': metadata['buildNumber'] ?? config.buildNumber,
      'fatal': fatal,
      'errorType': errorType,
      'errorSource': errorSource,
      'message': message,
      'stackTrace': stackTrace,
      'breadcrumbs': List<String>.from(_breadcrumbs),
      'sessionId': _sessionId,
      'timestamp': timestamp ?? DateTime.now().toUtc().toIso8601String(),
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

  static Future<Map<String, String>> _resolveMetadata() async {
    final provider = _config?.metadataProvider;
    if (provider == null) {
      return {};
    }

    try {
      return await provider();
    } catch (error) {
      debugPrint('[CrashReporter] metadataProvider failed: $error');
      return {};
    }
  }

  static Future<bool> _sendPayload(
    Map<String, dynamic> payload, {
    bool fromQueue = false,
  }) async {
    final config = _config!;
    final maxAttempts = fromQueue ? 1 : config.maxRetries;
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (config.apiKey.isNotEmpty) {
      headers['X-Api-Key'] = config.apiKey;
    }

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await http
            .post(
              Uri.parse(config.endpoint),
              headers: headers,
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
