const express = require('express');
const { validateCrashPayload } = require('./schema');
const { requireApiKey } = require('./auth');
const storage = require('./storage');

const app = express();

app.use(express.json({ limit: '256kb' }));

app.get('/', (req, res) => {
  res.json({
    status: 'ok',
    service: 'flutter-crash-reporter',
    platform: 'tizen',
    endpoints: {
      ingest: 'POST /crashes',
      list: 'GET /crashes',
      detail: 'GET /crashes/:id',
      groups: 'GET /crashes/groups/summary',
    },
  });
});

app.get('/crashes/groups/summary', requireApiKey, (req, res) => {
  const limit = parseLimit(req.query.limit, 50);
  const appId = req.query.appId || undefined;

  res.json({
    status: 'success',
    groups: storage.listGroups({ limit, appId }),
  });
});

app.get('/crashes/:id', requireApiKey, (req, res) => {
  const crash = storage.getCrashById(req.params.id);

  if (!crash) {
    return res.status(404).json({
      status: 'error',
      message: 'Crash report not found',
    });
  }

  return res.json({
    status: 'success',
    crash,
  });
});

app.get('/crashes', requireApiKey, (req, res) => {
  const limit = parseLimit(req.query.limit, 50);
  const appId = req.query.appId || undefined;
  const fingerprint = req.query.fingerprint || undefined;

  res.json({
    status: 'success',
    crashes: storage.listCrashes({ limit, appId, fingerprint }),
  });
});

app.post('/crashes', requireApiKey, (req, res) => {
  try {
    const validation = validateCrashPayload(req.body);

    if (!validation.ok) {
      return res.status(400).json({
        status: 'error',
        message: 'Invalid crash payload',
        errors: validation.errors,
      });
    }

    const record = storage.createCrashRecord(validation.crash);

    console.log('NEW TIZEN CRASH REPORT:', JSON.stringify(record, null, 2));

    return res.status(201).json({
      status: 'success',
      id: record.id,
      fingerprint: record.fingerprint,
      message: 'Crash reported successfully',
    });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ status: 'error', message: 'Internal server error' });
  }
});

function parseLimit(value, fallback) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return fallback;
  }

  return Math.min(parsed, 200);
}

module.exports = app;
