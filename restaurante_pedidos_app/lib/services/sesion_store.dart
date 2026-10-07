import 'package:shared_preferences/shared_preferences.dart';

/// Guarda la sesión de la mesa en el dispositivo para que, si el cliente
/// cierra la app sin querer, al volver a abrirla siga en la misma cuenta
/// en vez de tener que escanear el QR de nuevo.
class SesionStore {
  static const _kApiBaseUrl = 'api_base_url';
  static const _kRestauranteId = 'restaurante_id';
  static const _kCuentaId = 'cuenta_id';
  static const _kRol = 'rol';
  static const _kSesionToken = 'sesion_token';

  Future<void> guardar({
    required String apiBaseUrl,
    required String restauranteId,
    required String cuentaId,
    required String rol,
    String? sesionToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kApiBaseUrl, apiBaseUrl);
    await prefs.setString(_kRestauranteId, restauranteId);
    await prefs.setString(_kCuentaId, cuentaId);
    await prefs.setString(_kRol, rol);
    if (sesionToken != null) {
      await prefs.setString(_kSesionToken, sesionToken);
    }
  }

  Future<Map<String, String>?> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final cuentaId = prefs.getString(_kCuentaId);
    if (cuentaId == null) return null;

    return {
      'apiBaseUrl': prefs.getString(_kApiBaseUrl) ?? '',
      'restauranteId': prefs.getString(_kRestauranteId) ?? '',
      'cuentaId': cuentaId,
      'rol': prefs.getString(_kRol) ?? 'espectador',
      'sesionToken': prefs.getString(_kSesionToken) ?? '',
    };
  }

  Future<void> limpiar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kApiBaseUrl);
    await prefs.remove(_kRestauranteId);
    await prefs.remove(_kCuentaId);
    await prefs.remove(_kRol);
    await prefs.remove(_kSesionToken);
  }
}
