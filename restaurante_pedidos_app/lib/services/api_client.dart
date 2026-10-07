import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/menu_item.dart';
import '../models/sesion_mesa.dart';
import '../models/item_carrito.dart';

class ApiException implements Exception {
  final String mensaje;
  ApiException(this.mensaje);

  @override
  String toString() => mensaje;
}

class EventoPedido {
  final int id;
  final String tipo;
  final String pedidoId;

  EventoPedido({required this.id, required this.tipo, required this.pedidoId});

  factory EventoPedido.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'] as Map<String, dynamic>;
    return EventoPedido(
      id: json['id'] as int,
      tipo: json['tipo'] as String,
      pedidoId: payload['pedido_id'] as String,
    );
  }
}

class EventosRespuesta {
  final List<EventoPedido> eventos;
  final int ultimoId;

  EventosRespuesta({required this.eventos, required this.ultimoId});

  factory EventosRespuesta.fromJson(Map<String, dynamic> json) {
    final lista = json['eventos'] as List<dynamic>;
    return EventosRespuesta(
      eventos: lista
          .map((e) => EventoPedido.fromJson(e as Map<String, dynamic>))
          .toList(),
      ultimoId: json['ultimo_id'] as int,
    );
  }
}

/// baseUrl ya incluye el /api/v1 (ej: http://10.0.2.2:3000/api/v1).
class ApiClient {
  final String baseUrl;

  ApiClient(this.baseUrl);

  Future<SesionMesa> unirseAMesa({
    required String restauranteId,
    required String mesaId,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/restaurantes/$restauranteId/mesas/$mesaId/unirse'),
    );
    if (res.statusCode != 200) {
      throw ApiException('No se pudo unir a la mesa (${res.statusCode})');
    }
    return SesionMesa.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<List<MenuItem>> obtenerMenu(String restauranteId) async {
    final res = await http.get(Uri.parse('$baseUrl/restaurantes/$restauranteId/menu'));
    if (res.statusCode != 200) {
      throw ApiException('No se pudo cargar el menú (${res.statusCode})');
    }
    final lista = jsonDecode(res.body) as List<dynamic>;
    return lista.map((e) => MenuItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> enviarPedido({
    required String cuentaId,
    required String sesionToken,
    required List<ItemCarrito> items,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/cuentas/$cuentaId/pedidos'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $sesionToken',
      },
      body: jsonEncode({'items': items.map((i) => i.toJson()).toList()}),
    );
    if (res.statusCode != 201) {
      String mensaje = 'No se pudo enviar el pedido';
      try {
        final cuerpo = jsonDecode(res.body) as Map<String, dynamic>;
        mensaje = cuerpo['error']?.toString() ?? mensaje;
      } catch (_) {
        // el body no era JSON, nos quedamos con el mensaje genérico
      }
      throw ApiException(mensaje);
    }
  }

  /// Patrón outbox del lado del cliente: SIEMPRE se pide "desde" el
  /// último id conocido, nunca se confía en que no se perdió nada por
  /// estar un rato sin conexión. Ver decisión de arquitectura del canal
  /// de tiempo real.
  Future<EventosRespuesta> obtenerEventos({
    required String cuentaId,
    required int desde,
  }) async {
    final res = await http.get(Uri.parse('$baseUrl/cuentas/$cuentaId/eventos?desde=$desde'));
    if (res.statusCode != 200) {
      throw ApiException('No se pudieron consultar las novedades (${res.statusCode})');
    }
    return EventosRespuesta.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }
}
