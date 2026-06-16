typedef CrashMetadataProvider = Future<Map<String, String>> Function();

class CrashReporterConfig {
  const CrashReporterConfig({
    required this.endpoint,
    this.apiKey = '',
    required this.appId,
    required this.appVersion,
    this.buildNumber,
    this.deviceType = TizenDeviceType.unknown,
    this.deviceModel,
    this.deviceId,
    this.tizenVersion,
    this.timeout = const Duration(seconds: 10),
    this.maxQueueSize = 100,
    this.maxRetries = 3,
    this.userId,
    this.userEmail,
    this.userName,
    this.enableNativeCrashFlush = true,
    this.nativeCrashChannel = 'tizen/crash_reporter',
    this.showFlutterErrorOnScreen = false,
    this.metadataProvider,
  });

  /// Example: https://your-app.vercel.app/crashes
  final String endpoint;

  /// Sent as `X-Api-Key` header when non-empty.
  final String apiKey;
  final String appId;
  final String appVersion;
  final String? buildNumber;
  final TizenDeviceType deviceType;
  final String? deviceModel;
  final String? deviceId;
  final String? tizenVersion;
  final Duration timeout;
  final int maxQueueSize;
  final int maxRetries;
  final String? userId;
  final String? userEmail;
  final String? userName;

  /// When true, pending native crash files are uploaded during [CrashReporter.init].
  final bool enableNativeCrashFlush;

  /// Method channel used to read/clear native crash files from App.cs.
  final String nativeCrashChannel;

  /// When true, [FlutterError.presentError] is called after reporting framework errors.
  final bool showFlutterErrorOnScreen;

  /// Optional hook to refresh app/device metadata before each report.
  final CrashMetadataProvider? metadataProvider;
}

enum TizenDeviceType {
  tv('tv'),
  watch('watch'),
  mobile('mobile'),
  unknown('unknown');

  const TizenDeviceType(this.value);
  final String value;
}
