import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/api_client.dart';
import '../services/sesion_store.dart';
import '../models/menu_item.dart';
import '../models/item_carrito.dart';

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
  final Map<String, String> estadoPedidos = {}; // pedidoId -> estado
  int _ultimoEventoId = 0;
  Timer? _pollTimer;
  String? error;

  bool get esDueno => rol == 'dueño';
  bool get tieneSesion => cuentaId != null;

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

  Future<void> enviarPedido() async {
    if (_api == null || cuentaId == null || sesionToken == null || carrito.isEmpty) return;
    try {
      await _api!.enviarPedido(cuentaId: cuentaId!, sesionToken: sesionToken!, items: carrito);
      carrito.clear();
      error = null;
    } catch (e) {
      error = e.toString();
    }
    notifyListeners();
  }

  void _iniciarPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _consultarEventos());
  }

  Future<void> _consultarEventos() async {
    if (_api == null || cuentaId == null) return;
    try {
      final respuesta = await _api!.obtenerEventos(cuentaId: cuentaId!, desde: _ultimoEventoId);
      for (final evento in respuesta.eventos) {
        if (evento.tipo == 'pedido_recibido') {
          estadoPedidos[evento.pedidoId] = 'recibido';
        } else if (evento.tipo == 'pedido_en_preparacion') {
          estadoPedidos[evento.pedidoId] = 'en_preparacion';
        }
        // "pedido_listo" y "cuenta_cerrada" se ignoran a propósito:
        // el estado "listo" no se muestra al cliente (lo informa el
        // mozo en persona, según decidimos), y el cierre de cuenta lo
        // maneja caja, no esta pantalla.
      }
      _ultimoEventoId = respuesta.ultimoId;
      if (respuesta.eventos.isNotEmpty) notifyListeners();
    } catch (_) {
      // Un fallo de red puntual no debería tirar la app: el próximo
      // tick del timer reintenta solo, y como el cursor "desde" vive
      // en memoria, no se pierde ningún evento cuando vuelve a conectar.
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
