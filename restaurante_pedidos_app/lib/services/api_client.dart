import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/item_carrito.dart';
import '../models/menu_item.dart';
import '../models/pedido_cliente.dart';
import '../models/sesion_mesa.dart';

class ApiException implements Exception {
  final String mensaje;
  final int? statusCode;
  ApiException(this.mensaje, [this.statusCode]);

  @override
  String toString() => mensaje;
}

class EventoPedido {
  final int id;
  final String tipo;
  final String? pedidoId; // null en eventos como cuenta_cerrada

  EventoPedido({required this.id, required this.tipo, this.pedidoId});

  factory EventoPedido.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'] as Map<String, dynamic>;
    return EventoPedido(
      id: json['id'] as int,
      tipo: json['tipo'] as String,
      pedidoId: payload['pedido_id'] as String?,
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

  String _mensajeDeError(http.Response res, String porDefecto) {
    try {
      final cuerpo = jsonDecode(res.body) as Map<String, dynamic>;
      return cuerpo['error']?.toString() ?? porDefecto;
    } catch (_) {
      return porDefecto;
    }
  }

  Future<SesionMesa> unirseAMesa({
    required String restauranteId,
    required String mesaId,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/restaurantes/$restauranteId/mesas/$mesaId/unirse'),
    );
    if (res.statusCode != 200) {
      throw ApiException('No se pudo unir a la mesa (${res.statusCode})', res.statusCode);
    }
    return SesionMesa.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<List<MenuItem>> obtenerMenu(String restauranteId) async {
    final res = await http.get(Uri.parse('$baseUrl/restaurantes/$restauranteId/menu'));
    if (res.statusCode != 200) {
      throw ApiException('No se pudo cargar el menú (${res.statusCode})', res.statusCode);
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
      throw ApiException(
        _mensajeDeError(res, 'No se pudo enviar el pedido'),
        res.statusCode,
      );
    }
  }

  Future<void> modificarPedido({
    required String cuentaId,
    required String pedidoId,
    required String sesionToken,
    required List<ItemCarrito> items,
  }) async {
    final res = await http.put(
      Uri.parse('$baseUrl/cuentas/$cuentaId/pedidos/$pedidoId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $sesionToken',
      },
      body: jsonEncode({'items': items.map((i) => i.toJson()).toList()}),
    );
    if (res.statusCode != 200) {
      throw ApiException(
        _mensajeDeError(res, 'No se pudo modificar el pedido'),
        res.statusCode,
      );
    }
  }

  Future<PedidoCliente> obtenerPedido(String pedidoId) async {
    final res = await http.get(Uri.parse('$baseUrl/pedidos/$pedidoId'));
    if (res.statusCode != 200) {
      throw ApiException('No se pudo cargar el pedido (${res.statusCode})', res.statusCode);
    }
    return PedidoCliente.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Patrón outbox del lado del cliente: SIEMPRE se pide "desde" el
  /// último id conocido, nunca se asume que no se perdió nada.
  Future<EventosRespuesta> obtenerEventos({
    required String cuentaId,
    required int desde,
  }) async {
    final res = await http.get(Uri.parse('$baseUrl/cuentas/$cuentaId/eventos?desde=$desde'));
    if (res.statusCode != 200) {
      throw ApiException(
        'No se pudieron consultar las novedades (${res.statusCode})',
        res.statusCode,
      );
    }
    return EventosRespuesta.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> cancelarPedido({
    required String cuentaId,
    required String pedidoId,
    required String sesionToken,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/cuentas/$cuentaId/pedidos/$pedidoId/cancelar'),
      headers: {'Authorization': 'Bearer $sesionToken'},
    );
    if (res.statusCode != 200) {
      throw ApiException(
        _mensajeDeError(res, 'No se pudo cancelar el pedido'),
        res.statusCode,
      );
    }
  }
}

  