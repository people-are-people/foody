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

  /// true cuando la cuenta de la mesa se cerró: la app muestra el agradecimiento.
  bool cuentaCerrada = false;

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

  // El servidor responde 404 cuando la cuenta ya no existe o está cerrada.
  bool _cuentaYaNoExiste(Object e) => e is ApiException && e.statusCode == 404;

  // ---- Sesión de mesa ----

  Future<void> intentarRestaurarSesion() async {
    final datos = await _store.cargar();
    if (datos == null) return;

    apiBaseUrl = datos['apiBaseUrl'];
    restauranteId = datos['restauranteId'];
    cuentaId = datos['cuentaId'];
    rol = datos['rol'];
    sesionToken = (datos['sesionToken']?.isEmpty ?? true) ? null : datos['sesionToken'];
    _api = ApiClient(apiBaseUrl!);

    try {
      await cargarMenu();
    } catch (_) {
      // Sin red al abrir: la app arranca igual y el menú se recarga cuando haga falta.
    }

    _iniciarPolling();
    // Primera consulta ya mismo: si la cuenta se cerró mientras la app estaba
    // cerrada, se entera acá y no llega a mostrar el menú.
    await _consultarEventos();
    notifyListeners();
  }

  Future<void> unirseDesdeQr({
    required String apiUrl,
    required String restaurante,
    required String mesa,
  }) async {
    final api = ApiClient(apiUrl);
    final sesion = await api.unirseAMesa(restauranteId: restaurante, mesaId: mesa);

    _api = api;
    apiBaseUrl = apiUrl;
    restauranteId = restaurante;
    cuentaId = sesion.cuentaId;
    rol = sesion.rol;
    sesionToken = sesion.sesionToken;
    cuentaCerrada = false;
    _ultimoEventoId = 0;
    pedidos.clear();

    await _store.guardar(
      apiBaseUrl: apiUrl,
      restauranteId: restaurante,
      cuentaId: sesion.cuentaId,
      rol: sesion.rol,
      sesionToken: sesion.sesionToken,
    );

    await cargarMenu();
    _iniciarPolling();
    unawaited(_consultarEventos());
    notifyListeners();
  }

  /// La cuenta se cerró (o dejó de existir): se borra todo lo de esta mesa
  /// y se muestra el agradecimiento.
  Future<void> _terminarSesionPorCierre() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    await _store.limpiar();

    _api = null;
    apiBaseUrl = null;
    restauranteId = null;
    cuentaId = null;
    rol = null;
    sesionToken = null;
    menu = [];
    carrito.clear();
    _borrador.clear();
    pedidos.clear();
    pedidoEditandoId = null;
    _ultimoEventoId = 0;
    error = null;
    aviso = null;
    enviando = false;

    cuentaCerrada = true;
    notifyListeners();
  }

  /// Desde la pantalla de agradecimiento: vuelve a escanear.
  void volverAlInicio() {
    cuentaCerrada = false;
    notifyListeners();
  }

  Future<void> cargarMenu() async {
    if (_api == null || restauranteId == null) return;
    menu = await _api!.obtenerMenu(restauranteId!);
    notifyListeners();
  }

  // ---- Carrito ----

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

  /// El backend rechazó el pedido porque algún plato dejó de estar disponible.
  /// Se recarga el menú y se sacan del carrito los platos que ya no figuran.
  /// Devuelve el mensaje para el cliente, o null si no se pudo reconciliar
  /// (por ejemplo, sin red): en ese caso queda el mensaje original del servidor.
  Future<String?> _reconciliarMenu() async {
    try {
      menu = await _api!.obtenerMenu(restauranteId!);
    } catch (_) {
      return null;
    }

    final disponibles = menu.map((m) => m.id).toSet();
    final sacados = <String>[];
    carrito.removeWhere((i) {
      final yaNoEsta = !disponibles.contains(i.item.id);
      if (yaNoEsta) sacados.add(i.item.nombre);
      return yaNoEsta;
    });

    if (sacados.isEmpty) return null;
    return 'Ya no están disponibles: ${sacados.join(', ')}. '
        'Los quitamos de tu pedido; revisalo y volvé a enviarlo.';
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
      unawaited(_consultarEventos()); // refresca ya, sin esperar al próximo ciclo
      return true;
    } catch (e) {
      if (_cuentaYaNoExiste(e)) {
        await _terminarSesionPorCierre();
        return false;
      }
      if (e is ApiException && e.statusCode == 409) {
        // Cocina ya tomó el pedido: no hay nada más que editar.
        _salirDeEdicion();
        aviso = e.mensaje;
      } else if (e is ApiException && e.statusCode == 400) {
        error = await _reconciliarMenu() ?? e.mensaje;
      } else {
        error = e.toString();
      }
      enviando = false;
      notifyListeners();
      return false;
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
      if (_cuentaYaNoExiste(e)) {
        await _terminarSesionPorCierre();
      } else if (e is ApiException && e.statusCode == 409) {
        aviso = e.mensaje; // cocina ya lo tomó
        unawaited(_consultarEventos());
        notifyListeners();
      } else {
        error = e.toString();
        notifyListeners();
      }
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
      if (_cuentaYaNoExiste(e)) {
        await _terminarSesionPorCierre();
        return false;
      }
      error = e.toString();
      if (e is ApiException && e.statusCode == 400) {
        error = await _reconciliarMenu() ?? error;
      }
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

      // Caja cerró la cuenta: se termina la sesión de esta mesa.
      if (respuesta.eventos.any((e) => e.tipo == 'cuenta_cerrada')) {
        await _terminarSesionPorCierre();
        return;
      }

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
      // falla, el próximo ciclo reintenta desde el mismo punto.
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
      // Un fallo de red puntual no tira la app: el próximo ciclo reintenta.
    } finally {
      _consultando = false;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}