import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reads pending native crash files via a Tizen [MethodChannel].
class NativeCrashBridge {
  NativeCrashBridge(this.channelName);

  final String channelName;

  MethodChannel get _channel => MethodChannel(channelName);

  Future<List<Map<String, dynamic>>> getPendingNativeCrashes() async {
    debugPrint('[NativeCrashBridge] getPendingNativeCrashes → channel=$channelName');
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'getPendingNativeCrashes',
      );
      final count = result?.length ?? 0;
      debugPrint('[NativeCrashBridge] getPendingNativeCrashes ← $count item(s)');
      if (result == null) {
        return [];
      }

      return result
          .whereType<Map>()
          .map((item) => item.map((key, value) => MapEntry('$key', value)))
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } on MissingPluginException catch (error) {
      debugPrint('[NativeCrashBridge] getPendingNativeCrashes MissingPluginException: $error');
      return [];
    } on PlatformException catch (error) {
      debugPrint(
        '[NativeCrashBridge] getPendingNativeCrashes PlatformException: '
        '${error.code} ${error.message}',
      );
      return [];
    } catch (error) {
      debugPrint('[NativeCrashBridge] getPendingNativeCrashes error: $error');
      return [];
    }
  }

  Future<void> clearPendingNativeCrash(String id) async {
    debugPrint('[NativeCrashBridge] clearPendingNativeCrash → id=$id');
    try {
      await _channel.invokeMethod<void>(
        'clearPendingNativeCrash',
        {'id': id},
      );
      debugPrint('[NativeCrashBridge] clearPendingNativeCrash ← ok');
    } on MissingPluginException catch (error) {
      debugPrint('[NativeCrashBridge] clearPendingNativeCrash MissingPluginException: $error');
    } on PlatformException catch (error) {
      debugPrint(
        '[NativeCrashBridge] clearPendingNativeCrash PlatformException: '
        '${error.code} ${error.message}',
      );
    } catch (error) {
      debugPrint('[NativeCrashBridge] clearPendingNativeCrash error: $error');
    }
  }

  /// Debug-only: writes a pending native crash file via App.cs.
  Future<void> simulateManagedCrash() async {
    debugPrint('[NativeCrashBridge] simulateManagedCrash →');
    try {
      await _channel.invokeMethod<void>('simulateManagedCrash');
      debugPrint('[NativeCrashBridge] simulateManagedCrash ← ok');
    } on MissingPluginException catch (error) {
      debugPrint('[NativeCrashBridge] simulateManagedCrash MissingPluginException: $error');
      rethrow;
    } on PlatformException catch (error) {
      debugPrint(
        '[NativeCrashBridge] simulateManagedCrash PlatformException: '
        '${error.code} ${error.message}',
      );
      rethrow;
    } catch (error) {
      debugPrint('[NativeCrashBridge] simulateManagedCrash error: $error');
      rethrow;
    }
  }

  /// Debug-only: triggers a native SIGSEGV in the host process.
  Future<void> simulateNativeCppCrash() async {
    debugPrint('[NativeCrashBridge] simulateNativeCppCrash →');
    try {
      await _channel.invokeMethod<void>('simulateNativeCppCrash');
      debugPrint('[NativeCrashBridge] simulateNativeCppCrash ← ok');
    } on MissingPluginException catch (error) {
      debugPrint('[NativeCrashBridge] simulateNativeCppCrash MissingPluginException: $error');
      rethrow;
    } on PlatformException catch (error) {
      debugPrint(
        '[NativeCrashBridge] simulateNativeCppCrash PlatformException: '
        '${error.code} ${error.message}',
      );
      rethrow;
    } catch (error) {
      debugPrint('[NativeCrashBridge] simulateNativeCppCrash error: $error');
      rethrow;
    }
  }
}
