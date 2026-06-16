-- Run once in the Supabase SQL editor (Dashboard → SQL → New query).
-- Stores Tizen crash reports ingested by POST /crashes.

create table if not exists public.crash_reports (
  id uuid primary key,
  received_at timestamptz not null default now(),
  app_id text not null,
  app_version text not null,
  fingerprint text not null,
  error_source text not null default 'dart',
  device_type text not null default 'unknown',
  client_timestamp timestamptz not null,
  payload jsonb not null
);

create index if not exists crash_reports_received_at_idx
  on public.crash_reports (received_at desc);

create index if not exists crash_reports_app_id_idx
  on public.crash_reports (app_id);

create index if not exists crash_reports_fingerprint_idx
  on public.crash_reports (fingerprint);

create index if not exists crash_reports_app_id_fingerprint_idx
  on public.crash_reports (app_id, fingerprint);

-- Optional: enable RLS and deny direct client access (API uses service role key).
alter table public.crash_reports enable row level security;
