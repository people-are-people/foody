import 'dotenv/config';
import { PrismaClient } from '@prisma/client';
import { hashearPin } from '../src/lib/pins.js';

const [, , restauranteId, usuario, nombre, pin] = process.argv;

if (!restauranteId || !usuario || !nombre || !pin) {
  console.error('Uso: npm run staff:crear -- <restauranteId> <usuario> <nombre> <pin>');
  process.exit(1);
}

const prisma = new PrismaClient();

const staff = await prisma.staffCaja.create({
  data: {
    restauranteId,
    usuario,
    nombre,
    pinHash: hashearPin(pin),
  },
});

console.log('Staff creado. id:', staff.id);
await prisma.$disconnect();