import 'package:flutter/material.dart';
import 'package:tizen_crash_reporter/tizen_crash_reporter.dart';

/// Example wiring for a flutter-tizen app.
///
/// Replace endpoint/apiKey/app metadata with your real values.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await CrashReporter.init(
    config: const CrashReporterConfig(
      endpoint: 'https://your-app.vercel.app/crashes',
      apiKey: 'your-secret-key',
      appId: 'com.example.tizen.tvapp',
      appVersion: '1.0.0',
      buildNumber: '1',
      deviceType: TizenDeviceType.tv,
      deviceModel: 'Samsung TV',
      tizenVersion: '8.0',
    ),
  );

  CrashReporter.installGlobalHandlers();

  await CrashReporter.runGuarded(() async {
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
