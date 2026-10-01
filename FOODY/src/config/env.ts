import 'dotenv/config';
import { z } from 'zod';

const envSchema = z.object({
  DATABASE_URL: z.string().min(1),
  PORT: z.coerce.number().default(3000),
  RESTAURANTE_ID: z
    .string()
    .min(1, 'Cada instancia debe declarar a qué restaurante pertenece'),
  JWT_SECRET: z
    .string()
    .min(16, 'Necesita al menos 16 caracteres para firmar los tokens de staff'),
});

export const env = envSchema.parse(process.env);
