import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'state/sesion_provider.dart';
import 'screens/qr_scan_screen.dart';
import 'screens/menu_screen.dart';

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SesionProvider(),
      child: MaterialApp(
        title: 'Pedidos del restaurante',
        theme: ThemeData(colorSchemeSeed: Colors.deepOrange, useMaterial3: true),
        home: const _PantallaInicial(),
      ),
    );
  }
}

/// Al abrir la app, primero intenta restaurar una sesión de mesa
/// guardada (ver SesionStore). Si no hay ninguna, manda a escanear.
class _PantallaInicial extends StatefulWidget {
  const _PantallaInicial();

  @override
  State<_PantallaInicial> createState() => _PantallaInicialState();
}

class _PantallaInicialState extends State<_PantallaInicial> {
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _restaurar();
  }

  Future<void> _restaurar() async {
    await context.read<SesionProvider>().intentarRestaurarSesion();
    if (mounted) setState(() => _cargando = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final tieneSesion = context.watch<SesionProvider>().tieneSesion;
    return tieneSesion ? const MenuScreen() : const QrScanScreen();
  }
}
