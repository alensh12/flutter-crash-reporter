const crypto = require('crypto');

/**
 * Sketch storage layer.
 *
 * Vercel functions are stateless, so this in-memory store resets on cold starts.
 * For production on Tizen, swap this module for Postgres / Supabase / MongoDB
 * without changing the API contract.
 */
const crashes = new Map();
const groups = new Map();

function createCrashRecord(payload) {
  const id = crypto.randomUUID();
  const receivedAt = new Date().toISOString();

  const record = {
    id,
    receivedAt,
    ...payload,
  };

  crashes.set(id, record);

  const group = groups.get(payload.fingerprint) || {
    fingerprint: payload.fingerprint,
    count: 0,
    firstSeenAt: payload.timestamp,
    lastSeenAt: payload.timestamp,
    sampleMessage: payload.message,
    sampleAppVersion: payload.appVersion,
    deviceTypes: new Set(),
  };

  group.count += 1;
  group.lastSeenAt = payload.timestamp;
  group.sampleMessage = payload.message;
  group.sampleAppVersion = payload.appVersion;
  group.deviceTypes.add(payload.deviceType);
  groups.set(payload.fingerprint, group);

  return record;
}

function listCrashes({ limit = 50, appId, fingerprint } = {}) {
  let items = [...crashes.values()];

  if (appId) {
    items = items.filter((crash) => crash.appId === appId);
  }

  if (fingerprint) {
    items = items.filter((crash) => crash.fingerprint === fingerprint);
  }

  items.sort((a, b) => Date.parse(b.receivedAt) - Date.parse(a.receivedAt));

  return items.slice(0, limit);
}

function getCrashById(id) {
  return crashes.get(id) || null;
}

function listGroups({ limit = 50, appId } = {}) {
  let items = [...groups.values()];

  if (appId) {
    items = items.filter((group) => {
      const sample = listCrashes({ limit: 1, fingerprint: group.fingerprint, appId })[0];
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

module.exports = {
  createCrashRecord,
  listCrashes,
  getCrashById,
  listGroups,
};
