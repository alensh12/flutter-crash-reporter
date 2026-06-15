const app = require('./api/index');

const preferredPort = Number.parseInt(process.env.PORT || '3000', 10);
const maxAttempts = 10;

function startServer(port, attempt = 0) {
  const server = app.listen(port);

  server.on('listening', () => {
    if (port !== preferredPort) {
      console.warn(`Port ${preferredPort} is in use. Using http://localhost:${port} instead.`);
    }

    console.log(`Crash reporter running at http://localhost:${port}`);
  });

  server.on('error', (error) => {
    if (error.code === 'EADDRINUSE' && attempt < maxAttempts - 1) {
      return startServer(port + 1, attempt + 1);
    }

    if (error.code === 'EADDRINUSE') {
      console.error(`Ports ${preferredPort}-${port} are already in use.`);
      console.error('Stop the other process or run with a custom port, e.g.:');
      console.error('  PORT=3001 npm run dev');
      console.error('  lsof -i :3000');
      process.exit(1);
    }

    console.error(error);
    process.exit(1);
  });
}

startServer(preferredPort);
