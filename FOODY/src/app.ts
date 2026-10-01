import Fastify from 'fastify';
import cors from '@fastify/cors';
import prismaPlugin from './plugins/prisma.js';
import mesasRoutes from './routes/mesas.js';
import pedidosRoutes from './routes/pedidos.js';
import eventosRoutes from './routes/eventos.js';
import cajaRoutes from './routes/caja.js';
import { env } from './config/env.js';
import menuRoutes from './routes/menu.js';

export async function build() {
  const app = Fastify({ logger: true });

  await app.register(cors, { origin: true });
  await app.register(prismaPlugin);

  // Esta instancia sirve a un único restaurante (ver decisión de
  // infraestructura: una instancia independiente por restaurante).
  // Cualquier request que traiga un restauranteId distinto en la URL
  // se rechaza acá, antes de llegar a la ruta.
  app.addHook('preHandler', async (request, reply) => {
    const { restauranteId } = request.params as { restauranteId?: string };
    if (restauranteId && restauranteId !== env.RESTAURANTE_ID) {
      return reply.code(403).send({ error: 'esta instancia no atiende a ese restaurante' });
    }
  });

  await app.register(mesasRoutes, { prefix: '/api/v1' });
  await app.register(pedidosRoutes, { prefix: '/api/v1' });
  await app.register(eventosRoutes, { prefix: '/api/v1' });
  await app.register(cajaRoutes, { prefix: '/api/v1' });
  await app.register(menuRoutes, { prefix: '/api/v1' });

  return app;
}