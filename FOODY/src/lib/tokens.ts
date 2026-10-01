import { randomBytes } from 'node:crypto';

// Se usa como dueño_token de una cuenta: es lo único que impide que
// alguien adivine o fuerce el control de pedido de otra mesa.
// Nunca reemplazar por un contador ni por algo predecible.
export function generarToken(): string {
  return randomBytes(24).toString('base64url');
}
