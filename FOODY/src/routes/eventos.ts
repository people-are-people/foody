import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

const cuentaParamsSchema = z.object({ cuentaId: z.string().uuid() });
const querySchema = z.object({ desde: z.coerce.number().int().min(0).default(0) });

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
      eventos: eventos.map((e) => ({ ...e, id: Number(e.id) })),
      ultimo_id: eventos.length ? Number(eventos[eventos.length - 1].id) : desde,
    };
  });
}