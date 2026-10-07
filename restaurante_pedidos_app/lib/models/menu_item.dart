class MenuItem {
  final String id;
  final String nombre;
  final String? descripcion;
  final double precio;
  final bool disponible;

  MenuItem({
    required this.id,
    required this.nombre,
    this.descripcion,
    required this.precio,
    required this.disponible,
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      id: json['id'] as String,
      nombre: json['nombre'] as String,
      descripcion: json['descripcion'] as String?,
      // El backend puede devolver el precio como string (Decimal de
      // Prisma) o como número, según cómo termine resolviéndose ese
      // pendiente del contrato de API. toString() + parse cubre ambos.
      precio: double.parse(json['precio'].toString()),
      disponible: json['disponible'] as bool? ?? true,
    );
  }
}
