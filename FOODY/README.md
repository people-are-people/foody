# Backend — Sistema de pedidos de restaurante

Node.js + TypeScript + Fastify + Prisma + PostgreSQL.

## Poner en marcha (local)

```bash
cp .env.example .env
docker compose up -d          # levanta Postgres en localhost:5432
npm install
npx prisma migrate dev --name init
npm run dev                   # http://localhost:3000
```

## Estructura

```
src/
  config/env.ts     valida las variables de entorno
  plugins/prisma.ts decora Fastify con el cliente de Prisma
  lib/tokens.ts      generador seguro de dueño_token
  routes/
    mesas.ts         unirse a una mesa (rol dueño/espectador)
    pedidos.ts        enviar una ronda de pedido (patrón outbox)
    eventos.ts        consultar el outbox (app y cocina)
    caja.ts            listar, cerrar y liberar cuentas
  app.ts             arma la instancia de Fastify
  server.ts          arranca el servidor
prisma/schema.prisma  modelo de datos
```

## Pendiente antes de producción

- **Índice único parcial**: Prisma (sin preview features) no genera un
  `UNIQUE INDEX ... WHERE estado = 'abierta'`. Después de la primera
  migración, agregar a mano en el SQL generado:
  ```sql
  CREATE UNIQUE INDEX una_cuenta_abierta_por_mesa
    ON cuentas (mesa_id) WHERE estado = 'abierta';
  ```
  Sin esto, el manejo de la condición de carrera en `mesas.ts` (dos
  celulares escaneando al mismo tiempo) no está garantizado a nivel base
  de datos, solo a nivel aplicación.
- **Autenticación de caja**: las rutas de `caja.ts` todavía no verifican
  login de staff (usuario/PIN). Están abiertas a propósito para poder
  probar el flujo completo primero.
- **Precio como Decimal**: Prisma devuelve `Decimal` para el campo
  `precio`; falta decidir cómo se serializa en las respuestas JSON
  (como string o como number) antes de que la app dependa de ese formato.
- Sin tests todavía — el primero que conviene escribir es el de
  reconexión del endpoint de eventos (`GET /eventos?desde=X`), que es la
  pieza de mayor riesgo del sistema.
