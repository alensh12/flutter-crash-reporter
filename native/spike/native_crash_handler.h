#ifndef NATIVE_CRASH_HANDLER_H_
#define NATIVE_CRASH_HANDLER_H_

// Reference spike for Phase 2 native (C/C++) crash capture.
// Canonical copy lives in flutter-tizen:
//   embedding/cpp/native_crash_handler.{h,cc}
//
// Wire InstallNativeCrashHandlers() into native engine startup so crash JSON
// lands in <app_data>/crashes/ for CrashReporter.flushNativeCrashes().

void InstallNativeCrashHandlers();

#endif  // NATIVE_CRASH_HANDLER_H_
