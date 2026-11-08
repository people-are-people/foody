import 'package:flutter/foundation.dart';
import '../models/pedido_cocina.dart';

/// Contrato que cumple cualquier impresora. Como todavía no está definida
/// cuál se va a comprar (red ESC/POS, USB o Bluetooth), el resto de la app
/// solo conoce esta interfaz: cuando llegue la impresora real, se escribe
/// una clase nueva que la implemente y se cambia UNA línea en main.dart.
abstract class ImpresoraTickets {
  /// Imprime el ticket del pedido. Si falla, lanza una excepción.
  Future<void> imprimir(PedidoCocina pedido);
}

/// Arma el texto del ticket (pensado para papel de 58 mm, ~32 columnas).
String formatearTicket(PedidoCocina pedido) {
  final hora = '${pedido.creadoEn.hour.toString().padLeft(2, '0')}:'
      '${pedido.creadoEn.minute.toString().padLeft(2, '0')}';
  final linea = '-' * 32;

  final b = StringBuffer()
    ..writeln('MESA ${pedido.mesa}')
    ..writeln('Pedido ${pedido.codigoCorto}   $hora')
    ..writeln(linea);

  for (final item in pedido.items) {
    b.writeln('${item.cantidad} x ${item.nombre}');
    if (item.notas != null) b.writeln('   * ${item.notas}');
  }

  b.writeln(linea);
  return b.toString();
}

/// No imprime en papel: guarda el último ticket para poder verlo en la app
/// y lo escribe en la consola. Sirve para probar todo el flujo sin hardware.
class ImpresoraSimulada implements ImpresoraTickets {
  String? ultimoTicket;

  @override
  Future<void> imprimir(PedidoCocina pedido) async {
    ultimoTicket = formatearTicket(pedido);
    debugPrint(ultimoTicket);
  }
}
