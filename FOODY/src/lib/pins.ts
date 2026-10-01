import { scryptSync, randomBytes, timingSafeEqual } from 'node:crypto';

export function hashearPin(pin: string): string {
  const salt = randomBytes(16);
  const hash = scryptSync(pin, salt, 64);
  return `${salt.toString('hex')}:${hash.toString('hex')}`;
}

export function verificarPin(pin: string, hashGuardado: string): boolean {
  const [saltHex, hashHex] = hashGuardado.split(':');
  if (!saltHex || !hashHex) return false;

  const salt = Buffer.from(saltHex, 'hex');
  const hashEsperado = Buffer.from(hashHex, 'hex');
  const hashIngresado = scryptSync(pin, salt, 64);

  return hashEsperado.length === hashIngresado.length && timingSafeEqual(hashEsperado, hashIngresado);
}