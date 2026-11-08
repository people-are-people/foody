# Contrato de API — Sistema de pedidos de restaurante

Refleja el backend tal como está construido hoy (actualizado el 15/10/2026).
Las inconsistencias y huecos que se conocen están al final, en **Pendientes**.

## Convenciones

- **Base**: todas las rutas cuelgan de `/api/v1` (ej: `http://localhost:3000/api/v1`).
- **Formato**: JSON en request y response. Fechas en ISO 8601 (UTC).
- **Una instancia = un restaurante.** Toda ruta que lleva `{restauranteId}` en la URL responde `403` si ese id no coincide con el `RESTAURANTE_ID` de la instancia.
- **Ids**: UUID. Un id mal formado responde `400` (ver Errores).
- **Nombres de campos**: los objetos que salen de la base conservan el camelCase de Prisma (`restauranteId`, `creadoEn`, `precioUnitario`, `menuItem`). Los que arma el backend a mano usan snake_case (`cuenta_id`, `sesion_token`, `ultimo_id`, `pedido_id`).
- **Importes** (`precio`, `precioUnitario`): llegan como **string** (`"12.50"`).
- **Id de los eventos**: número.

## Autenticación

| Zona | Cómo se autentica | Rutas |
|---|---|---|
| Cliente, escritura | `Authorization: Bearer <sesion_token>` que entrega `unirse` (solo el dueño de la cuenta lo tiene) | crear, modificar y cancelar pedidos |
| Cliente, lectura | sin autenticación | unirse, menú, detalle de pedido, eventos de la cuenta |
| Cocina | `Authorization: Bearer <token>` con rol `cocina` | `/cocina/*`, salvo el login |
| Caja | `Authorization: Bearer <token>` con rol `caja` | `/caja/*`, salvo el login |

- El token de staff dura **12 horas** y lleva el usuario, el restaurante y el rol. Se renueva antes de que venza con `POST .../cocina/renovar` o `POST .../caja/renovar`, sin volver a pedir el PIN: la app de cocina lo hace sola al pasar la mitad de su vida. Un token ya vencido no se puede renovar.
- `401`: falta el token, o es inválido o está vencido.
- `403`: el token es de otro restaurante o de otro rol (un token de caja no sirve en cocina, ni al revés).
- No hay un endpoint para crear usuarios de staff. Se crean con el script `npm run staff:crear -- <restauranteId> <usuario> <nombre> <pin> [caja|cocina]` (el rol por defecto es `caja`).

## Errores

Todas las respuestas de error tienen la forma `{ "error": "mensaje" }`.

| Código | Cuándo |
|---|---|
| `400` | Datos inválidos: un id que no es UUID, un body incompleto o mal formado, o platos no disponibles. En los datos inválidos viene además `detalles`, una lista con el campo y el problema. |
| `401` | Falta el token de staff, o es inválido o está vencido. |
| `403` | El token es de otro restaurante o de otro rol, o el token del cliente no es el del dueño. |
| `404` | El recurso no existe, o la ruta no existe. |
| `409` | Conflicto de estado: la acción ya no es posible (pedido ya en preparación, cuenta ya cerrada). |
| `500` | Error interno. El mensaje es siempre genérico: el detalle queda solo en el log del servidor. |

Ejemplo de `400` por datos inválidos:
```json
{ "error": "datos inválidos", "detalles": [{ "campo": "pedidoId", "mensaje": "Invalid uuid" }] }
```

## Estados

**Pedido**: `recibido` → `en_preparacion` → `listo`. Además, un pedido `recibido` puede pasar a `cancelado`.

| Cambio | Quién | Ruta | Condición |
|---|---|---|---|
| `recibido` → `en_preparacion` | Cocina | `PATCH .../cocina/pedidos/{id}/estado` | el pedido está `recibido` |
| `en_preparacion` → `listo` | Cocina | `PATCH .../cocina/pedidos/{id}/estado` | el pedido está `en_preparacion` |
| `recibido` → `cancelado` | Cliente (dueño) | `POST /cuentas/{id}/pedidos/{id}/cancelar` | el pedido está `recibido` |
| platos de un pedido `recibido` | Cliente (dueño) | `PUT /cuentas/{id}/pedidos/{id}` | el pedido está `recibido` |

Cada cambio usa un candado en la base: si cocina y cliente actúan a la vez sobre el mismo pedido, gana el primero y el otro recibe `409`. Ningún cambio es posible si la cuenta está cerrada.

**Cuenta**: `abierta` → `cerrada`. Solo puede haber una cuenta abierta por mesa (índice único parcial en la base).

## Eventos (outbox)

Todo cambio relevante se registra como un evento en la misma transacción que el cambio de datos.

```json
{ "id": 43, "restauranteId": "…", "cuentaId": "…", "tipo": "pedido_recibido",
  "payload": { "pedido_id": "…" }, "creadoEn": "…" }
```

| `tipo` | Lo genera | `payload` |
|---|---|---|
| `pedido_recibido` | cliente, al crear un pedido | `{ "pedido_id" }` |
| `pedido_modificado` | cliente, al modificar un pedido | `{ "pedido_id" }` |
| `pedido_cancelado` | cliente, al cancelar un pedido | `{ "pedido_id" }` |
| `pedido_en_preparacion` | cocina | `{ "pedido_id" }` |
| `pedido_listo` | cocina | `{ "pedido_id" }` |
| `cuenta_cerrada` | caja, con `cerrar` o `liberar` | `{ "cuenta_id" }` |

**Cómo se consumen** (aplica a la app del cliente y a la de cocina):

- Los eventos se piden con un cursor: `?desde=<último id conocido>`. La respuesta trae `ultimo_id` para seguir desde ahí.
- El cursor solo avanza cuando el evento se procesó bien. Si algo falla, el próximo ciclo reintenta desde el mismo punto, así que una caída de red no pierde eventos.
- Procesar un evento dos veces es inofensivo: ante un evento de pedido, la app vuelve a pedir su detalle (`GET /pedidos/{id}`) y se queda con el estado actual.
- La app del cliente no muestra el estado `listo` (lo informa el mozo en persona): lo trata como "en preparación".
- Al recibir `cuenta_cerrada`, la app del cliente termina la sesión de la mesa y muestra un agradecimiento. Hace lo mismo si el servidor responde `404` al enviar, modificar o cancelar un pedido (la cuenta ya no existe o está cerrada).

---

## Rutas del cliente

### `POST /restaurantes/{restauranteId}/mesas/{mesaId}/unirse`

Sin autenticación. El primer dispositivo que se une a una mesa sin cuenta abierta crea la cuenta y queda como `dueño`. Los que se unen después quedan como `espectador`: ven el menú y el estado, pero no pueden pedir. Dos escaneos simultáneos no duplican la cuenta.

Respuesta `200`:
```json
{ "cuenta_id": "…", "rol": "dueño", "sesion_token": "…", "estado_cuenta": "abierta" }
```
`sesion_token` solo viene si `rol` es `dueño`. Si la mesa ya tiene dueño, `rol` es `espectador` y no hay token. `404` si la mesa no existe en este restaurante.

### `GET /restaurantes/{restauranteId}/menu`

Sin autenticación. Devuelve solo los platos disponibles, ordenados por nombre. No incluye el `codigoInterno` (el código que usa la facturación).

Respuesta `200`:
```json
[{ "id": "…", "restauranteId": "…", "nombre": "Milanesa", "descripcion": null,
   "precio": "12.50", "disponible": true }]
```

### `POST /cuentas/{cuentaId}/pedidos`

`Authorization: Bearer <sesion_token>`. Solo el dueño de la cuenta. Crea el pedido (estado `recibido`) y el evento `pedido_recibido`. El precio de cada plato se guarda en el pedido (`precioUnitario`), así un cambio de precio posterior no altera lo ya pedido.

Body:
```json
{ "items": [{ "menu_item_id": "…", "cantidad": 2, "notas": "sin sal" }] }
```
`items` necesita al menos un elemento. `cantidad` es un entero mayor que 0. `notas` es opcional.

- `201`: el pedido con sus platos.
  ```json
  { "id": "…", "restauranteId": "…", "cuentaId": "…", "estado": "recibido", "creadoEn": "…",
    "items": [{ "id": "…", "pedidoId": "…", "menuItemId": "…", "cantidad": 2,
                "notas": "sin sal", "precioUnitario": "12.50" }] }
  ```
- `400`: alguno de los platos no existe o ya no está disponible.
- `403`: el token no es el del dueño (`otro comensal ya está pidiendo por esta mesa`).
- `404`: la cuenta no existe o está cerrada.

### `PUT /cuentas/{cuentaId}/pedidos/{pedidoId}`

`Authorization: Bearer <sesion_token>`. Solo el dueño. **Reemplaza** los platos del pedido, y solo mientras esté `recibido`. Genera el evento `pedido_modificado`. El body es el mismo que el de crear.

- `200`: el pedido con sus platos nuevos (misma forma que en `201`).
- `400`: alguno de los platos ya no está disponible.
- `403`: el token no es el del dueño.
- `404`: el pedido no existe en esa cuenta, o la cuenta está cerrada.
- `409`: el pedido ya no está `recibido` (cocina lo tomó o está cancelado).

### `POST /cuentas/{cuentaId}/pedidos/{pedidoId}/cancelar`

`Authorization: Bearer <sesion_token>`. Solo el dueño. Sin body. Cancela el pedido mientras esté `recibido` y genera el evento `pedido_cancelado`. Los pedidos cancelados no figuran en lo que caja cobra.

- `200`: el pedido con `estado: "cancelado"` (sin los platos).
- `403`: el token no es el del dueño.
- `404`: el pedido no existe en esa cuenta, o la cuenta está cerrada.
- `409`: el pedido ya estaba cancelado, o ya está en preparación.

### `GET /pedidos/{pedidoId}`

Sin autenticación. Devuelve el detalle de un pedido. Lo usan la app del cliente y la de cocina.

Respuesta `200`:
```json
{ "id": "…", "restauranteId": "…", "cuentaId": "…", "estado": "recibido", "creadoEn": "…",
  "items": [{ "id": "…", "pedidoId": "…", "menuItemId": "…", "cantidad": 2, "notas": null,
              "precioUnitario": "12.50",
              "menuItem": { "id": "…", "nombre": "Milanesa", "descripcion": null } }],
  "cuenta": { "id": "…", "mesa": { "etiqueta": "Mesa 7" } } }
```
De la cuenta solo se devuelven el id y la etiqueta de la mesa (el token del dueño no sale por acá), y del plato solo el id, el nombre y la descripción. `404` si el pedido no existe.

### `GET /cuentas/{cuentaId}/eventos?desde=0`

Sin autenticación. Los eventos de una cuenta, en orden, con id mayor que `desde` (por defecto `0`).

Respuesta `200`:
```json
{ "eventos": [ { "id": 43, "tipo": "pedido_recibido", "…": "…" } ], "ultimo_id": 43 }
```
Si no hay eventos nuevos, `eventos` viene vacío y `ultimo_id` repite el valor de `desde`.

---

## Rutas de cocina

Todas, menos el login, exigen el token de cocina.

### `POST /restaurantes/{restauranteId}/cocina/login`

Body: `{ "usuario": "cocina1", "pin": "4321" }`. Solo acepta usuarios con rol `cocina`.

- `200`: `{ "token": "…" }`
- `401`: `usuario o PIN incorrecto`. El mensaje es el mismo si el usuario no existe, si el PIN está mal o si el usuario tiene otro rol.

### `POST /restaurantes/{restauranteId}/cocina/renovar`

Con el token de cocina vigente en `Authorization: Bearer <token>` y sin body. Devuelve un token nuevo con la misma duración, sin pedir el PIN. Antes de renovar, el backend verifica en la base que el usuario siga existiendo con el rol de cocina.

- `200`: `{ "token": "…" }`
- `401`: el token está vencido o es inválido, o el usuario ya no está habilitado. Hay que volver a iniciar sesión con el PIN.
- `403`: el token es de otro restaurante o de otro rol.

### `GET /restaurantes/{restauranteId}/cocina/pedidos`

La **foto inicial** para arrancar la pantalla de cocina: solo los pedidos activos (`recibido` o `en_preparacion`, de cuentas abiertas), del más viejo al más nuevo, y desde qué evento seguir. Evita releer todo el historial de eventos.

Respuesta `200`:
```json
{ "ultimo_evento_id": 120,
  "pedidos": [{ "id": "…", "estado": "recibido", "creadoEn": "…",
                "cuenta": { "id": "…", "mesa": { "etiqueta": "Mesa 7" } },
                "items": [{ "id": "…", "cantidad": 2, "notas": null,
                            "menuItem": { "nombre": "Milanesa" } }] }] }
```
La app sigue después con `GET .../cocina/eventos?desde=<ultimo_evento_id>`. El último evento se lee antes que los pedidos: si entra algo en el medio, llega de nuevo como evento y se reprocesa sin problema.

### `GET /restaurantes/{restauranteId}/cocina/eventos?desde=0`

Los eventos de **todo el restaurante** (todas las mesas). Misma forma y mismo cursor que el de la cuenta.

### `PATCH /restaurantes/{restauranteId}/cocina/pedidos/{pedidoId}/estado`

Body: `{ "estado": "en_preparacion" }` o `{ "estado": "listo" }`. Genera el evento `pedido_en_preparacion` o `pedido_listo`.

La impresión del ticket al aceptar un pedido la dispara la propia app de cocina cuando recibe el `200`: el backend no sabe nada de impresoras. Una vez en preparación los platos ya no cambian, así que el ticket sale con lo definitivo.

- `200`: el pedido actualizado (`id`, `restauranteId`, `cuentaId`, `estado`, `creadoEn`).
- `404`: el pedido no existe en ese restaurante.
- `409`: la cuenta ya está cerrada, la transición no es válida desde el estado actual (`no se puede pasar de "X" a "Y"`), o el pedido cambió justo antes (por ejemplo, el cliente lo canceló).

---

## Rutas de caja

Todas, menos el login, exigen el token de caja. Ninguna devuelve el token del dueño de la cuenta (`duenioToken`).

### `POST /restaurantes/{restauranteId}/caja/login`

Body: `{ "usuario": "mozo1", "pin": "1234" }`. Solo acepta usuarios con rol `caja`.

- `200`: `{ "token": "…" }`
- `401`: `usuario o PIN incorrecto` (mismo mensaje por usuario inexistente, PIN incorrecto o rol distinto).

### `POST /restaurantes/{restauranteId}/caja/renovar`

Igual que la de cocina, pero con el token de caja: sin body, devuelve `{ "token": "…" }` con la misma duración y verifica que el usuario siga existiendo con el rol de caja. Mismos errores (`401` si el token venció o el usuario ya no está habilitado, `403` si es de otro restaurante o de otro rol).

### `GET /restaurantes/{restauranteId}/caja/cuentas-abiertas`

Las cuentas abiertas con su mesa y sus pedidos (sin los cancelados), cada uno con sus platos. `200`: arreglo.

### `GET /restaurantes/{restauranteId}/caja/cuentas/{cuentaId}`

El detalle de una cuenta, abierta o cerrada: mesa, pedidos (sin los cancelados) y, en cada plato, los datos del menú. Es la vista para saber cuánto cobrar. `404` si no existe.

### `POST /restaurantes/{restauranteId}/caja/cuentas/{cuentaId}/cerrar`

Sin body. Marca la cuenta como `cerrada` (con `cerradaEn`) y genera el evento `cuenta_cerrada`, todo en una sola transacción. Es el punto de enganche para la facturación, cuyo formato todavía no está definido. No exige que los pedidos estén terminados: los que sigan pendientes desaparecen del tablero de cocina por ese evento.

- `200`: la cuenta cerrada.
- `404`: la cuenta no existe en ese restaurante.
- `409`: la cuenta ya estaba cerrada.

### `POST /restaurantes/{restauranteId}/caja/mesas/{mesaId}/liberar`

Sin body. Botón de emergencia: cierra a la fuerza la cuenta abierta de la mesa (por ejemplo, si el dueño perdió el celular y nadie más puede pedir). Genera el evento `cuenta_cerrada`, igual que `cerrar`, para que la cocina saque de su tablero los pedidos de esa mesa.

- `200`: `{ "liberada": true }`
- `404`: no había ninguna cuenta abierta en esa mesa.

---

## Flujo típico

1. El cliente escanea el QR → `unirse` → queda como dueño y recibe su token.
2. Arma el pedido con el menú → `POST /cuentas/{id}/pedidos` → evento `pedido_recibido`.
3. Cocina lo ve aparecer en su tablero, lo acepta → `PATCH .../estado` (`en_preparacion`) → imprime el ticket.
4. La app del cliente se entera por los eventos: la tarjeta pasa de "se puede modificar" a "en preparación".
5. Cocina lo marca `listo` y el mozo lo lleva a la mesa.
6. Al terminar, caja cierra la cuenta → `cerrar` → evento `cuenta_cerrada`.

---

## Pendientes

- **`GET /pedidos/{id}` y `GET /cuentas/{id}/eventos` no piden autenticación**: los UUID hacen de secreto. Es aceptable con una instancia por restaurante; habría que revisarlo si se pasa a un backend compartido.
- **Rutas del cliente sin `/restaurantes/{id}`**: decisión tomada para el modelo de una instancia por restaurante. Con un backend compartido habría que verificar el restaurante en esas rutas.
- **Precios como string**: sigue pendiente decidir si se exponen como `string` o como `number`.
- **Facturación**: el formato del detalle que acompaña a `cuenta_cerrada` está pospuesto.
