function requireApiKey(req, res, next) {
  const configuredKey = process.env.CRASH_REPORTER_API_KEY;

  // Local/dev sketch: allow unauthenticated traffic when no key is configured.
  if (!configuredKey) {
    return next();
  }

  const headerKey = req.get('x-api-key');
  const bearer = req.get('authorization');
  const token =
    headerKey ||
    (bearer && bearer.startsWith('Bearer ') ? bearer.slice('Bearer '.length) : null);

  if (!token || token !== configuredKey) {
    return res.status(401).json({
      status: 'error',
      message: 'Invalid or missing API key',
    });
  }

  return next();
}

module.exports = {
  requireApiKey,
};
