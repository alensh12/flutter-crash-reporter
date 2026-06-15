/// Sketch Flutter-Tizen crash reporter for a custom REST backend.
///
/// Drop this into your flutter-tizen app and wire [CrashReporter.init]
/// before [runApp]. The reporter captures Dart/Flutter errors, queues
/// reports offline, and POSTs to `POST /crashes`.
library tizen_crash_reporter;

export 'src/crash_reporter.dart';
export 'src/crash_reporter_config.dart';
