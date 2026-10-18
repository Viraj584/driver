import { createApp } from './app.js';
import { env } from './config/env.js';
import { getDatabase, closeDatabase } from './db/database.js';

const app = createApp();

// Initialize database
const db = getDatabase();
console.log(`[Database] SQLite connected at: ${env.DATABASE_PATH}`);

const server = app.listen(env.PORT, env.HOST, () => {
  console.log(`[Trust Juggler API] Server running at http://${env.HOST}:${env.PORT}`);
  console.log(`[Trust Juggler API] Environment: ${env.NODE_ENV}`);
  console.log(`[Trust Juggler API] Health check: http://${env.HOST}:${env.PORT}/api/health`);
});

// Graceful shutdown handling
function gracefulShutdown(signal: string) {
  console.log(`\n[Server] Received ${signal}. Shutting down gracefully...`);
  server.close(() => {
    console.log('[Server] HTTP server closed.');
    closeDatabase();
    console.log('[Database] Database connection closed.');
    process.exit(0);
  });

  setTimeout(() => {
    console.error('[Server] Forceful shutdown after timeout.');
    process.exit(1);
  }, 10000).unref();
}

process.on('SIGINT', () => gracefulShutdown('SIGINT'));
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
