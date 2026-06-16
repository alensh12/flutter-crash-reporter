-- Run once in the Supabase SQL editor (Dashboard → SQL → New query).
-- Stores Tizen crash reports ingested by POST /crashes.

create table if not exists public.crash_reports (
  id uuid primary key,
  received_at timestamptz not null default now(),
  app_id text not null,
  app_version text not null,
  build_number text,
  fingerprint text not null,
  error_source text not null default 'dart',
  error_type text,
  device_type text not null default 'unknown',
  device_model text,
  tizen_version text,
  fatal boolean not null default true,
  message text,
  stack_trace text,
  client_timestamp timestamptz not null,
  payload jsonb not null
);

-- Migration for tables created before dedicated crash columns were added.
alter table public.crash_reports
  add column if not exists build_number text,
  add column if not exists error_type text,
  add column if not exists device_model text,
  add column if not exists tizen_version text,
  add column if not exists fatal boolean not null default true,
  add column if not exists message text,
  add column if not exists stack_trace text;

create index if not exists crash_reports_received_at_idx
  on public.crash_reports (received_at desc);

create index if not exists crash_reports_app_id_idx
  on public.crash_reports (app_id);

create index if not exists crash_reports_fingerprint_idx
  on public.crash_reports (fingerprint);

create index if not exists crash_reports_app_id_fingerprint_idx
  on public.crash_reports (app_id, fingerprint);

create index if not exists crash_reports_error_type_idx
  on public.crash_reports (error_type);

create index if not exists crash_reports_fatal_idx
  on public.crash_reports (fatal);

-- Optional: enable RLS and deny direct client access (API uses service role key).
alter table public.crash_reports enable row level security;
