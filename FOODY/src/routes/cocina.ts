import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireRol } from '../lib/auth.js';
import { firmarTokenStaff } from '../lib/jwt.js';
import { verificarPin } from '../lib/pins.js';
import { registrarRenovacion } from '../lib/renovar.js';

const restauranteParamsSchema = z.object({ restauranteId: z.string().uuid() });
const pedidoParamsSchema = z.object({
  restauranteId: z.string().uuid(),
  pedidoId: z.string().uuid(),
});
const loginBodySchema = z.object({ usuario: z.string().min(1), pin: z.string().min(1) });
const querySchema = z.object({ desde: z.coerce.number().int().min(0).default(0) });
const estadoBodySchema = z.object({ estado: z.enum(['en_preparacion', 'listo']) });

// Solo se avanza hacia adelante. La clave es el estado al que se quiere
// pasar; el valor, el estado ACTUAL que el pedido debe tener para poder.
const transicionesValidas: Record<string, string> = {
  en_preparacion: 'recibido',
  listo: 'en_preparacion',
};


class CambioConcurrente extends Error {}

export default async function cocinaRoutes(app: FastifyInstance) {
  const soloCocina = requireRol('cocina');
  registrarRenovacion(app, 'cocina');
  app.post('/restaurantes/:restauranteId/cocina/login', async (request, reply) => {
    const { restauranteId } = restauranteParamsSchema.parse(request.params);
    const { usuario, pin } = loginBodySchema.parse(request.body);

    const staff = await app.prisma.staffCaja.findFirst({
      where: { restauranteId, usuario, rol: 'cocina' },
    });
    if (!staff || !verificarPin(pin, staff.pinHash)) {
      return reply.code(401).send({ error: 'usuario o PIN incorrecto' });
    }

    const token = firmarTokenStaff({ staffId: staff.id, restauranteId, rol: staff.rol });
    return reply.send({ token });
  });

  // La pantalla de cocina pregunta: "¿qué pasó en TODO el restaurante desde X?"
  app.get(
    '/restaurantes/:restauranteId/cocina/eventos',
    { preHandler: soloCocina },
    async (request) => {
      const { restauranteId } = restauranteParamsSchema.parse(request.params);
      const { desde } = querySchema.parse(request.query);

      const eventos = await app.prisma.evento.findMany({
        where: { restauranteId, id: { gt: desde } },
        orderBy: { id: 'asc' },
      });

      return {
        eventos: eventos.map((e) => ({ ...e, id: Number(e.id) })),
        ultimo_id: eventos.length ? Number(eventos[eventos.length - 1].id) : desde,
      };
    },
  );

  // Foto del momento para arrancar la pantalla de cocina: solo los pedidos
  // activos y desde qué evento seguir, sin releer todo el historial.
  app.get(
    '/restaurantes/:restauranteId/cocina/pedidos',
    { preHandler: soloCocina },
    async (request) => {
      const { restauranteId } = restauranteParamsSchema.parse(request.params);

      // Primero el último evento y después los pedidos: si entra algo en el
      // medio, la app lo vuelve a recibir como evento y reprocesarlo es inofensivo.
      const ultimo = await app.prisma.evento.aggregate({
        where: { restauranteId },
        _max: { id: true },
      });

      const pedidos = await app.prisma.pedido.findMany({
        where: {
          restauranteId,
          estado: { in: ['recibido', 'en_preparacion'] },
          cuenta: { estado: 'abierta' },
        },
        orderBy: { creadoEn: 'asc' },
        select: {
          id: true,
          estado: true,
          creadoEn: true,
          cuenta: { select: { id: true, mesa: { select: { etiqueta: true } } } },
          items: {
            select: {
              id: true,
              cantidad: true,
              notas: true,
              menuItem: { select: { nombre: true } },
            },
          },
        },
      });

      return { ultimo_evento_id: Number(ultimo._max.id ?? 0), pedidos };
    },
  );

  // Cocina avanza el pedido. Cada transición genera su evento en el outbox.
  app.patch(
    '/restaurantes/:restauranteId/cocina/pedidos/:pedidoId/estado',
    { preHandler: soloCocina },
    async (request, reply) => {
      const { restauranteId, pedidoId } = pedidoParamsSchema.parse(request.params);
      const { estado } = estadoBodySchema.parse(request.body);

      const pedido = await app.prisma.pedido.findFirst({
        where: { id: pedidoId, restauranteId },
        include: { cuenta: true },
      });
      if (!pedido) return reply.code(404).send({ error: 'pedido no encontrado' });

      if (pedido.cuenta.estado !== 'abierta') {
        return reply.code(409).send({ error: 'la cuenta de este pedido ya está cerrada' });
      }

      const estadoRequerido = transicionesValidas[estado];
      if (pedido.estado !== estadoRequerido) {
        return reply.code(409).send({
          error: `no se puede pasar de "${pedido.estado}" a "${estado}"`,
        });
      }

      try {
        const actualizado = await app.prisma.$transaction(async (tx) => {
          // Candado: solo avanza si el pedido TODAVÍA está en el estado que
          // leímos. Si el cliente lo canceló en el medio, no encuentra nada.
          const guardia = await tx.pedido.updateMany({
            where: { id: pedidoId, estado: estadoRequerido },
            data: { estado },
          });
          if (guardia.count === 0) throw new CambioConcurrente();

          await tx.evento.create({
            data: {
              restauranteId,
              cuentaId: pedido.cuentaId,
              tipo: `pedido_${estado}`,
              payload: { pedido_id: pedidoId },
            },
          });

          return tx.pedido.findUniqueOrThrow({ where: { id: pedidoId } });
        });
        return reply.send(actualizado);
      } catch (err) {
        if (err instanceof CambioConcurrente) {
          return reply.code(409).send({
            error: 'el pedido cambió de estado justo antes (por ejemplo, el cliente lo canceló)',
          });
        }
        throw err;
      }
    },
  );
}