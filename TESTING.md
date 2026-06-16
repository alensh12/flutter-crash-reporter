# Native crash reporting — device test checklist

Run on a Samsung Tizen TV with a build that includes `App.cs`, `native_crash_handler_plugin`, and the Dart SDK wiring.

## Prerequisites

- Deployed Vercel endpoint: `https://flutter-crash-reporter.vercel.app/crashes`
- No API key required today — `POST /crashes` is open while `CRASH_REPORTER_API_KEY` is unset on Vercel
- `sdb dlog` or Vercel function logs open for verification

## Phase 1

### 1. Dart crash (immediate upload)

1. Launch the app.
2. Trigger a Dart exception from a debug button or dev menu.
3. Expect a `201` response and a log line containing `errorSource: dart`.

### 2. Offline Dart queue

1. Disconnect the TV from the network.
2. Trigger a Dart exception.
3. Restart the app with network restored.
4. Expect the queued crash to upload during `CrashReporter.init()` → `flushQueue()`.

### 3. Managed .NET crash (next-launch upload)

**Automated test hook (debug builds):**

```bash
flutter-tizen run --dart-define=SIMULATE_NATIVE_CRASH=true
```

1. Wait 10 seconds — a pending crash file is written (app keeps running).
2. **Cold-start the app again** (kill + relaunch).
3. On launch, expect `flushNativeCrashes()` to POST a report with `errorSource: native_managed`.

**Manual hook:** `CrashReporter.simulateManagedCrashForTesting()`

### 4. API key (later, optional)

When you add `CRASH_REPORTER_API_KEY` in Vercel project settings:

- Set the same value in the app: `apiKey: '...'` in `CrashReporterConfig`, or `--dart-define=CRASH_REPORTER_API_KEY=...`
- Unauthenticated requests will then return `401`

## Phase 2 — Native C/C++ crashes (`native_cpp`)

Signal handlers are installed by `native_crash_handler_plugin.so` at app startup (via flutter-tizen `NativeCrashHandler.TryInstall()` and plugin registration). They write minimal JSON to `<app_data>/crashes/pending_<id>.json` and the process exits.

### 5. Controlled SIGSEGV (debug)

```bash
flutter-tizen run --dart-define=SIMULATE_NATIVE_CPP_CRASH=true
```

1. Wait 10 seconds — the app should terminate (SIGSEGV).
2. **Cold-start the app again**.
3. Expect `flushNativeCrashes()` to upload `errorSource: native_cpp` with `signal: SIGSEGV` and a raw address stack (`#0 0x...`).
4. Watch logs:

```bash
sdb dlog | grep -E 'CrashReporter|NativeCrashBridge|NativeCrashStore|native_cpp'
```

**Manual hook:** `CrashReporter.simulateNativeCppCrashForTesting()`

### 6. AVPlay / GStreamer segfault (real-world)

On a Samsung TV (e.g. UA43CU7700):

1. Deploy a build with `native_crash_handler_plugin` included.
2. Reproduce a known AVPlay/GStreamer native crash scenario (e.g. playback edge case that previously segfaulted).
3. Confirm the app process dies.
4. Relaunch the app and verify:
   - `pending_*.json` existed under app data `crashes/` (optional: inspect via `sdb shell` if available)
   - Supabase / API row has `error_source = native_cpp`
   - `stack_trace` contains raw native addresses, not Dart file:line

If no pending file appears after a segfault, the crash may have occurred before handlers were installed, or the signal was not SIGSEGV/SIGABRT/SIGBUS.

### Phase 2 limitations (expected)

| Limitation | Detail |
|------------|--------|
| Process death | True segfault kills the app; upload only after restart |
| Raw backtraces | `#0 0x...` addresses only — no file:line symbolication |
| Async-signal-safe JSON | Minimal fields only; timestamp filled on upload |
| Handler coverage | SIGSEGV, SIGABRT, SIGBUS only unless extended later |
| AVPlay not guaranteed | Plugin crash paths vary by firmware; validate on target TV |
