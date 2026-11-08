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
const modificarParamsSchema = z.object({
  cuentaId: z.string().uuid(),
  pedidoId: z.string().uuid(),
});

class PedidoYaEnPreparacion extends Error {}

type ItemsPedido = z.infer<typeof bodySchema>['items'];

// Verifica que todos los platos existan, sean de este restaurante y estén
// disponibles, y devuelve su precio actual. Devuelve null si alguno no
// cumple. Lo usan crear y modificar, para que validen exactamente lo mismo.
async function precioDePlatos(app: FastifyInstance, restauranteId: string, items: ItemsPedido) {
  const ids = [...new Set(items.map((i) => i.menu_item_id))];
  const platos = await app.prisma.menuItem.findMany({
    where: { id: { in: ids }, restauranteId, disponible: true },
  });
  if (platos.length !== ids.length) return null;
  return new Map(platos.map((p) => [p.id, p.precio]));
}

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

    const precios = await precioDePlatos(app, cuenta.restauranteId, items);
    if (!precios) {
      return reply.code(400).send({ error: 'alguno de los platos ya no está disponible' });
    }

    // Pedido + items + evento se crean en UNA sola transacción: así el
    // outbox nunca queda desincronizado del dato real (patrón outbox).
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
              precioUnitario: precios.get(i.menu_item_id)!,
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

  // Detalle de un pedido. De la cuenta solo se devuelve el id y la mesa:
  // el duenioToken no puede salir por una ruta sin autenticación.
  app.get('/pedidos/:pedidoId', async (request, reply) => {
    const { pedidoId } = pedidoParamsSchema.parse(request.params);
    const pedido = await app.prisma.pedido.findUnique({
      where: { id: pedidoId },
      include: {
        items: {
          include: {
            menuItem: { select: { id: true, nombre: true, descripcion: true } },
          },
        },
        cuenta: { select: { id: true, mesa: { select: { etiqueta: true } } } },
      },
    });
    if (!pedido) return reply.code(404).send({ error: 'pedido no encontrado' });
    return pedido;
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

    const precios = await precioDePlatos(app, pedido.restauranteId, items);
    if (!precios) {
      return reply.code(400).send({ error: 'alguno de los platos ya no está disponible' });
    }

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
}