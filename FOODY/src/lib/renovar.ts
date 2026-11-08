import type { FastifyInstance } from 'fastify';
import { requireRol } from './auth.js';
import { firmarTokenStaff } from './jwt.js';

// Renueva la sesión de staff sin volver a pedir el PIN. La app la llama sola
// cuando el token pasó la mitad de su vida. Solo funciona con un token
// vigente: uno vencido ya no se puede renovar.
export function registrarRenovacion(app: FastifyInstance, rol: 'caja' | 'cocina') {
  app.post(
    `/restaurantes/:restauranteId/${rol}/renovar`,
    { preHandler: requireRol(rol) },
    async (request, reply) => {
      const staff = request.staff!;

      // Se vuelve a verificar contra la base: si el usuario se borró o
      // cambió de rol desde que inició sesión, no se renueva y el token
      // actual muere cuando venza.
      const vigente = await app.prisma.staffCaja.findFirst({
        where: { id: staff.staffId, restauranteId: staff.restauranteId, rol },
      });
      if (!vigente) {
        return reply.code(401).send({ error: 'el usuario ya no está habilitado' });
      }

      const token = firmarTokenStaff({
        staffId: vigente.id,
        restauranteId: vigente.restauranteId,
        rol: vigente.rol,
      });
      return reply.send({ token });
    },
  );
}