import type { FastifyReply, FastifyRequest } from 'fastify';
import { env } from '../config/env.js';
import { verificarTokenStaff, type StaffTokenPayload } from './jwt.js';

declare module 'fastify' {
  interface FastifyRequest {
    // Quién hace el pedido, ya verificado por requireRol.
    // Solo existe en las rutas de staff.
    staff?: StaffTokenPayload;
  }
}

// Protege una ruta para que solo entre staff con el rol indicado:
// "caja" para el panel de caja, "cocina" para la pantalla de cocina.
export function requireRol(rol: 'caja' | 'cocina') {
  return async function (request: FastifyRequest, reply: FastifyReply) {
    const token = request.headers.authorization?.replace('Bearer ', '');
    if (!token) {
      return reply.code(401).send({ error: 'falta el token de staff' });
    }

    try {
      const payload = verificarTokenStaff(token);

      if (payload.restauranteId !== env.RESTAURANTE_ID) {
        return reply.code(403).send({ error: 'el token no corresponde a este restaurante' });
      }
      if (payload.rol !== rol) {
        return reply.code(403).send({ error: 'tu usuario no tiene permiso para esta acción' });
      }

      request.staff = payload;
    } catch {
      return reply.code(401).send({ error: 'token inválido o vencido' });
    }
  };
}