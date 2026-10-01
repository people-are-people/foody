import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { generarToken } from '../lib/tokens.js';

const paramsSchema = z.object({
  restauranteId: z.string().uuid(),
  mesaId: z.string().uuid(),
});

export default async function mesasRoutes(app: FastifyInstance) {
  app.post('/restaurantes/:restauranteId/mesas/:mesaId/unirse', async (request, reply) => {
    const { restauranteId, mesaId } = paramsSchema.parse(request.params);

    const cuentaAbierta = await app.prisma.cuenta.findFirst({
      where: { mesaId, estado: 'abierta' },
    });

    if (cuentaAbierta) {
      // Ya hay alguien pidiendo por esta mesa: el que se une ahora
      // queda en modo espectador (ve menú y estado, no puede pedir).
      return reply.send({
        cuenta_id: cuentaAbierta.id,
        rol: 'espectador',
        estado_cuenta: cuentaAbierta.estado,
      });
    }

    try {
      const cuenta = await app.prisma.cuenta.create({
        data: { restauranteId, mesaId, duenioToken: generarToken() },
      });

      return reply.send({
        cuenta_id: cuenta.id,
        rol: 'dueño',
        sesion_token: cuenta.duenioToken,
        estado_cuenta: cuenta.estado,
      });
    } catch (err: unknown) {
      // Dos celulares escanearon el QR en el mismo instante y ambos
      // intentaron crear la cuenta. El índice único de la base
      // (ver migración) rechaza al segundo con error P2002 — ese
      // segundo pasa a espectador de la cuenta que ganó la carrera.
      const esConflicto = (err as { code?: string }).code === 'P2002';
      if (!esConflicto) throw err;

      const cuentaGanadora = await app.prisma.cuenta.findFirstOrThrow({
        where: { mesaId, estado: 'abierta' },
      });
      return reply.send({
        cuenta_id: cuentaGanadora.id,
        rol: 'espectador',
        estado_cuenta: cuentaGanadora.estado,
      });
    }
  });
}
