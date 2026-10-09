class PedidoItemCliente {
  final String menuItemId;
  final String nombre;
  final int cantidad;
  final String? notas;
  final double precioUnitario;

  PedidoItemCliente({
    required this.menuItemId,
    required this.nombre,
    required this.cantidad,
    this.notas,
    required this.precioUnitario,
  });

  factory PedidoItemCliente.fromJson(Map<String, dynamic> json) {
    final menuItem = json['menuItem'] as Map<String, dynamic>?;
    return PedidoItemCliente(
      menuItemId: json['menuItemId'] as String,
      nombre: (menuItem?['nombre'] as String?) ?? 'Plato',
      cantidad: json['cantidad'] as int,
      notas: json['notas'] as String?,
      precioUnitario: double.parse(json['precioUnitario'].toString()),
    );
  }
}

class PedidoCliente {
  final String id;
  final String estado; // recibido | en_preparacion | listo
  final List<PedidoItemCliente> items;

  PedidoCliente({required this.id, required this.estado, required this.items});

  factory PedidoCliente.fromJson(Map<String, dynamic> json) {
    final lista = json['items'] as List<dynamic>;
    return PedidoCliente(
      id: json['id'] as String,
      estado: json['estado'] as String,
      items: lista
          .map((e) => PedidoItemCliente.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}