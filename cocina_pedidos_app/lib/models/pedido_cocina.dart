class ItemCocina {
  final int cantidad;
  final String nombre;
  final String? notas;

  ItemCocina({required this.cantidad, required this.nombre, this.notas});

  factory ItemCocina.fromJson(Map<String, dynamic> json) {
    final menuItem = json['menuItem'] as Map<String, dynamic>?;
    final notas = json['notas'] as String?;
    return ItemCocina(
      cantidad: json['cantidad'] as int,
      nombre: (menuItem?['nombre'] as String?) ?? 'Plato',
      notas: (notas == null || notas.trim().isEmpty) ? null : notas.trim(),
    );
  }
}

class PedidoCocina {
  final String id;
  final String cuentaId;
  final String mesa;
  final String estado; // recibido | en_preparacion
  final DateTime creadoEn;
  final List<ItemCocina> items;

  PedidoCocina({
    required this.id,
    required this.cuentaId,
    required this.mesa,
    required this.estado,
    required this.creadoEn,
    required this.items,
  });

  /// Código corto para identificar el pedido en el ticket.
  String get codigoCorto => id.substring(0, 4).toUpperCase();

  PedidoCocina copiarConEstado(String nuevoEstado) => PedidoCocina(
        id: id,
        cuentaId: cuentaId,
        mesa: mesa,
        estado: nuevoEstado,
        creadoEn: creadoEn,
        items: items,
      );

  /// Sirve tanto para GET /pedidos/{id} como para cada pedido de la foto
  /// inicial (GET /cocina/pedidos): los dos devuelven la misma forma.
  factory PedidoCocina.fromJson(Map<String, dynamic> json) {
    final cuenta = json['cuenta'] as Map<String, dynamic>;
    final mesa = cuenta['mesa'] as Map<String, dynamic>;
    final items = json['items'] as List<dynamic>;
    return PedidoCocina(
      id: json['id'] as String,
      cuentaId: cuenta['id'] as String,
      mesa: mesa['etiqueta'] as String,
      estado: json['estado'] as String,
      creadoEn: DateTime.parse(json['creadoEn'] as String).toLocal(),
      items: items.map((e) => ItemCocina.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}
