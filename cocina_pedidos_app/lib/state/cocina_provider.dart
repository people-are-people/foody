import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/pedido_cocina.dart';
import '../services/api_cocina.dart';
import '../services/impresora_tickets.dart';
import '../services/sesion_store.dart';
import '../services/vida_token.dart';

class CocinaProvider extends ChangeNotifier {
  CocinaProvider({required this.impresora});

  final ImpresoraTickets impresora;
  final SesionStore _store = SesionStore();

  ApiCocina? _api;
  String? usuario;

  /// Pedidos activos (recibido / en_preparacion) de cuentas abiertas.
  final Map<String, PedidoCocina> pedidos = {};

  int _ultimoEventoId = 0;
  bool _inicializado = false;
  bool _consultando = false;
  Timer? _pollTimer;
  Timer? _tickTimer;

  bool _renovando = false;
  DateTime? _ultimaRenovacion;

  bool sinConexion = false;
  bool ocupado = false; // login en curso
  String? error; // se muestra en el login
  String? aviso; // se muestra arriba del tablero

  bool get tieneSesion => _api != null;
  bool get inicializado => _inicializado;

  List<PedidoCocina> get nuevos => _ordenados('recibido');
  List<PedidoCocina> get enPreparacion => _ordenados('en_preparacion');

  // El más viejo primero: es el que hay que sacar antes.
  List<PedidoCocina> _ordenados(String estado) {
    final lista = pedidos.values.where((p) => p.estado == estado).toList();
    lista.sort((a, b) => a.creadoEn.compareTo(b.creadoEn));
    return lista;
  }

  // ---- Sesión ----

  Future<void> intentarRestaurarSesion() async {
    final datos = await _store.cargarSesion();
    if (datos == null) return;

    usuario = datos['usuario'];
    _api = ApiCocina(
      baseUrl: datos['apiUrl']!,
      restauranteId: datos['restauranteId']!,
      token: datos['token'],
    );
    _arrancar();
    notifyListeners();
  }

  Future<bool> iniciarSesion({
    required String apiUrl,
    required String restauranteId,
    required String usuarioIngresado,
    required String pin,
  }) async {
    ocupado = true;
    error = null;
    notifyListeners();
    try {
      final api = ApiCocina(baseUrl: apiUrl.trim(), restauranteId: restauranteId.trim());
      final token = await api.login(usuarioIngresado.trim(), pin);
      api.token = token;

      _api = api;
      usuario = usuarioIngresado.trim();
      await _store.guardar(
        apiUrl: api.baseUrl,
        restauranteId: api.restauranteId,
        usuario: usuario!,
        token: token,
      );

      _arrancar();
      ocupado = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = e is ApiException
          ? e.mensaje
          : 'No se pudo conectar con el servidor. Revisá la URL y la red.';
      ocupado = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> cerrarSesion({String? mensaje}) async {
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    _pollTimer = null;
    _tickTimer = null;
    await _store.limpiarToken();
    _api = null;
    pedidos.clear();
    _inicializado = false;
    sinConexion = false;
    aviso = null;
    error = mensaje;
    notifyListeners();
  }

  void limpiarAviso() {
    aviso = null;
    notifyListeners();
  }

  // ---- Sincronización con el backend ----

  void _arrancar() {
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    _inicializado = false;
    pedidos.clear();

    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _consultar());
    // Refresca los "hace X min" aunque no haya novedades.
    _tickTimer = Timer.periodic(const Duration(seconds: 20), (_) => notifyListeners());
    unawaited(_consultar());
  }

  // La foto inicial trae solo lo que está activo y desde qué evento seguir,
  // en vez de releer todo el historial desde el evento 1.
  Future<void> _cargarFoto() async {
    final foto = await _api!.obtenerSnapshot();
    pedidos
      ..clear()
      ..addEntries(foto.pedidos.map((p) => MapEntry(p.id, p)));
    _ultimoEventoId = foto.ultimoEventoId;
    _inicializado = true;
  }

  Future<void> _consultar() async {
    if (_api == null || _consultando) return;
    _consultando = true;
    try {
      await _renovarTokenSiHaceFalta();
      if (_api == null) return; // la renovación falló por sesión vencida
      if (!_inicializado) {
        await _cargarFoto();
        sinConexion = false;
        notifyListeners();
        return;
      }

      final respuesta = await _api!.obtenerEventos(_ultimoEventoId);

      final afectados = <String>{};
      final cuentasCerradas = <String>{};
      for (final e in respuesta.eventos) {
        if (e.tipo == 'cuenta_cerrada') {
          if (e.cuentaId != null) cuentasCerradas.add(e.cuentaId!);
        } else if (e.pedidoId != null) {
          afectados.add(e.pedidoId!);
        }
      }

      // De cada pedido afectado se pide el detalle una sola vez, ya con su
      // estado y sus platos actuales (recibido, modificado, cancelado...).
      var hayNuevo = false;
      for (final id in afectados) {
        final detalle = await _api!.obtenerPedido(id);
        final activo = detalle.estado == 'recibido' || detalle.estado == 'en_preparacion';
        if (activo) {
          if (!pedidos.containsKey(id) && detalle.estado == 'recibido') hayNuevo = true;
          pedidos[id] = detalle;
        } else {
          pedidos.remove(id); // cancelado o listo
        }
      }
      pedidos.removeWhere((_, p) => cuentasCerradas.contains(p.cuentaId));

      // El cursor avanza recién cuando todo salió bien: si algo falla, el
      // próximo ciclo reintenta desde el mismo punto y no se pierde nada.
      _ultimoEventoId = respuesta.ultimoId;

      final reconecto = sinConexion;
      sinConexion = false;
      if (hayNuevo) {
        unawaited(SystemSound.play(SystemSoundType.alert).catchError((_) {}));
      }
      if (respuesta.eventos.isNotEmpty || reconecto) notifyListeners();
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await cerrarSesion(mensaje: 'Tu sesión venció. Ingresá de nuevo.');
      } else {
        _marcarSinConexion();
      }
    } catch (_) {
      _marcarSinConexion();
    } finally {
      _consultando = false;
    }
  }

    // Renueva el token cuando ya pasó la mitad de su vida, sin pedir el PIN.
  Future<void> _renovarTokenSiHaceFalta() async {
    final api = _api;
    final token = api?.token;
    if (api == null || token == null || _renovando) return;

    final vida = VidaToken.leer(token);
    if (vida == null || !vida.convieneRenovar) return;

    // Tope de seguridad: si el reloj de la tablet está desfasado, no se
    // insiste más de una vez por minuto.
    final ultima = _ultimaRenovacion;
    if (ultima != null && DateTime.now().difference(ultima) < const Duration(minutes: 1)) {
      return;
    }

    _renovando = true;
    _ultimaRenovacion = DateTime.now();
    try {
      final nuevo = await api.renovar();
      api.token = nuevo;
      await _store.guardarToken(nuevo);
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        await cerrarSesion(mensaje: 'Tu sesión venció. Ingresá de nuevo.');
      }
    } catch (_) {
      // Sin red: el token actual sigue valiendo, se reintenta más adelante.
    } finally {
      _renovando = false;
    }
  }

  void _marcarSinConexion() {
    if (!sinConexion) {
      sinConexion = true;
      notifyListeners();
    }
  }

  // ---- Acciones de cocina ----

  Future<bool> _cambiarEstado(String pedidoId, String estado) async {
    try {
      await _api!.cambiarEstado(pedidoId, estado);
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await cerrarSesion(mensaje: 'Tu sesión venció. Ingresá de nuevo.');
      } else {
        // Ej: el cliente canceló el pedido justo antes. El evento de
        // cancelación lo saca del tablero en el próximo ciclo.
        aviso = e.mensaje;
        notifyListeners();
        unawaited(_consultar());
      }
      return false;
    } catch (_) {
      aviso = 'Sin conexión: no se pudo actualizar el pedido. Reintentá.';
      notifyListeners();
      return false;
    }
  }

  Future<void> aceptar(String pedidoId) async {
    if (_api == null) return;
    aviso = null;
    if (!await _cambiarEstado(pedidoId, 'en_preparacion')) return;

    // Desde acá los platos quedan congelados (el cliente ya no puede
    // modificar ni cancelar), así que el ticket sale con lo definitivo.
    PedidoCocina? fresco;
    try {
      fresco = await _api!.obtenerPedido(pedidoId);
    } catch (_) {
      fresco = pedidos[pedidoId]?.copiarConEstado('en_preparacion');
    }
    if (fresco == null) return;

    pedidos[pedidoId] = fresco;
    notifyListeners();
    await _imprimir(fresco);
  }

  Future<void> marcarListo(String pedidoId) async {
    if (_api == null) return;
    aviso = null;
    if (!await _cambiarEstado(pedidoId, 'listo')) return;
    pedidos.remove(pedidoId);
    notifyListeners();
  }

  Future<void> reimprimir(String pedidoId) async {
    final pedido = pedidos[pedidoId];
    if (pedido != null) await _imprimir(pedido);
  }

  // Si la impresora falla, el pedido igual queda aceptado: no se pierde
  // nada, solo hay que reimprimir.
  Future<void> _imprimir(PedidoCocina pedido) async {
    try {
      await impresora.imprimir(pedido);
    } catch (_) {
      aviso = 'El pedido pasó a preparación, pero no se pudo imprimir el ticket. '
          'Usá "Reimprimir".';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    super.dispose();
  }
}
