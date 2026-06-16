#ifndef NATIVE_CRASH_HANDLER_H_
#define NATIVE_CRASH_HANDLER_H_

// Phase 2 native (C/C++) crash capture for Flutter-on-Tizen.
//
// Canonical implementation:
//   flutter-tizen/embedding/cpp/native_crash_handler.cc
//   nettv native_crash_handler_plugin (shared lib shipped in app TPK)
//
// Install at process start before the Flutter engine loads. Handlers write
// minimal async-signal-safe JSON to <app_data>/crashes/pending_<id>.json:
//
//   {
//     "id": "<unix>_<pid>",
//     "errorSource": "native_cpp",
//     "fatal": true,
//     "errorType": "SIGSEGV",
//     "signal": "SIGSEGV",
//     "message": "Native crash: SIGSEGV",
//     "stackTrace": "#0 0x...\\n#1 0x..."
//   }
//
// Timestamp is omitted; CrashReporter.flushNativeCrashes() fills ISO-8601 on upload.
// Upload happens on the next app launch via tizen/crash_reporter MethodChannel.

#ifdef __cplusplus
extern "C" {
#endif

void InstallNativeCrashHandlers();

#ifdef __cplusplus
}
#endif

#endif  // NATIVE_CRASH_HANDLER_H_

