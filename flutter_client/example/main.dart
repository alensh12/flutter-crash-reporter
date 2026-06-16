import 'package:flutter/material.dart';
import 'package:tizen_crash_reporter/tizen_crash_reporter.dart';

/// Example wiring for a flutter-tizen app.
///
/// Replace endpoint/apiKey/app metadata with your real values.
Future<void> main() async {
  await CrashReporter.runGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    await CrashReporter.init(
      config: CrashReporterConfig(
        endpoint: 'https://your-app.vercel.app/crashes',
        // Leave apiKey empty until CRASH_REPORTER_API_KEY is set on Vercel.
        appId: 'com.example.tizen.tvapp',
        appVersion: '1.0.0',
        buildNumber: '1',
        deviceType: TizenDeviceType.tv,
        deviceModel: 'Samsung TV',
        tizenVersion: '8.0',
        enableNativeCrashFlush: true,
        metadataProvider: () async {
          // Replace with PackageInfo + DeviceInfoPluginTizen in a real app.
          return {
            'appId': 'com.example.tizen.tvapp',
            'appVersion': '1.0.0',
            'buildNumber': '1',
            'deviceType': 'tv',
            'deviceModel': 'Samsung TV',
            'tizenVersion': '8.0',
          };
        },
      ),
    );

    CrashReporter.installGlobalHandlers();
    runApp(const ExampleApp());
  });
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Tizen Crash Reporter Sketch')),
        body: Center(
          child: ElevatedButton(
            onPressed: () {
              CrashReporter.addBreadcrumb('User tapped test crash button');
              throw StateError('Intentional test crash');
            },
            child: const Text('Trigger test crash'),
          ),
        ),
      ),
    );
  }
}
