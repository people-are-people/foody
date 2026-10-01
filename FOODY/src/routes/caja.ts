import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { verificarPin } from '../lib/pins.js';
import { firmarTokenStaff, verificarTokenStaff } from '../lib/jwt.js';

const restauranteParamsSchema = z.object({ restauranteId: z.string().uuid() });
const cuentaParamsSchema = z.object({ restauranteId: z.string().uuid(), cuentaId: z.string().uuid() });
const mesaParamsSchema = z.object({ restauranteId: z.string().uuid(), mesaId: z.string().uuid() });
const loginBodySchema = z.object({ usuario: z.string().min(1), pin: z.string().min(1) });

async function requireStaffAuth(request: FastifyRequest, reply: FastifyReply) {
  const token = request.headers.authorization?.replace('Bearer ', '');
  if (!token) {
    return reply.code(401).send({ error: 'falta el token de staff' });
  }

  try {
    const payload = verificarTokenStaff(token);
    const { restauranteId } = request.params as { restauranteId?: string };
    if (restauranteId && payload.restauranteId !== restauranteId) {
      return reply.code(403).send({ error: 'el token no corresponde a este restaurante' });
    }
  } catch {
    return reply.code(401).send({ error: 'token inválido o vencido' });
  }
}

export default async function cajaRoutes(app: FastifyInstance) {
  app.post('/restaurantes/:restauranteId/caja/login', async (request, reply) => {
    const { restauranteId } = restauranteParamsSchema.parse(request.params);
    const { usuario, pin } = loginBodySchema.parse(request.body);

    const staff = await app.prisma.staffCaja.findFirst({ where: { restauranteId, usuario } });
    if (!staff || !verificarPin(pin, staff.pinHash)) {
      return reply.code(401).send({ error: 'usuario o PIN incorrecto' });
    }

    const token = firmarTokenStaff({ staffId: staff.id, restauranteId, rol: staff.rol });
    return reply.send({ token });
  });

  app.get(
    '/restaurantes/:restauranteId/caja/cuentas-abiertas',
    { preHandler: requireStaffAuth },
    async (request) => {
      const { restauranteId } = restauranteParamsSchema.parse(request.params);
      return app.prisma.cuenta.findMany({
        where: { restauranteId, estado: 'abierta' },
        include: { mesa: true, pedidos: { include: { items: true } } },
      });
    },
  );

  app.get(
    '/restaurantes/:restauranteId/caja/cuentas/:cuentaId',
    { preHandler: requireStaffAuth },
    async (request, reply) => {
      const { cuentaId } = cuentaParamsSchema.parse(request.params);
      const cuenta = await app.prisma.cuenta.findUnique({
        where: { id: cuentaId },
        include: { mesa: true, pedidos: { include: { items: { include: { menuItem: true } } } } },
      });
      if (!cuenta) return reply.code(404).send({ error: 'cuenta no encontrada' });
      return cuenta;
    },
  );

  app.post(
    '/restaurantes/:restauranteId/caja/cuentas/:cuentaId/cerrar',
    { preHandler: requireStaffAuth },
    async (request) => {
      const { cuentaId } = cuentaParamsSchema.parse(request.params);
      const cuenta = await app.prisma.cuenta.update({
        where: { id: cuentaId },
        data: { estado: 'cerrada', cerradaEn: new Date() },
      });

      await app.prisma.evento.create({
        data: {
          restauranteId: cuenta.restauranteId,
          cuentaId: cuenta.id,
          tipo: 'cuenta_cerrada',
          payload: { cuenta_id: cuenta.id },
        },
      });

      return cuenta;
    },
  );

  app.post(
    '/restaurantes/:restauranteId/caja/mesas/:mesaId/liberar',
    { preHandler: requireStaffAuth },
    async (request, reply) => {
      const { mesaId } = mesaParamsSchema.parse(request.params);
      const resultado = await app.prisma.cuenta.updateMany({
        where: { mesaId, estado: 'abierta' },
        data: { estado: 'cerrada', cerradaEn: new Date() },
      });

      if (resultado.count === 0) {
        return reply.code(404).send({ error: 'no hay ninguna cuenta abierta en esa mesa' });
      }

      return reply.send({ liberada: true });
    },
  );
}