import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/pedido_cocina.dart';
import '../services/impresora_tickets.dart';
import '../state/cocina_provider.dart';

class TableroScreen extends StatelessWidget {
  const TableroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cocina = context.watch<CocinaProvider>();
    final impresora = cocina.impresora;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Cocina · ${cocina.nuevos.length} nuevos · ${cocina.enPreparacion.length} en preparación',
        ),
        actions: [
          if (impresora is ImpresoraSimulada)
            IconButton(
              icon: const Icon(Icons.receipt_long),
              tooltip: 'Ver último ticket (impresora simulada)',
              onPressed: () => _verTicket(context, impresora),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () => cocina.cerrarSesion(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (cocina.sinConexion)
            _Banner(
              color: Colors.red.shade200,
              texto: 'Sin conexión con el servidor: los pedidos nuevos pueden no estar apareciendo.',
            ),
          if (cocina.aviso != null)
            _Banner(
              color: Colors.amber.shade200,
              texto: cocina.aviso!,
              onCerrar: cocina.limpiarAviso,
            ),
          Expanded(
            child: !cocina.inicializado
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    builder: (context, c) {
                      final nuevos = _Columna(
                        titulo: 'Nuevos',
                        color: Colors.amber,
                        pedidos: cocina.nuevos,
                      );
                      final enPrep = _Columna(
                        titulo: 'En preparación',
                        color: Colors.blue,
                        pedidos: cocina.enPreparacion,
                      );

                      // Tablet apaisada: dos columnas. Pantalla angosta: una debajo de otra.
                      if (c.maxWidth >= 700) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: SingleChildScrollView(child: nuevos)),
                            const VerticalDivider(width: 1),
                            Expanded(child: SingleChildScrollView(child: enPrep)),
                          ],
                        );
                      }
                      return SingleChildScrollView(
                        child: Column(children: [nuevos, enPrep]),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

void _verTicket(BuildContext context, ImpresoraSimulada impresora) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Último ticket (simulado)'),
      content: SingleChildScrollView(
        child: Text(
          impresora.ultimoTicket ?? 'Todavía no se imprimió ninguno.',
          style: const TextStyle(fontFamily: 'monospace'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
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

class _Columna extends StatelessWidget {
  final String titulo;
  final MaterialColor color;
  final List<PedidoCocina> pedidos;

  const _Columna({required this.titulo, required this.color, required this.pedidos});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: color.shade100,
          padding: const EdgeInsets.all(12),
          child: Text(
            '$titulo (${pedidos.length})',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        if (pedidos.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Sin pedidos', style: TextStyle(color: Colors.grey)),
          )
        else
          for (final p in pedidos) _Tarjeta(pedido: p),
      ],
    );
  }
}

class _Tarjeta extends StatelessWidget {
  final PedidoCocina pedido;

  const _Tarjeta({required this.pedido});

  @override
  Widget build(BuildContext context) {
    final cocina = context.read<CocinaProvider>();
    final nuevo = pedido.estado == 'recibido';
    final base = nuevo ? Colors.amber : Colors.blue;
    final minutos = DateTime.now().difference(pedido.creadoEn).inMinutes;
    final demorado = minutos >= 10;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: demorado ? Colors.red : base.shade600, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'MESA ${pedido.mesa}',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (nuevo)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(
                      label: const Text('NUEVO'),
                      backgroundColor: base.shade200,
                    ),
                  ),
                Text(
                  minutos < 1 ? 'recién' : 'hace $minutos min',
                  style: TextStyle(
                    color: demorado ? Colors.red : null,
                    fontWeight: demorado ? FontWeight.bold : null,
                  ),
                ),
              ],
            ),
            const Divider(),
            for (final item in pedido.items) ...[
              Text(
                '${item.cantidad}× ${item.nombre}',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (item.notas != null)
                Container(
                  margin: const EdgeInsets.only(left: 16, top: 2, bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '⚠ ${item.notas}',
                    style: TextStyle(
                      color: Colors.red.shade900,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            if (nuevo)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.print),
                  label: const Text('Aceptar e imprimir'),
                  onPressed: () => cocina.aceptar(pedido.id),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.check),
                      label: const Text('Listo'),
                      onPressed: () => cocina.marcarListo(pedido.id),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.print),
                    label: const Text('Reimprimir'),
                    onPressed: () => cocina.reimprimir(pedido.id),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
