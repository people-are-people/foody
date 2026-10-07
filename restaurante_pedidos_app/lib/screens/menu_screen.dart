import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/sesion_provider.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sesion = context.watch<SesionProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Menú'),
        actions: [
          IconButton(
            icon: Badge(
              label: Text('${sesion.carrito.length}'),
              isLabelVisible: sesion.carrito.isNotEmpty,
              child: const Icon(Icons.shopping_cart),
            ),
            onPressed: (sesion.esDueno && sesion.carrito.isNotEmpty)
                ? () => sesion.enviarPedido()
                : null,
          ),
        ],
      ),
      body: Column(
        children: [
          if (!sesion.esDueno)
            Container(
              width: double.infinity,
              color: Colors.amber.shade100,
              padding: const EdgeInsets.all(8),
              child: const Text(
                'Alguien de tu mesa ya está pidiendo. Podés ver el menú, pero no enviar pedidos.',
                textAlign: TextAlign.center,
              ),
            ),
          if (sesion.error != null)
            Container(
              width: double.infinity,
              color: Colors.red.shade100,
              padding: const EdgeInsets.all(8),
              child: Text(sesion.error!, textAlign: TextAlign.center),
            ),
          if (sesion.estadoPedidos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 8,
                children: sesion.estadoPedidos.values
                    .map((estado) => Chip(label: Text('Pedido: $estado')))
                    .toList(),
              ),
            ),
          Expanded(
            child: sesion.menu.isEmpty
                ? const Center(child: Text('No hay items disponibles todavía'))
                : ListView.builder(
                    itemCount: sesion.menu.length,
                    itemBuilder: (context, i) {
                      final item = sesion.menu[i];
                      return ListTile(
                        title: Text(item.nombre),
                        subtitle: item.descripcion != null ? Text(item.descripcion!) : null,
                        trailing: Text('\$${item.precio.toStringAsFixed(2)}'),
                        onTap: sesion.esDueno ? () => sesion.agregarAlCarrito(item) : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
