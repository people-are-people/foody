import Fastify from 'fastify';
import cors from '@fastify/cors';
import { ZodError } from 'zod';
import prismaPlugin from './plugins/prisma.js';
import mesasRoutes from './routes/mesas.js';
import menuRoutes from './routes/menu.js';
import pedidosRoutes from './routes/pedidos.js';
import eventosRoutes from './routes/eventos.js';
import cajaRoutes from './routes/caja.js';
import cocinaRoutes from './routes/cocina.js';
import { env } from './config/env.js';

export async function build() {
  const app = Fastify({ logger: true });

  // Todos los errores salen con la misma forma: { error: "mensaje" }.
  app.setErrorHandler((error, request, reply) => {
    // Datos mal formados (un id que no es UUID, un body incompleto...):
    // es un problema de quien llama, no del servidor.
    if (error instanceof ZodError) {
      return reply.code(400).send({
        error: 'datos inválidos',
        detalles: error.issues.map((i) => ({
          campo: i.path.join('.'),
          mensaje: i.message,
        })),
      });
    }

    // Errores de Fastify con código propio (JSON mal formado, body vacío...).
    if (error.statusCode && error.statusCode < 500) {
      return reply.code(error.statusCode).send({ error: error.message });
    }

    // Cualquier otra cosa es un error nuestro. El detalle (que puede traer
    // consultas SQL o rutas de archivos) queda solo en el log del servidor.
    request.log.error(error);
    return reply.code(500).send({ error: 'error interno del servidor' });
  });

  app.setNotFoundHandler((_request, reply) => {
    return reply.code(404).send({ error: 'ruta no encontrada' });
  });

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
  await app.register(menuRoutes, { prefix: '/api/v1' });
  await app.register(pedidosRoutes, { prefix: '/api/v1' });
  await app.register(eventosRoutes, { prefix: '/api/v1' });
  await app.register(cajaRoutes, { prefix: '/api/v1' });
  await app.register(cocinaRoutes, { prefix: '/api/v1' });

  return app;
}