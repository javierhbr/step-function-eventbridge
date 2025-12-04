import { createApp } from './app';

/**
 * Standalone Fastify server for local development
 * Run with: npm run dev
 */
async function startServer() {
  const app = createApp();

  const PORT = process.env.PORT ? parseInt(process.env.PORT) : 3000;
  const HOST = process.env.HOST || '0.0.0.0';

  try {
    await app.listen({ port: PORT, host: HOST });
    console.log('');
    console.log('🚀 Upload API Server Started');
    console.log('================================');
    console.log(`📍 URL: http://localhost:${PORT}`);
    console.log('');
    console.log('Available endpoints:');
    console.log(`  GET  /health`);
    console.log(`  POST /initiate`);
    console.log(`  GET  /status/:uploadId`);
    console.log('');
    console.log('Press Ctrl+C to stop');
    console.log('');
  } catch (err) {
    app.log.error(err);
    process.exit(1);
  }
}

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\n👋 Shutting down gracefully...');
  process.exit(0);
});

process.on('SIGTERM', () => {
  console.log('\n👋 Shutting down gracefully...');
  process.exit(0);
});

startServer();
