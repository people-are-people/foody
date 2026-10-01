import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';

export interface StaffTokenPayload {
  staffId: string;
  restauranteId: string;
  rol: string;
}

export function firmarTokenStaff(payload: StaffTokenPayload): string {
  return jwt.sign(payload, env.JWT_SECRET, { expiresIn: '12h' });
}

export function verificarTokenStaff(token: string): StaffTokenPayload {
  return jwt.verify(token, env.JWT_SECRET) as StaffTokenPayload;
}