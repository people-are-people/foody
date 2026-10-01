import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

const paramsSchema = z.object({ restauranteId: z.string().uuid() });

export default async function menuRoutes(app: FastifyInstance) {
  // Público: no requiere sesion_token, tanto el dueño como los
  // espectadores de una mesa necesitan poder ver el menú.
  // Solo devuelve items disponibles — lo que está pausado/agotado
  // no debería aparecer para pedir.
  app.get('/restaurantes/:restauranteId/menu', async (request) => {
    const { restauranteId } = paramsSchema.parse(request.params);
    return app.prisma.menuItem.findMany({
      where: { restauranteId, disponible: true },
      orderBy: { nombre: 'asc' },
    });
  });
}