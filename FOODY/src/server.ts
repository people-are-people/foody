import { build } from './app.js';
import { env } from './config/env.js';

async function start() {
  const app = await build();
  try {
    await app.listen({ port: env.PORT, host: '0.0.0.0' });
  } catch (err) {
    app.log.error(err);
    process.exit(1);
  }
}

start();
