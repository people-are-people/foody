# App del cliente — Sistema de pedidos de restaurante

Flutter + Provider + http. Consume el backend documentado en `api-contract.md`.

## Integrarlo con tu proyecto

1. Si todavía no lo hiciste:
   ```bash
   flutter create restaurante_pedidos_app
   cd restaurante_pedidos_app
   ```
2. Reemplazá la carpeta `lib/` generada por la que está acá.
3. Abrí `pubspec-dependencias.yaml` y copiá esas líneas dentro de la
   sección `dependencies:` de tu `pubspec.yaml` real (el que generó
   `flutter create`, que ya trae la config nativa correcta — no lo
   reemplaces entero).
4. Agregá los permisos de cámara (ver abajo).
5. `flutter pub get`
6. `flutter run`

## Permisos de cámara (para `mobile_scanner`)

**Android** — en `android/app/src/main/AndroidManifest.xml`, dentro de
`<manifest>` y antes de `<application>`:
```xml
<uses-permission android:name="android.permission.CAMERA" />
```

**iOS** — en `ios/Runner/Info.plist`, dentro del `<dict>` principal:
```xml
<key>NSCameraUsageDescription</key>
<string>Necesitamos la cámara para escanear el código QR de tu mesa</string>
```

Sin esto, la app se cierra (o la cámara no abre) al llegar a la
pantalla de escaneo — es un paso fácil de olvidar.

## Estructura

```
lib/
  config/qr_payload.dart     formato del QR (URL con api/restaurante/mesa)
  models/                    MenuItem, SesionMesa, ItemCarrito
  services/
    api_client.dart          llamadas HTTP al backend
    sesion_store.dart        persiste la sesión en el dispositivo
  state/sesion_provider.dart estado central: menú, carrito, polling de eventos
  screens/
    qr_scan_screen.dart      escaneo con cámara
    union_manual_screen.dart modo prueba, sin QR real todavía
    menu_screen.dart         menú + carrito + estado de pedidos
  main.dart                  arranque, restaura sesión si existe
```

## Probarlo sin un QR impreso

Como todavía no definiste la impresora ni generaste QRs reales, usá el
botón **"Ingresar datos manualmente (modo prueba)"** en la pantalla de
escaneo. Pedís ahí:
- **URL base de la API**: en el emulador de Android, `http://10.0.2.2:3000/api/v1`
  (10.0.2.2 es el alias que usa el emulador para llegar al localhost de
  tu PC — "localhost" a secas NO va a funcionar ahí). En el simulador de
  iOS, `http://localhost:3000/api/v1` sí funciona directo. En un celular
  físico, necesitás la IP de tu PC en la red local, no localhost.
- **restauranteId** y **mesaId**: los mismos UUIDs que ya usaste en
  Postman.

## Pendientes conocidos

- **Deep linking real** (que el QR abra la app directo, sin pasar por
  la cámara de la propia app) quedó pospuesto — ver el checklist de
  antes de programar. El formato de URL que usamos para el QR ya es
  compatible con migrar a esto después.
- **Impresión de tickets**: no es parte de esta app — vive en la app de
  cocina, que todavía no construimos.
- **Precio como string vs number**: el modelo `MenuItem` ya maneja los
  dos casos al parsear, por las dudas se resuelva de una forma u otra
  del lado del backend.
