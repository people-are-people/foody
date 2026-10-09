import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

const modificarParamsSchema = z.object({
  cuentaId: z.string().uuid(),
  pedidoId: z.string().uuid(),
});

class PedidoYaEnPreparacion extends Error {}

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

    app.post('/cuentas/:cuentaId/pedidos/:pedidoId/cancelar', async (request, reply) => {
    const { cuentaId, pedidoId } = modificarParamsSchema.parse(request.params);
    const token = request.headers.authorization?.replace('Bearer ', '');

    const pedido = await app.prisma.pedido.findFirst({
      where: { id: pedidoId, cuentaId },
      include: { cuenta: true },
    });
    if (!pedido || pedido.cuenta.estado !== 'abierta') {
      return reply.code(404).send({ error: 'pedido no encontrado o cuenta cerrada' });
    }
    if (pedido.cuenta.duenioToken !== token) {
      return reply.code(403).send({ error: 'solo quien hizo el pedido puede cancelarlo' });
    }
    if (pedido.estado === 'cancelado') {
      return reply.code(409).send({ error: 'el pedido ya estaba cancelado' });
    }

    try {
      const cancelado = await app.prisma.$transaction(async (tx) => {
        const guardia = await tx.pedido.updateMany({
          where: { id: pedidoId, estado: 'recibido' },
          data: { estado: 'cancelado' },
        });
        if (guardia.count === 0) throw new PedidoYaEnPreparacion();

        await tx.evento.create({
          data: {
            restauranteId: pedido.restauranteId,
            cuentaId,
            tipo: 'pedido_cancelado',
            payload: { pedido_id: pedidoId },
          },
        });

        return tx.pedido.findUniqueOrThrow({ where: { id: pedidoId } });
      });
      return reply.send(cancelado);
    } catch (err) {
      if (err instanceof PedidoYaEnPreparacion) {
        return reply
          .code(409)
          .send({ error: 'el pedido ya está en preparación y no se puede cancelar' });
      }
      throw err;
    }
  });
  // El cliente (dueño de la cuenta) reemplaza los platos de un pedido,
  // solo mientras siga en "recibido".
  app.put('/cuentas/:cuentaId/pedidos/:pedidoId', async (request, reply) => {
    const { cuentaId, pedidoId } = modificarParamsSchema.parse(request.params);
    const { items } = bodySchema.parse(request.body);
    const token = request.headers.authorization?.replace('Bearer ', '');

    const pedido = await app.prisma.pedido.findFirst({
      where: { id: pedidoId, cuentaId },
      include: { cuenta: true },
    });
    if (!pedido || pedido.cuenta.estado !== 'abierta') {
      return reply.code(404).send({ error: 'pedido no encontrado o cuenta cerrada' });
    }
    if (pedido.cuenta.duenioToken !== token) {
      return reply.code(403).send({ error: 'solo quien hizo el pedido puede modificarlo' });
    }
    if (pedido.estado !== 'recibido') {
      return reply
        .code(409)
        .send({ error: 'el pedido ya está en preparación y no se puede modificar' });
    }

    const idsMenu = [...new Set(items.map((i) => i.menu_item_id))];
    const menuItems = await app.prisma.menuItem.findMany({
      where: { id: { in: idsMenu }, restauranteId: pedido.restauranteId, disponible: true },
    });
    if (menuItems.length !== idsMenu.length) {
      return reply.code(400).send({ error: 'alguno de los platos ya no está disponible' });
    }
    const precios = new Map(menuItems.map((m) => [m.id, m.precio]));

    try {
      const actualizado = await app.prisma.$transaction(async (tx) => {
        // Candado: este UPDATE bloquea la fila y solo avanza si el pedido
        // TODAVÍA está en "recibido". Si cocina lo movió justo antes,
        // no encuentra nada y se cancela todo.
        const guardia = await tx.pedido.updateMany({
          where: { id: pedidoId, estado: 'recibido' },
          data: { estado: 'recibido' },
        });
        if (guardia.count === 0) throw new PedidoYaEnPreparacion();

        await tx.pedidoItem.deleteMany({ where: { pedidoId } });
        await tx.pedidoItem.createMany({
          data: items.map((i) => ({
            pedidoId,
            menuItemId: i.menu_item_id,
            cantidad: i.cantidad,
            notas: i.notas,
            precioUnitario: precios.get(i.menu_item_id)!,
          })),
        });
        await tx.evento.create({
          data: {
            restauranteId: pedido.restauranteId,
            cuentaId,
            tipo: 'pedido_modificado',
            payload: { pedido_id: pedidoId },
          },
        });

        return tx.pedido.findUniqueOrThrow({
          where: { id: pedidoId },
          include: { items: true },
        });
      });
      return reply.send(actualizado);
    } catch (err) {
      if (err instanceof PedidoYaEnPreparacion) {
        return reply
          .code(409)
          .send({ error: 'el pedido ya está en preparación y no se puede modificar' });
      }
      throw err;
    }
  });

  // La pantalla de cocina usa esto para saber QUÉ preparar: el evento del
  // outbox solo trae el pedido_id, no los items.
  app.get('/pedidos/:pedidoId', async (request, reply) => {
    const { pedidoId } = pedidoParamsSchema.parse(request.params);
    const pedido = await app.prisma.pedido.findUnique({
      where: { id: pedidoId },
      include: {
        items: { include: { menuItem: true } },
        cuenta: { select: { id: true, mesa: { select: { etiqueta: true } } } },
      },
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