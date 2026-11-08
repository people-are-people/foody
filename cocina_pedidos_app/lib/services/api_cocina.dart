import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/pedido_cocina.dart';

class ApiException implements Exception {
  final String mensaje;
  final int? statusCode;
  ApiException(this.mensaje, [this.statusCode]);

  @override
  String toString() => mensaje;
}

class EventoCocina {
  final int id;
  final String tipo;
  final String? cuentaId;
  final String? pedidoId; // null en eventos como cuenta_cerrada

  EventoCocina({required this.id, required this.tipo, this.cuentaId, this.pedidoId});

  factory EventoCocina.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'] as Map<String, dynamic>;
    return EventoCocina(
      id: json['id'] as int,
      tipo: json['tipo'] as String,
      cuentaId: json['cuentaId'] as String?,
      pedidoId: payload['pedido_id'] as String?,
    );
  }
}

class EventosRespuesta {
  final List<EventoCocina> eventos;
  final int ultimoId;

  EventosRespuesta({required this.eventos, required this.ultimoId});
}

/// Foto del momento: los pedidos activos + desde qué evento seguir.
class SnapshotCocina {
  final int ultimoEventoId;
  final List<PedidoCocina> pedidos;

  SnapshotCocina({required this.ultimoEventoId, required this.pedidos});
}

/// baseUrl ya incluye el /api/v1 (ej: http://10.0.2.2:3000/api/v1).
class ApiCocina {
  final String baseUrl;
  final String restauranteId;
  String? token;

  ApiCocina({required this.baseUrl, required this.restauranteId, this.token});

  String get _base => '$baseUrl/restaurantes/$restauranteId/cocina';

  Map<String, String> get _conToken => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  String _mensajeDeError(http.Response res, String porDefecto) {
    try {
      final cuerpo = jsonDecode(res.body) as Map<String, dynamic>;
      return cuerpo['error']?.toString() ?? porDefecto;
    } catch (_) {
      return porDefecto;
    }
  }

  void _verificar(http.Response res, String mensaje) {
    if (res.statusCode != 200) {
      throw ApiException(
        _mensajeDeError(res, '$mensaje (${res.statusCode})'),
        res.statusCode,
      );
    }
  }

  Future<String> login(String usuario, String pin) async {
    final res = await http.post(
      Uri.parse('$_base/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'usuario': usuario, 'pin': pin}),
    );
    _verificar(res, 'No se pudo iniciar sesión');
    return (jsonDecode(res.body) as Map<String, dynamic>)['token'] as String;
  }

  /// Cambia el token actual por uno nuevo, sin pedir el PIN.
  Future<String> renovar() async {
    final res = await http.post(
      Uri.parse('$_base/renovar'),
      headers: {'Authorization': 'Bearer $token'},
    );
    _verificar(res, 'No se pudo renovar la sesión');
    return (jsonDecode(res.body) as Map<String, dynamic>)['token'] as String;
  }

  Future<SnapshotCocina> obtenerSnapshot() async {
    final res = await http.get(Uri.parse('$_base/pedidos'), headers: _conToken);
    _verificar(res, 'No se pudieron cargar los pedidos');
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final lista = json['pedidos'] as List<dynamic>;
    return SnapshotCocina(
      ultimoEventoId: json['ultimo_evento_id'] as int,
      pedidos: lista.map((e) => PedidoCocina.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  /// Patrón outbox: siempre se pide "desde" el último id conocido.
  Future<EventosRespuesta> obtenerEventos(int desde) async {
    final res = await http.get(Uri.parse('$_base/eventos?desde=$desde'), headers: _conToken);
    _verificar(res, 'No se pudieron consultar las novedades');
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final lista = json['eventos'] as List<dynamic>;
    return EventosRespuesta(
      eventos: lista.map((e) => EventoCocina.fromJson(e as Map<String, dynamic>)).toList(),
      ultimoId: json['ultimo_id'] as int,
    );
  }

  /// Detalle de un pedido (platos, notas, mesa). Esta ruta no pide token.
  Future<PedidoCocina> obtenerPedido(String pedidoId) async {
    final res = await http.get(Uri.parse('$baseUrl/pedidos/$pedidoId'));
    _verificar(res, 'No se pudo cargar el pedido');
    return PedidoCocina.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> cambiarEstado(String pedidoId, String estado) async {
    final res = await http.patch(
      Uri.parse('$_base/pedidos/$pedidoId/estado'),
      headers: _conToken,
      body: jsonEncode({'estado': estado}),
    );
    _verificar(res, 'No se pudo actualizar el pedido');
  }
}
