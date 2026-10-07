import 'menu_item.dart';

class ItemCarrito {
  final MenuItem item;
  int cantidad;
  String? notas;

  ItemCarrito({required this.item, this.cantidad = 1, this.notas});

  Map<String, dynamic> toJson() => {
        'menu_item_id': item.id,
        'cantidad': cantidad,
        if (notas != null && notas!.isNotEmpty) 'notas': notas,
      };
}
