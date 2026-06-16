# Flutter Crash Reporter (Tizen)

Crash reporting stack for Flutter-on-Tizen apps, with:

- a Vercel-hosted ingest API (`POST /crashes`)
- persistent storage in Supabase Postgres
- a Flutter client SDK (`flutter_client`) that captures Dart/Flutter crashes
- native crash flush support through a Tizen `MethodChannel`

## What this project does

This repository contains two main pieces:

1. **Crash API (Node.js + Express)** in `api/`
   - Validates crash payloads
   - Computes a fingerprint for grouping
   - Stores records in Supabase (or in-memory fallback if Supabase is not configured)
   - Exposes query endpoints for debugging and reporting

2. **Flutter client package** in `flutter_client/`
   - Installs global Dart/Flutter error handlers
   - Sends crash payloads to the Vercel endpoint
   - Queues failed uploads locally and retries on next app start
   - Reads pending native crash files through `MethodChannel` and uploads them

## How Vercel and Supabase are used

### Vercel

Vercel hosts the API function defined in `api/index.js`:

- `POST /crashes` - ingest crash reports
- `GET /crashes` - list crashes (API key protected when configured)
- `GET /crashes/:id` - crash detail
- `GET /crashes/groups/summary` - grouped crash summary
- `GET /` - health + current storage mode (`supabase` or `memory`)

`vercel.json` rewrites all routes to `/api/index`.

### Supabase

Supabase is the persistent storage layer for crash records:

- table: `public.crash_reports`
- schema SQL: `supabase/schema.sql`
- client init: `api/supabase.js`
- insert/read logic: `api/storage.js`

Recent updates persist key crash fields in dedicated columns (`error_type`, `message`, `stack_trace`, `device_model`, `device_id`, `tizen_version`, `fatal`, etc.) while also keeping the full raw object in `payload` JSONB.

## How errors are captured from Flutter Tizen devices

## 1) Dart/Flutter errors (immediate path)

In the app, `CrashReporter.installGlobalHandlers()` in `flutter_client/lib/src/crash_reporter.dart` wires:

- `FlutterError.onError` (Flutter framework exceptions)
- `PlatformDispatcher.instance.onError` (uncaught async/platform errors)
- plus zone-level handling via `CrashReporter.runGuarded(...)`

When an error happens:

1. SDK builds payload (`platform`, `appId`, `appVersion`, `errorType`, `errorSource`, `message`, `stackTrace`, device metadata, breadcrumbs, session info)
2. SDK `POST`s to Vercel endpoint
3. If network/upload fails, payload is queued in `SharedPreferences`
4. Queue is flushed on next launch (`flushQueue()`)

## 2) Native managed crashes (next-launch path)

Native crash handoff is done through `NativeCrashBridge` in `flutter_client/lib/src/native_crash_bridge.dart`:

- `getPendingNativeCrashes`
- `clearPendingNativeCrash`
- `simulateManagedCrash` (debug)

Flow:

1. Tizen native layer (implemented in the app host side) writes pending crash file(s)
2. On next app launch, `CrashReporter.init()` calls `flushNativeCrashes()`
3. SDK reads pending native crashes through MethodChannel
4. Each native crash is uploaded to Vercel with `errorSource: native_managed` (or provided source)
5. If upload succeeds, SDK asks host to delete the pending crash entry

## 3) Native C/C++ crashes (`native_cpp`, next-launch path)

Requires `native_crash_handler_plugin` in the host app TPK. Signal handlers (`SIGSEGV`, `SIGABRT`, `SIGBUS`) write async-signal-safe JSON to `<app_data>/crashes/pending_<id>.json` and the process exits.

- `simulateNativeCppCrash` (debug) — triggers a test SIGSEGV via `TriggerTestSegfault()`
- Upload uses the same `flushNativeCrashes()` path as managed native crashes
- `errorSource` is `native_cpp`; `signal` is copied into `customKeys`
- Backtraces are raw native addresses (`#0 0x...`), not Dart file:line

Install path:

1. Add `native_crash_handler_plugin` to the app `pubspec.yaml`
2. flutter-tizen `NativeCrashHandler.TryInstall()` runs in `FlutterApplication.OnCreate()` (requires updated embedding)
3. Plugin `.so` is packaged into the TPK `lib/` directory

## Architecture overview

1. **Device crash occurs** (Dart/Flutter immediately; `native_managed` / `native_cpp` on next launch)
2. **Flutter SDK** formats payload and sends to `POST /crashes`
3. **Vercel API** validates with `api/schema.js`
4. **Storage layer** writes to Supabase `crash_reports`
5. **Consumers** query via `GET /crashes` and summary endpoints

## API contract

### `POST /crashes`

Request body (minimum required):

- `platform` (`"tizen"`)
- `appId`
- `appVersion`
- `message`

Optional but recommended:

- `errorType`
- `errorSource` (`dart`, `flutter`, `native_managed`, `native_cpp`)
- `stackTrace`
- `deviceModel`, `deviceId` (Tizen device ID / `tizenId`), `tizenVersion`, `buildNumber`
- `fatal`, `timestamp`, `customKeys`, `breadcrumbs`

Response (`201`):

```json
{
  "status": "success",
  "id": "uuid",
  "fingerprint": "16-char-hash",
  "message": "Crash reported successfully"
}
```

## Fatal vs non-fatal classification

Every crash report includes a `fatal` boolean. This is a classification label for
triage and filtering. The current API stores both fatal and non-fatal crashes.

### How `fatal` is set

- **Flutter SDK:** global handlers (`FlutterError`, `PlatformDispatcher`, and
  zone errors via `runGuarded`) report with `fatal: true` by default.
- **Manual reports:** app code can explicitly send `fatal: false` through
  `CrashReporter.report(...)`.
- **Native crash flush:** uses native crash value when present, otherwise falls
  back to `fatal: true`.
- **API normalization:** when omitted, `fatal` defaults to `true`.

### Classification rules

- **Fatal:** `fatal == true` (default for uncaught/runtime crashes)
- **Non-fatal:** `fatal == false` (explicitly marked by caller)

`errorSource` and `fatal` are independent fields. For example, a `dart` error
can still be marked non-fatal if the caller reports it that way.

### Database storage

`fatal` is stored in two places:

- dedicated boolean column: `crash_reports.fatal`
- full raw payload JSON: `crash_reports.payload`

### Query examples (Supabase SQL)

Fatal only:

```sql
select id, app_id, error_type, message, error_source, client_timestamp
from public.crash_reports
where fatal = true
order by received_at desc;
```

Non-fatal only:

```sql
select id, app_id, error_type, message, error_source, client_timestamp
from public.crash_reports
where fatal = false
order by received_at desc;
```

Fatal native managed only:

```sql
select id, app_id, error_type, message, client_timestamp
from public.crash_reports
where fatal = true
  and error_source = 'native_managed'
order by received_at desc;
```

Optional metadata keys from `metadataProvider` that are not mapped to top-level
crash fields (for example `deviceDuid`) are copied into `customKeys` automatically.

## Local development

Install and run:

```bash
npm install
npm run dev
```

Vercel local mode:

```bash
npm run dev:vercel
```

Schema test:

```bash
npm run test:schema
```

## Environment variables

Use `.env.example` as reference:

- `CRASH_REPORTER_API_KEY` (optional; when set, protected endpoints require it)
- `SUPABASE_URL` (must be base URL, no `/rest/v1` suffix)
- `SUPABASE_SERVICE_ROLE_KEY` (server secret, never expose to client apps)

## Supabase setup

1. Create Supabase project
2. Run `supabase/schema.sql` in SQL Editor
3. Set `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` in Vercel project env vars
4. Redeploy Vercel project
5. Verify `GET /` returns `"storage":"supabase"`

## Notes and limitations

- If Supabase env vars are missing, API falls back to in-memory storage (non-persistent).
- **Dart / Flutter crashes** upload immediately (or queue offline).
- **Managed .NET crashes** (`native_managed`) persist to disk and upload on next launch.
- **Native C/C++ crashes** (`native_cpp`) require `native_crash_handler_plugin` in the app TPK. Signal handlers write minimal JSON to `<app_data>/crashes/`; upload happens on the next cold start via `flushNativeCrashes()`.

### Native C/C++ limitations (Phase 2)

| Limitation | Detail |
|------------|--------|
| AVPlay/GStreamer segfaults | Handlers catch SIGSEGV/SIGABRT/SIGBUS when the plugin is linked; real-world AVPlay paths must be validated per TV firmware |
| C# runner wiring | Handlers install via `native_crash_handler_plugin.so` + flutter-tizen `NativeCrashHandler.TryInstall()` — not from `libflutter_tizen.so` alone |
| Signal-handler constraints | Async-signal-safe only (`dprintf`, `backtrace`); no rich symbolication in-process |
| Process death | Segfault still kills the app; no in-process upload |
| No symbols | Backtraces are raw addresses (`#0 0x...`), not `file:line` like Dart |

See [`TESTING.md`](TESTING.md) Phase 2 for device validation steps.

- The API currently logs ingest events to Vercel function logs for debugging.
