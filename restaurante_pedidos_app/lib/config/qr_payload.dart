/// El QR codifica una URL con tres parámetros: la base de la API de esta
/// instancia, el restauranteId y el mesaId. Ejemplo:
///
///   https://pedidos.midominio.com/unirse
///     ?api=https%3A%2F%2Fmi-backend.onrender.com%2Fapi%2Fv1
///     &restaurante=<uuid>
///     &mesa=<uuid>
///
/// Hoy el cliente lo escanea con la cámara dentro de la app (sin deep
/// linking todavía, ver el pendiente de infraestructura que quedó
/// anotado). El formato ya queda listo para migrar a un Universal/App
/// Link el día de mañana sin cambiar el contenido del QR, solo cómo se
/// abre.
class QrPayload {
  final String apiBaseUrl;
  final String restauranteId;
  final String mesaId;

  QrPayload({
    required this.apiBaseUrl,
    required this.restauranteId,
    required this.mesaId,
  });

  static QrPayload? parse(String contenido) {
    final uri = Uri.tryParse(contenido);
    if (uri == null) return null;

    final api = uri.queryParameters['api'];
    final restaurante = uri.queryParameters['restaurante'];
    final mesa = uri.queryParameters['mesa'];

    if (api == null || restaurante == null || mesa == null) return null;

    return QrPayload(apiBaseUrl: api, restauranteId: restaurante, mesaId: mesa);
  }
}
