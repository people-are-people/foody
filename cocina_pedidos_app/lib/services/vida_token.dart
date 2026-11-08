import 'dart:convert';

class VidaToken {
  final DateTime emitido;
  final DateTime vence;

  VidaToken(this.emitido, this.vence);

  /// Pasada la mitad de su vida, conviene renovarlo.
  bool get convieneRenovar {
    final mitad = emitido.add(vence.difference(emitido) ~/ 2);
    return DateTime.now().isAfter(mitad);
  }

  /// Devuelve null si el token no tiene el formato esperado.
  static VidaToken? leer(String token) {
    try {
      final partes = token.split('.');
      if (partes.length != 3) return null;
      final cuerpo = utf8.decode(base64Url.decode(base64Url.normalize(partes[1])));
      final datos = jsonDecode(cuerpo) as Map<String, dynamic>;
      final iat = datos['iat'] as int;
      final exp = datos['exp'] as int;
      return VidaToken(
        DateTime.fromMillisecondsSinceEpoch(iat * 1000),
        DateTime.fromMillisecondsSinceEpoch(exp * 1000),
      );
    } catch (_) {
      return null;
    }
  }
}