import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/sesion_provider.dart';

class CarritoSheet extends StatelessWidget {
  const CarritoSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final sesion = context.watch<SesionProvider>();
    final editando = sesion.editando;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                editando ? 'Editando Pedido ${sesion.numeroPedidoEditando ?? ''}' : 'Tu pedido',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (sesion.carrito.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Tu pedido está vacío.'),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final i in sesion.carrito)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(i.item.nombre,
                                      style: Theme.of(context).textTheme.titleMedium),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: () => sesion.quitarDelCarrito(i.item),
                                ),
                                Text('${i.cantidad}'),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: () => sesion.agregarAlCarrito(i.item),
                                ),
                                SizedBox(
                                  width: 64,
                                  child: Text(
                                    '\$${(i.item.precio * i.cantidad).toStringAsFixed(2)}',
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                              ],
                            ),
                            TextFormField(
                              key: ValueKey('notas-${i.item.id}'),
                              initialValue: i.notas,
                              decoration: const InputDecoration(
                                hintText: 'Aclaraciones (ej: sin sal)',
                                isDense: true,
                              ),
                              onChanged: (v) => sesion.actualizarNotas(i.item.id, v),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total', style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    '\$${sesion.totalCarrito.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            if (sesion.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(sesion.error!, style: const TextStyle(color: Colors.red)),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (sesion.enviando || sesion.carrito.isEmpty)
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final navigator = Navigator.of(context);
                          final estabaEditando = sesion.editando;
                          final ok = estabaEditando
                              ? await sesion.guardarEdicion()
                              : await sesion.enviarPedido();
                          if (ok) {
                            navigator.pop();
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  estabaEditando
                                      ? 'Pedido modificado'
                                      : '¡Pedido enviado a cocina!',
                                ),
                              ),
                            );
                          } else if (estabaEditando && !sesion.editando) {
                            // Cocina tomó el pedido mientras editabas: se
                            // cerró la edición y el aviso queda en el menú.
                            navigator.pop();
                          }
                        },
                  child: sesion.enviando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(editando ? 'Guardar cambios' : 'Enviar pedido'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}