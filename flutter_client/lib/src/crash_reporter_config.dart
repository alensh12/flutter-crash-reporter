class CrashReporterConfig {
  const CrashReporterConfig({
    required this.endpoint,
    required this.apiKey,
    required this.appId,
    required this.appVersion,
    this.buildNumber,
    this.deviceType = TizenDeviceType.unknown,
    this.deviceModel,
    this.tizenVersion,
    this.timeout = const Duration(seconds: 10),
    this.maxQueueSize = 100,
    this.maxRetries = 3,
    this.userId,
    this.userEmail,
    this.userName,
  });

  /// Example: https://your-app.vercel.app/crashes
  final String endpoint;

  /// Sent as `X-Api-Key` header.
  final String apiKey;
  final String appId;
  final String appVersion;
  final String? buildNumber;
  final TizenDeviceType deviceType;
  final String? deviceModel;
  final String? tizenVersion;
  final Duration timeout;
  final int maxQueueSize;
  final int maxRetries;
  final String? userId;
  final String? userEmail;
  final String? userName;
}

enum TizenDeviceType {
  tv('tv'),
  watch('watch'),
  mobile('mobile'),
  unknown('unknown');

  const TizenDeviceType(this.value);
  final String value;
}
