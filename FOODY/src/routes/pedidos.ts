import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

const paramsSchema = z.object({ cuentaId: z.string().uuid() });
const bodySchema = z.object({
  items: z
    .array(
      z.object({
        menu_item_id: z.string().uuid(),
        cantidad: z.number().int().positive(),
        notas: z.string().optional(),
      }),
    )
    .min(1),
});

const pedidoParamsSchema = z.object({ pedidoId: z.string().uuid() });
const estadoBodySchema = z.object({ estado: z.enum(['en_preparacion', 'listo']) });

// Solo se puede avanzar el pedido hacia adelante, nunca saltear pasos
// ni retroceder. La clave del objeto es el estado ACTUAL requerido
// para poder pasar al estado indicado.
const transicionesValidas: Record<string, string> = {
  en_preparacion: 'recibido',
  listo: 'en_preparacion',
};

export default async function pedidosRoutes(app: FastifyInstance) {
  app.post('/cuentas/:cuentaId/pedidos', async (request, reply) => {
    const { cuentaId } = paramsSchema.parse(request.params);
    const { items } = bodySchema.parse(request.body);
    const token = request.headers.authorization?.replace('Bearer ', '');

    const cuenta = await app.prisma.cuenta.findUnique({ where: { id: cuentaId } });
    if (!cuenta || cuenta.estado !== 'abierta') {
      return reply.code(404).send({ error: 'cuenta no encontrada o cerrada' });
    }
    if (cuenta.duenioToken !== token) {
      return reply.code(403).send({ error: 'otro comensal ya está pidiendo por esta mesa' });
    }

    const menuItems = await app.prisma.menuItem.findMany({
      where: { id: { in: items.map((i) => i.menu_item_id) } },
    });
    const precios = new Map(menuItems.map((m) => [m.id, m.precio]));

    const pedido = await app.prisma.$transaction(async (tx) => {
      const nuevoPedido = await tx.pedido.create({
        data: {
          restauranteId: cuenta.restauranteId,
          cuentaId: cuenta.id,
          items: {
            create: items.map((i) => ({
              menuItemId: i.menu_item_id,
              cantidad: i.cantidad,
              notas: i.notas,
              precioUnitario: precios.get(i.menu_item_id) ?? 0,
            })),
          },
        },
        include: { items: true },
      });

      await tx.evento.create({
        data: {
          restauranteId: cuenta.restauranteId,
          cuentaId: cuenta.id,
          tipo: 'pedido_recibido',
          payload: { pedido_id: nuevoPedido.id },
        },
      });

      return nuevoPedido;
    });

    return reply.code(201).send(pedido);
  });

  // La pantalla de cocina usa esto para saber QUÉ preparar: el evento del
  // outbox solo trae el pedido_id, no los items.
  app.get('/pedidos/:pedidoId', async (request, reply) => {
    const { pedidoId } = pedidoParamsSchema.parse(request.params);
    const pedido = await app.prisma.pedido.findUnique({
      where: { id: pedidoId },
      include: { items: { include: { menuItem: true } }, cuenta: { include: { mesa: true } } },
    });
    if (!pedido) return reply.code(404).send({ error: 'pedido no encontrado' });
    return pedido;
  });

  // Cocina usa esto para avanzar el pedido. Cada transición genera su
  // propio evento en el outbox, así la app del cliente también se entera.
  app.patch('/pedidos/:pedidoId/estado', async (request, reply) => {
    const { pedidoId } = pedidoParamsSchema.parse(request.params);
    const { estado } = estadoBodySchema.parse(request.body);

    const pedido = await app.prisma.pedido.findUnique({
      where: { id: pedidoId },
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

    const actualizado = await app.prisma.$transaction(async (tx) => {
      const pedidoActualizado = await tx.pedido.update({
        where: { id: pedidoId },
        data: { estado },
      });

      await tx.evento.create({
        data: {
          restauranteId: pedido.restauranteId,
          cuentaId: pedido.cuentaId,
          tipo: `pedido_${estado}`,
          payload: { pedido_id: pedidoId },
        },
      });

      return pedidoActualizado;
    });

    return reply.send(actualizado);
  });
}