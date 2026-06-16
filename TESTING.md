# Phase 1 native crash reporting — device test checklist

Run on a Samsung Tizen TV with a build that includes the updated `App.cs` and Dart SDK wiring.

## Prerequisites

- Deployed Vercel endpoint: `https://flutter-crash-reporter.vercel.app/crashes`
- No API key required today — `POST /crashes` is open while `CRASH_REPORTER_API_KEY` is unset on Vercel
- `sdb dlog` or Vercel function logs open for verification

## 1. Dart crash (immediate upload)

1. Launch the app.
2. Trigger a Dart exception from a debug button or dev menu.
3. Expect a `201` response and a log line containing `errorSource: dart`.

## 2. Offline Dart queue

1. Disconnect the TV from the network.
2. Trigger a Dart exception.
3. Restart the app with network restored.
4. Expect the queued crash to upload during `CrashReporter.init()` → `flushQueue()`.

## 3. Managed .NET crash (next-launch upload)

**Automated test hook (debug builds):**

1. Rebuild and run with the dart-define flag:

   ```bash
   flutter-tizen run --dart-define=SIMULATE_NATIVE_CRASH=true
   ```

2. Wait 10 seconds — a pending crash file is written (app keeps running).
3. **Cold-start the app again** (kill + relaunch).
4. On launch, expect `flushNativeCrashes()` to POST a report with `errorSource: native_managed`.
5. Watch logs:

   ```bash
   sdb dlog | grep -E 'CrashReporter|NativeCrashBridge|NativeCrashStore'
   ```

**Manual hook:** `CrashReporter.simulateManagedCrashForTesting()` calls the
`tizen/crash_reporter` channel method `simulateManagedCrash` in `App.cs`.

## 4. API key (later, optional)

When you add `CRASH_REPORTER_API_KEY` in Vercel project settings:

- Set the same value in the app: `apiKey: '...'` in `CrashReporterConfig`, or `--dart-define=CRASH_REPORTER_API_KEY=...`
- Unauthenticated requests will then return `401`

## Phase 2 (not covered here)

AVPlay/GStreamer segfaults require the C/C++ signal handler from `flutter-tizen/embedding/cpp/native_crash_handler.cc` to be linked into the native engine used by the C# runner. Validate separately once that library is rebuilt and deployed.
