const crypto = require('crypto');

const { getSupabase, isSupabaseConfigured } = require('./supabase');

/**
 * Crash storage: Supabase Postgres when configured, otherwise in-memory (local dev).
 */
const memoryCrashes = new Map();
const memoryGroups = new Map();

function buildRecord(payload) {
  const id = crypto.randomUUID();
  const receivedAt = new Date().toISOString();

  return {
    id,
    receivedAt,
    ...payload,
  };
}

function updateMemoryGroup(record) {
  const group = memoryGroups.get(record.fingerprint) || {
    fingerprint: record.fingerprint,
    count: 0,
    firstSeenAt: record.timestamp,
    lastSeenAt: record.timestamp,
    sampleMessage: record.message,
    sampleAppVersion: record.appVersion,
    deviceTypes: new Set(),
  };

  group.count += 1;
  group.lastSeenAt = record.timestamp;
  group.sampleMessage = record.message;
  group.sampleAppVersion = record.appVersion;
  group.deviceTypes.add(record.deviceType);
  memoryGroups.set(record.fingerprint, group);
}

function rowToRecord(row) {
  if (!row) {
    return null;
  }

  if (row.payload && typeof row.payload === 'object') {
    return row.payload;
  }

  return null;
}

function toDbRow(record) {
  return {
    id: record.id,
    received_at: record.receivedAt,
    app_id: record.appId,
    app_version: record.appVersion,
    build_number: record.buildNumber,
    fingerprint: record.fingerprint,
    error_source: record.errorSource || 'dart',
    error_type: record.errorType,
    device_type: record.deviceType || 'unknown',
    device_model: record.deviceModel,
    tizen_version: record.tizenVersion,
    fatal: record.fatal !== false,
    message: record.message,
    stack_trace: record.stackTrace,
    client_timestamp: record.timestamp,
    payload: record,
  };
}

async function createCrashRecord(payload) {
  const record = buildRecord(payload);

  if (!isSupabaseConfigured()) {
    memoryCrashes.set(record.id, record);
    updateMemoryGroup(record);
    return record;
  }

  const supabase = getSupabase();
  const { error } = await supabase.from('crash_reports').insert(toDbRow(record));

  if (error) {
    throw new Error(`Supabase insert failed: ${error.message}`);
  }

  return record;
}

async function listCrashes({ limit = 50, appId, fingerprint } = {}) {
  if (!isSupabaseConfigured()) {
    let items = [...memoryCrashes.values()];

    if (appId) {
      items = items.filter((crash) => crash.appId === appId);
    }

    if (fingerprint) {
      items = items.filter((crash) => crash.fingerprint === fingerprint);
    }

    items.sort((a, b) => Date.parse(b.receivedAt) - Date.parse(a.receivedAt));
    return items.slice(0, limit);
  }

  const supabase = getSupabase();
  let query = supabase
    .from('crash_reports')
    .select('payload')
    .order('received_at', { ascending: false })
    .limit(limit);

  if (appId) {
    query = query.eq('app_id', appId);
  }

  if (fingerprint) {
    query = query.eq('fingerprint', fingerprint);
  }

  const { data, error } = await query;

  if (error) {
    throw new Error(`Supabase list failed: ${error.message}`);
  }

  return (data || []).map((row) => rowToRecord(row)).filter(Boolean);
}

async function getCrashById(id) {
  if (!isSupabaseConfigured()) {
    return memoryCrashes.get(id) || null;
  }

  const supabase = getSupabase();
  const { data, error } = await supabase
    .from('crash_reports')
    .select('payload')
    .eq('id', id)
    .maybeSingle();

  if (error) {
    throw new Error(`Supabase get failed: ${error.message}`);
  }

  return rowToRecord(data);
}

function aggregateGroups(rows, { limit = 50, appId } = {}) {
  const groups = new Map();

  for (const row of rows) {
    const record = rowToRecord(row);
    if (!record) {
      continue;
    }

    if (appId && record.appId !== appId) {
      continue;
    }

    const group = groups.get(record.fingerprint) || {
      fingerprint: record.fingerprint,
      count: 0,
      firstSeenAt: record.timestamp,
      lastSeenAt: record.timestamp,
      sampleMessage: record.message,
      sampleAppVersion: record.appVersion,
      deviceTypes: new Set(),
    };

    group.count += 1;

    if (Date.parse(record.timestamp) < Date.parse(group.firstSeenAt)) {
      group.firstSeenAt = record.timestamp;
    }

    if (Date.parse(record.timestamp) > Date.parse(group.lastSeenAt)) {
      group.lastSeenAt = record.timestamp;
      group.sampleMessage = record.message;
      group.sampleAppVersion = record.appVersion;
    }

    group.deviceTypes.add(record.deviceType);
    groups.set(record.fingerprint, group);
  }

  return [...groups.values()]
    .sort((a, b) => Date.parse(b.lastSeenAt) - Date.parse(a.lastSeenAt))
    .slice(0, limit)
    .map((group) => ({
      fingerprint: group.fingerprint,
      count: group.count,
      firstSeenAt: group.firstSeenAt,
      lastSeenAt: group.lastSeenAt,
      sampleMessage: group.sampleMessage,
      sampleAppVersion: group.sampleAppVersion,
      deviceTypes: [...group.deviceTypes],
    }));
}

async function listGroups({ limit = 50, appId } = {}) {
  if (!isSupabaseConfigured()) {
    let items = [...memoryGroups.values()];

    if (appId) {
      items = items.filter((group) => {
        const sample = [...memoryCrashes.values()].find(
          (crash) => crash.fingerprint === group.fingerprint && crash.appId === appId,
        );
        return Boolean(sample);
      });
    }

    items.sort((a, b) => Date.parse(b.lastSeenAt) - Date.parse(a.lastSeenAt));

    return items.slice(0, limit).map((group) => ({
      fingerprint: group.fingerprint,
      count: group.count,
      firstSeenAt: group.firstSeenAt,
      lastSeenAt: group.lastSeenAt,
      sampleMessage: group.sampleMessage,
      sampleAppVersion: group.sampleAppVersion,
      deviceTypes: [...group.deviceTypes],
    }));
  }

  const supabase = getSupabase();
  const scanLimit = Math.min(Math.max(limit * 100, 500), 5000);

  let query = supabase
    .from('crash_reports')
    .select('payload')
    .order('received_at', { ascending: false })
    .limit(scanLimit);

  if (appId) {
    query = query.eq('app_id', appId);
  }

  const { data, error } = await query;

  if (error) {
    throw new Error(`Supabase groups failed: ${error.message}`);
  }

  return aggregateGroups(data || [], { limit, appId });
}

module.exports = {
  createCrashRecord,
  listCrashes,
  getCrashById,
  listGroups,
  isSupabaseConfigured,
};
