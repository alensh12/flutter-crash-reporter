const crypto = require('crypto');

const DEVICE_TYPES = new Set(['tv', 'watch', 'mobile', 'unknown']);

/**
 * Minimal production schema for Flutter-on-Tizen crash reports.
 * Swap storage later; keep this shape stable for the client SDK.
 */
function validateCrashPayload(body) {
  const errors = [];

  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    return { ok: false, errors: ['Body must be a JSON object'] };
  }

  const platform = requireString(body.platform, 'platform', errors);
  if (platform && platform !== 'tizen') {
    errors.push('platform must be "tizen"');
  }

  requireString(body.appId, 'appId', errors);
  requireString(body.appVersion, 'appVersion', errors);
  requireString(body.message, 'message', errors);

  if (body.deviceType !== undefined && !DEVICE_TYPES.has(body.deviceType)) {
    errors.push(`deviceType must be one of: ${[...DEVICE_TYPES].join(', ')}`);
  }

  if (body.fatal !== undefined && typeof body.fatal !== 'boolean') {
    errors.push('fatal must be a boolean');
  }

  if (body.breadcrumbs !== undefined) {
    if (!Array.isArray(body.breadcrumbs)) {
      errors.push('breadcrumbs must be an array of strings');
    } else if (body.breadcrumbs.some((item) => typeof item !== 'string')) {
      errors.push('breadcrumbs must contain only strings');
    }
  }

  if (body.customKeys !== undefined) {
    if (
      typeof body.customKeys !== 'object' ||
      body.customKeys === null ||
      Array.isArray(body.customKeys)
    ) {
      errors.push('customKeys must be an object');
    }
  }

  if (body.timestamp !== undefined && !isIsoTimestamp(body.timestamp)) {
    errors.push('timestamp must be a valid ISO-8601 string');
  }

  if (errors.length > 0) {
    return { ok: false, errors };
  }

  const normalized = {
    platform: 'tizen',
    deviceType: body.deviceType || 'unknown',
    deviceModel: optionalString(body.deviceModel),
    tizenVersion: optionalString(body.tizenVersion),
    appId: body.appId.trim(),
    appVersion: body.appVersion.trim(),
    buildNumber: optionalString(body.buildNumber),
    fatal: body.fatal !== false,
    errorType: optionalString(body.errorType) || 'UnknownError',
    message: body.message.trim(),
    stackTrace: optionalString(body.stackTrace),
    breadcrumbs: Array.isArray(body.breadcrumbs) ? body.breadcrumbs.slice(-50) : [],
    sessionId: optionalString(body.sessionId),
    timestamp: body.timestamp || new Date().toISOString(),
    customKeys: body.customKeys || {},
    userId: optionalString(body.userId),
  };

  normalized.fingerprint = computeFingerprint(normalized);

  return { ok: true, crash: normalized };
}

function computeFingerprint(crash) {
  const topFrame = extractTopFrame(crash.stackTrace);
  const raw = [crash.errorType, crash.message, topFrame].join('|').toLowerCase();

  return crypto.createHash('sha256').update(raw).digest('hex').slice(0, 16);
}

function extractTopFrame(stackTrace) {
  if (!stackTrace) {
    return '';
  }

  const lines = stackTrace
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean);

  for (const line of lines) {
    if (line.startsWith('#0') || line.includes('.dart:')) {
      return line;
    }
  }

  return lines[0] || '';
}

function requireString(value, field, errors) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    errors.push(`${field} is required and must be a non-empty string`);
    return null;
  }

  return value.trim();
}

function optionalString(value) {
  if (typeof value !== 'string') {
    return null;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function isIsoTimestamp(value) {
  if (typeof value !== 'string') {
    return false;
  }

  const time = Date.parse(value);
  return Number.isFinite(time);
}

module.exports = {
  validateCrashPayload,
  computeFingerprint,
};
