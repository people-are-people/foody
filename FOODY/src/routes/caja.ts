import type { Prisma } from '@prisma/client';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireRol } from '../lib/auth.js';
import { firmarTokenStaff } from '../lib/jwt.js';
import { verificarPin } from '../lib/pins.js';
import { registrarRenovacion } from '../lib/renovar.js';

const restauranteParamsSchema = z.object({ restauranteId: z.string().uuid() });
const cuentaParamsSchema = z.object({
  restauranteId: z.string().uuid(),
  cuentaId: z.string().uuid(),
});
const mesaParamsSchema = z.object({
  restauranteId: z.string().uuid(),
  mesaId: z.string().uuid(),
});
const loginBodySchema = z.object({ usuario: z.string().min(1), pin: z.string().min(1) });

// Campos de la cuenta que se pueden mostrar. A propósito NO incluye
// duenioToken: con ese token se puede pedir en nombre del cliente, así
// que no tiene que salir de ninguna ruta, ni siquiera para el staff.
const cuentaSinToken = {
  id: true,
  restauranteId: true,
  mesaId: true,
  estado: true,
  abiertaEn: true,
  cerradaEn: true,
} as const;

  

// Única forma de cerrar una cuenta: el cierre y su evento van en la misma
// transacción. Devuelve false si la cuenta ya no estaba abierta (candado:
// si caja la cerró en el mismo instante, no se genera un segundo evento).
async function cerrarCuenta(
  tx: Prisma.TransactionClient,
  restauranteId: string,
  cuentaId: string,
): Promise<boolean> {
  const cierre = await tx.cuenta.updateMany({
    where: { id: cuentaId, estado: 'abierta' },
    data: { estado: 'cerrada', cerradaEn: new Date() },
  });
  if (cierre.count === 0) return false;

  await tx.evento.create({
    data: {
      restauranteId,
      cuentaId,
      tipo: 'cuenta_cerrada',
      // Acá se va a sumar el detalle para facturación una vez que
      // se defina ese formato — tema que quedó pendiente.
      payload: { cuenta_id: cuentaId },
    },
  });
  return true;
}

export default async function cajaRoutes(app: FastifyInstance) {
  const soloCaja = requireRol('caja');
  registrarRenovacion(app, 'caja');
  
  app.post('/restaurantes/:restauranteId/caja/login', async (request, reply) => {
    const { restauranteId } = restauranteParamsSchema.parse(request.params);
    const { usuario, pin } = loginBodySchema.parse(request.body);

    const staff = await app.prisma.staffCaja.findFirst({
      where: { restauranteId, usuario, rol: 'caja' },
    });
    if (!staff || !verificarPin(pin, staff.pinHash)) {
      return reply.code(401).send({ error: 'usuario o PIN incorrecto' });
    }

    const token = firmarTokenStaff({ staffId: staff.id, restauranteId, rol: staff.rol });
    return reply.send({ token });
  });

  app.get(
    '/restaurantes/:restauranteId/caja/cuentas-abiertas',
    { preHandler: soloCaja },
    async (request) => {
      const { restauranteId } = restauranteParamsSchema.parse(request.params);
      return app.prisma.cuenta.findMany({
        where: { restauranteId, estado: 'abierta' },
        select: {
          ...cuentaSinToken,
          mesa: true,
          pedidos: {
            where: { estado: { not: 'cancelado' } },
            include: { items: true },
          },
        },
      });
    },
  );

  app.get(
    '/restaurantes/:restauranteId/caja/cuentas/:cuentaId',
    { preHandler: soloCaja },
    async (request, reply) => {
      const { cuentaId } = cuentaParamsSchema.parse(request.params);
      const cuenta = await app.prisma.cuenta.findUnique({
        where: { id: cuentaId },
        select: {
          ...cuentaSinToken,
          mesa: true,
          pedidos: {
            where: { estado: { not: 'cancelado' } },
            include: { items: { include: { menuItem: true } } },
          },
        },
      });
      if (!cuenta) return reply.code(404).send({ error: 'cuenta no encontrada' });
      return cuenta;
    },
  );

  app.post(
    '/restaurantes/:restauranteId/caja/cuentas/:cuentaId/cerrar',
    { preHandler: soloCaja },
    async (request, reply) => {
      const { restauranteId, cuentaId } = cuentaParamsSchema.parse(request.params);

      const cuenta = await app.prisma.cuenta.findFirst({
        where: { id: cuentaId, restauranteId },
        select: { estado: true },
      });
      if (!cuenta) return reply.code(404).send({ error: 'cuenta no encontrada' });
      if (cuenta.estado !== 'abierta') {
        return reply.code(409).send({ error: 'la cuenta ya estaba cerrada' });
      }

      const cerrada = await app.prisma.$transaction((tx) =>
        cerrarCuenta(tx, restauranteId, cuentaId),
      );
      if (!cerrada) {
        return reply.code(409).send({ error: 'la cuenta ya estaba cerrada' });
      }

      return reply.send(
        await app.prisma.cuenta.findUniqueOrThrow({
          where: { id: cuentaId },
          select: cuentaSinToken,
        }),
      );
    },
  );

  app.post(
    '/restaurantes/:restauranteId/caja/mesas/:mesaId/liberar',
    { preHandler: soloCaja },
    async (request, reply) => {
      const { restauranteId, mesaId } = mesaParamsSchema.parse(request.params);

      const liberada = await app.prisma.$transaction(async (tx) => {
        const cuenta = await tx.cuenta.findFirst({
          where: { mesaId, restauranteId, estado: 'abierta' },
          select: { id: true },
        });
        if (!cuenta) return false;
        return cerrarCuenta(tx, restauranteId, cuenta.id);
      });

      if (!liberada) {
        return reply.code(404).send({ error: 'no hay ninguna cuenta abierta en esa mesa' });
      }
      return reply.send({ liberada: true });
    },
  );
}