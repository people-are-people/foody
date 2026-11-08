import 'package:shared_preferences/shared_preferences.dart';

/// Guarda en la tablet la configuración (URL, restaurante, usuario) y el
/// token, para no tener que reingresar todo si la app se cierra durante
/// el servicio. El PIN nunca se guarda.
class SesionStore {
  static const _kApi = 'api_url';
  static const _kRestaurante = 'restaurante_id';
  static const _kUsuario = 'usuario';
  static const _kToken = 'token';

  Future<void> guardar({
    required String apiUrl,
    required String restauranteId,
    required String usuario,
    required String token,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kApi, apiUrl);
    await prefs.setString(_kRestaurante, restauranteId);
    await prefs.setString(_kUsuario, usuario);
    await prefs.setString(_kToken, token);
  }

  Future<void> guardarToken(String token) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kToken, token);
  }

  /// Lo que se precarga en la pantalla de login.
  Future<Map<String, String>> cargarConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'apiUrl': prefs.getString(_kApi) ?? '',
      'restauranteId': prefs.getString(_kRestaurante) ?? '',
      'usuario': prefs.getString(_kUsuario) ?? '',
    };
  }

  /// Devuelve null si no hay una sesión completa guardada.
  Future<Map<String, String>?> cargarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    final config = await cargarConfig();
    final token = prefs.getString(_kToken);
    if (token == null ||
        token.isEmpty ||
        config['apiUrl']!.isEmpty ||
        config['restauranteId']!.isEmpty) {
      return null;
    }
    return {...config, 'token': token};
  }

  Future<void> limpiarToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
  }
}
