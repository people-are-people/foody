import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

const cuentaParamsSchema = z.object({ cuentaId: z.string().uuid() });
const restauranteParamsSchema = z.object({ restauranteId: z.string().uuid() });
const querySchema = z.object({ desde: z.coerce.number().int().min(0).default(0) });

// El id de Evento es BigInt en Postgres; Fastify no serializa BigInt a
// JSON por default. A esta escala nunca se acerca al límite seguro de
// un number de JS, así que lo convertimos sin problema.
function serializar(evento: { id: bigint; [key: string]: unknown }) {
  return { ...evento, id: Number(evento.id) };
}

export default async function eventosRoutes(app: FastifyInstance) {
  // La app del cliente pregunta: "¿qué pasó en MI cuenta desde X?"
  app.get('/cuentas/:cuentaId/eventos', async (request) => {
    const { cuentaId } = cuentaParamsSchema.parse(request.params);
    const { desde } = querySchema.parse(request.query);

    const eventos = await app.prisma.evento.findMany({
      where: { cuentaId, id: { gt: desde } },
      orderBy: { id: 'asc' },
    });

    return {
      eventos: eventos.map(serializar),
      ultimo_id: eventos.length ? Number(eventos[eventos.length - 1].id) : desde,
    };
  });

  // La pantalla de cocina pregunta: "¿qué pasó en TODO el restaurante desde X?"
  app.get('/restaurantes/:restauranteId/cocina/eventos', async (request) => {
    const { restauranteId } = restauranteParamsSchema.parse(request.params);
    const { desde } = querySchema.parse(request.query);

    const eventos = await app.prisma.evento.findMany({
      where: { restauranteId, id: { gt: desde } },
      orderBy: { id: 'asc' },
    });

    return {
      eventos: eventos.map(serializar),
      ultimo_id: eventos.length ? Number(eventos[eventos.length - 1].id) : desde,
    };
  });
}
