import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/item_carrito.dart';
import '../models/menu_item.dart';
import '../models/pedido_cliente.dart';
import '../services/api_client.dart';
import '../services/sesion_store.dart';

class SesionProvider extends ChangeNotifier {
  final SesionStore _store = SesionStore();

  ApiClient? _api;
  String? apiBaseUrl;
  String? restauranteId;
  String? cuentaId;
  String? rol; // "dueño" | "espectador"
  String? sesionToken;

  List<MenuItem> menu = [];
  final List<ItemCarrito> carrito = [];
  // Platos que el cliente tenía sin enviar cuando empezó a editar un pedido.
  final List<ItemCarrito> _borrador = [];
  // Pedidos de la cuenta, en orden de aparición (define "Pedido 1", "Pedido 2").
  final Map<String, PedidoCliente> pedidos = {};
  String? pedidoEditandoId;

  int _ultimoEventoId = 0;
  Timer? _pollTimer;
  bool _consultando = false;
  String? error;
  String? aviso;
  bool enviando = false;

  bool get esDueno => rol == 'dueño';
  bool get tieneSesion => cuentaId != null;
  bool get editando => pedidoEditandoId != null;

  int? get numeroPedidoEditando {
    if (pedidoEditandoId == null) return null;
    final indice = pedidos.keys.toList().indexOf(pedidoEditandoId!);
    return indice == -1 ? null : indice + 1;
  }

  int get cantidadTotal => carrito.fold<int>(0, (suma, i) => suma + i.cantidad);
  double get totalCarrito =>
      carrito.fold<double>(0, (suma, i) => suma + i.item.precio * i.cantidad);

  int cantidadEnCarrito(String menuItemId) {
    for (final i in carrito) {
      if (i.item.id == menuItemId) return i.cantidad;
    }
    return 0;
  }

  Future<void> intentarRestaurarSesion() async {
    final datos = await _store.cargar();
    if (datos == null) return;

    apiBaseUrl = datos['apiBaseUrl'];
    restauranteId = datos['restauranteId'];
    cuentaId = datos['cuentaId'];
    rol = datos['rol'];
    sesionToken = (datos['sesionToken']?.isEmpty ?? true) ? null : datos['sesionToken'];
    _api = ApiClient(apiBaseUrl!);

    await cargarMenu();
    _iniciarPolling();
    notifyListeners();
  }

  Future<void> unirseDesdeQr({
    required String apiUrl,
    required String restaurante,
    required String mesa,
  }) async {
    _api = ApiClient(apiUrl);
    final sesion = await _api!.unirseAMesa(restauranteId: restaurante, mesaId: mesa);

    apiBaseUrl = apiUrl;
    restauranteId = restaurante;
    cuentaId = sesion.cuentaId;
    rol = sesion.rol;
    sesionToken = sesion.sesionToken;

    await _store.guardar(
      apiBaseUrl: apiUrl,
      restauranteId: restaurante,
      cuentaId: sesion.cuentaId,
      rol: sesion.rol,
      sesionToken: sesion.sesionToken,
    );

    await cargarMenu();
    _iniciarPolling();
    notifyListeners();
  }

  Future<void> cargarMenu() async {
    if (_api == null || restauranteId == null) return;
    menu = await _api!.obtenerMenu(restauranteId!);
    notifyListeners();
  }

  void agregarAlCarrito(MenuItem item) {
    error = null;
    ItemCarrito? existente;
    for (final i in carrito) {
      if (i.item.id == item.id) {
        existente = i;
        break;
      }
    }
    if (existente != null) {
      existente.cantidad++;
    } else {
      carrito.add(ItemCarrito(item: item));
    }
    notifyListeners();
  }

  void quitarDelCarrito(MenuItem item) {
    for (final i in carrito) {
      if (i.item.id == item.id) {
        i.cantidad--;
        if (i.cantidad <= 0) carrito.remove(i);
        break;
      }
    }
    notifyListeners();
  }

  // No notifica a propósito: así el campo de texto no pierde el foco
  // mientras el cliente escribe.
  void actualizarNotas(String menuItemId, String notas) {
    for (final i in carrito) {
      if (i.item.id == menuItemId) {
        i.notas = notas;
        break;
      }
    }
  }

  void limpiarAviso() {
    aviso = null;
    notifyListeners();
  }

  // ---- Edición de un pedido ya enviado (solo mientras está "recibido") ----

  MenuItem _menuItemPara(PedidoItemCliente it) {
    for (final m in menu) {
      if (m.id == it.menuItemId) return m;
    }
    // El plato ya no figura en el menú: se reconstruye con lo guardado.
    // Si sigue sin estar disponible, el backend lo rechaza al guardar.
    return MenuItem(
      id: it.menuItemId,
      nombre: it.nombre,
      precio: it.precioUnitario,
      disponible: true,
    );
  }

  void iniciarEdicion(String pedidoId) {
    final pedido = pedidos[pedidoId];
    if (pedido == null || pedido.estado != 'recibido' || !esDueno) return;

    _borrador
      ..clear()
      ..addAll(carrito);
    carrito
      ..clear()
      ..addAll(pedido.items.map(
        (it) => ItemCarrito(item: _menuItemPara(it), cantidad: it.cantidad, notas: it.notas),
      ));
    pedidoEditandoId = pedidoId;
    error = null;
    aviso = null;
    notifyListeners();
  }

  void _salirDeEdicion() {
    carrito
      ..clear()
      ..addAll(_borrador);
    _borrador.clear();
    pedidoEditandoId = null;
  }

  void cancelarEdicion() {
    _salirDeEdicion();
    error = null;
    notifyListeners();
  }

  /// Devuelve true si los cambios se guardaron bien.
  Future<bool> guardarEdicion() async {
    final id = pedidoEditandoId;
    if (_api == null || cuentaId == null || sesionToken == null || id == null || carrito.isEmpty) {
      return false;
    }
    enviando = true;
    error = null;
    notifyListeners();
    try {
      await _api!.modificarPedido(
        cuentaId: cuentaId!,
        pedidoId: id,
        sesionToken: sesionToken!,
        items: carrito,
      );
      _salirDeEdicion();
      enviando = false;
      notifyListeners();
      unawaited(_consultarEventos()); // refresca ya, sin esperar al próximo tick
      return true;
    } catch (e) {
      enviando = false;
      if (e is ApiException && e.statusCode == 409) {
        // Cocina ya tomó el pedido: no hay nada más que editar.
        _salirDeEdicion();
        aviso = e.mensaje;
      } else {
        error = e.toString();
      }
      notifyListeners();
      return false;
    }
  }

  // ---- Envío de un pedido nuevo ----

  /// Devuelve true si el pedido se envió bien.
  Future<bool> enviarPedido() async {
    if (_api == null || cuentaId == null || sesionToken == null || carrito.isEmpty) {
      return false;
    }
    enviando = true;
    error = null;
    notifyListeners();
    try {
      await _api!.enviarPedido(cuentaId: cuentaId!, sesionToken: sesionToken!, items: carrito);
      carrito.clear();
      enviando = false;
      notifyListeners();
      unawaited(_consultarEventos());
      return true;
    } catch (e) {
      error = e.toString();
      enviando = false;
      notifyListeners();
      return false;
    }
  }

  // ---- Novedades (outbox) ----

  void _iniciarPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _consultarEventos());
  }

  Future<void> _consultarEventos() async {
    if (_api == null || cuentaId == null || _consultando) return;
    _consultando = true;
    try {
      final respuesta = await _api!.obtenerEventos(cuentaId: cuentaId!, desde: _ultimoEventoId);

      // Un pedido puede acumular varios eventos (recibido, modificado,
      // en preparación...). Se pide su detalle una sola vez, ya con el
      // estado y los platos actuales.
      final afectados = <String>{};
      for (final evento in respuesta.eventos) {
        final id = evento.pedidoId;
        if (id != null) afectados.add(id);
      }
      for (final id in afectados) {
        pedidos[id] = await _api!.obtenerPedido(id);
      }

      // El cursor avanza recién cuando todo lo anterior salió bien: si algo
      // falla, el próximo tick reintenta desde el mismo punto.
      _ultimoEventoId = respuesta.ultimoId;

      if (editando) {
        final enEdicion = pedidos[pedidoEditandoId];
        if (enEdicion == null || enEdicion.estado != 'recibido') {
          _salirDeEdicion();
          aviso = 'Tu pedido ya pasó a preparación y no se puede modificar.';
        }
      }

      if (respuesta.eventos.isNotEmpty) notifyListeners();
    } catch (_) {
      // Un fallo de red puntual no tira la app: el próximo tick reintenta.
    } finally {
      _consultando = false;
    }
  }

    Future<bool> cancelarPedido(String pedidoId) async {
    if (_api == null || cuentaId == null || sesionToken == null) return false;
    error = null;
    try {
      await _api!.cancelarPedido(
        cuentaId: cuentaId!,
        pedidoId: pedidoId,
        sesionToken: sesionToken!,
      );
      unawaited(_consultarEventos());
      return true;
    } catch (e) {
      if (e is ApiException && e.statusCode == 409) {
        aviso = e.mensaje; // cocina ya lo tomó
        unawaited(_consultarEventos());
      } else {
        error = e.toString();
      }
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}