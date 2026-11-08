import 'dotenv/config';
import { PrismaClient } from '@prisma/client';
import { hashearPin } from '../src/lib/pins.js';

const [, , restauranteId, usuario, nombre, pin, rol = 'caja'] = process.argv;

if (!restauranteId || !usuario || !nombre || !pin || !['caja', 'cocina'].includes(rol)) {
  console.error(
    'Uso: npm run staff:crear -- <restauranteId> <usuario> <nombre> <pin> [caja|cocina]',
  );
  process.exit(1);
}

const prisma = new PrismaClient();

const staff = await prisma.staffCaja.create({
  data: {
    restauranteId,
    usuario,
    nombre,
    pinHash: hashearPin(pin),
    rol,
  },
});

console.log(`Staff creado (${rol}). id:`, staff.id);
await prisma.$disconnect();