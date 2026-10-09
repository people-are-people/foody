import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/menu_item.dart';
import '../models/pedido_cliente.dart';
import '../state/sesion_provider.dart';
import 'carrito_sheet.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sesion = context.watch<SesionProvider>();
    final pedidos = sesion.pedidos.values.toList();
    final editando = sesion.editando;
    final etiquetaBoton = editando ? 'Revisar cambios' : 'Ver pedido';

    return Scaffold(
      appBar: AppBar(
        title: Text(editando ? 'Editando Pedido ${sesion.numeroPedidoEditando ?? ''}' : 'Menú'),
        backgroundColor: editando ? Colors.amber.shade200 : null,
        leading: editando
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Cancelar edición',
                onPressed: sesion.cancelarEdicion,
              )
            : null,
      ),
      body: ListView(
        children: [
          if (!sesion.esDueno)
            _Banner(
              color: Colors.amber.shade100,
              texto:
                  'Alguien de tu mesa ya está pidiendo. Podés ver el menú, pero no enviar pedidos.',
            ),
          if (sesion.aviso != null)
            _Banner(
              color: Colors.blue.shade100,
              texto: sesion.aviso!,
              onCerrar: sesion.limpiarAviso,
            ),
          if (editando)
            _Banner(
              color: Colors.amber.shade100,
              texto: 'Modificá los platos con + y −. Cuando termines, tocá "Revisar cambios".',
            )
          else if (sesion.esDueno && pedidos.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('Tocá + para agregar platos a tu pedido.'),
            ),
          if (!editando && pedidos.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('Tus pedidos', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (var i = 0; i < pedidos.length; i++)
              _PedidoCard(numero: i + 1, pedido: pedidos[i], puedeEditar: sesion.esDueno),
          ],
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Menú', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          if (sesion.menu.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No hay platos disponibles todavía'),
            ),
          for (final item in sesion.menu) _PlatoTile(item: item),
        ],
      ),
      bottomNavigationBar: (sesion.esDueno && (sesion.carrito.isNotEmpty || editando))
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  icon: Icon(editando ? Icons.edit : Icons.shopping_cart),
                  label: Text(
                    '$etiquetaBoton · ${sesion.cantidadTotal} · \$${sesion.totalCarrito.toStringAsFixed(2)}',
                  ),
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const CarritoSheet(),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

class _Banner extends StatelessWidget {
  final Color color;
  final String texto;
  final VoidCallback? onCerrar;

  const _Banner({required this.color, required this.texto, this.onCerrar});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(texto)),
          if (onCerrar != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: onCerrar,
            ),
        ],
      ),
    );
  }
}

/// Ámbar + ícono de edición = se puede modificar (recibido).
/// Verde + candado = ya está en cocina, no se puede tocar.

class _PedidoCard extends StatelessWidget {
  final int numero;
  final PedidoCliente pedido;
  final bool puedeEditar;

  const _PedidoCard({
    required this.numero,
    required this.pedido,
    required this.puedeEditar,
  });

  Future<void> _confirmarCancelacion(BuildContext context) async {
    final sesion = context.read<SesionProvider>();
    final messenger = ScaffoldMessenger.of(context);

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Cancelar el Pedido $numero?'),
        content: const Text('Cocina no lo va a preparar. Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Volver'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    final ok = await sesion.cancelarPedido(pedido.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Pedido cancelado' : (sesion.aviso ?? sesion.error ?? 'No se pudo cancelar'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cancelado = pedido.estado == 'cancelado';
    final editable = pedido.estado == 'recibido';
    final base = cancelado ? Colors.grey : (editable ? Colors.amber : Colors.green);
    final resumen = pedido.items.map((i) => '${i.cantidad}× ${i.nombre}').join(', ');
    final accionable = editable && puedeEditar;

    final String estadoTexto;
    if (cancelado) {
      estadoTexto = 'Cancelado';
    } else if (editable) {
      estadoTexto = 'Recibido · se puede modificar o cancelar';
    } else {
      estadoTexto = 'En preparación · ya no se puede modificar';
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: base.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: base.shade600, width: editable ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: accionable ? () => context.read<SesionProvider>().iniciarEdicion(pedido.id) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    cancelado
                        ? Icons.cancel_outlined
                        : (editable ? Icons.edit_note : Icons.restaurant),
                    color: base.shade800,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Pedido $numero',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          resumen,
                          style: TextStyle(
                            decoration: cancelado ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(estadoTexto,
                            style: TextStyle(color: base.shade900, fontSize: 12)),
                      ],
                    ),
                  ),
                  if (!editable && !cancelado)
                    Icon(Icons.lock_outline, color: base.shade700),
                ],
              ),
              if (accionable) ...[
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Cancelar pedido'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
                      onPressed: () => _confirmarCancelacion(context),
                    ),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Modificar'),
                      onPressed: () => context.read<SesionProvider>().iniciarEdicion(pedido.id),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
class _PlatoTile extends StatelessWidget {
  final MenuItem item;

  const _PlatoTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final sesion = context.watch<SesionProvider>();
    final cantidad = sesion.cantidadEnCarrito(item.id);

    return ListTile(
      title: Text(item.nombre),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.descripcion != null) Text(item.descripcion!),
          Text(
            '\$${item.precio.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      trailing: !sesion.esDueno
          ? null
          : cantidad == 0
              ? IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => sesion.agregarAlCarrito(item),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => sesion.quitarDelCarrito(item),
                    ),
                    Text('$cantidad', style: const TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => sesion.agregarAlCarrito(item),
                    ),
                  ],
                ),
    );
  }
}