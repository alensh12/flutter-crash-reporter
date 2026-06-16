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

Recent updates persist key crash fields in dedicated columns (`error_type`, `message`, `stack_trace`, `device_model`, `tizen_version`, `fatal`, etc.) while also keeping the full raw object in `payload` JSONB.

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

## Architecture overview

1. **Device crash occurs** (Dart/Flutter immediately, native managed on next launch)
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
- `deviceModel`, `tizenVersion`, `buildNumber`
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
- Native crash capture itself depends on host-side Tizen implementation; this repo provides the Flutter bridge + upload flow.
- The API currently logs ingest events to Vercel function logs for debugging.
