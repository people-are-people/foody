import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'state/sesion_provider.dart';
import 'screens/gracias_screen.dart';
import 'screens/menu_screen.dart';
import 'screens/qr_scan_screen.dart';

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

/// Única pantalla que decide qué se muestra, según el estado de la sesión:
/// agradecimiento (cuenta cerrada), menú (hay sesión) o escaneo (no hay).
/// Las demás pantallas no navegan entre sí para que esto siempre pueda reaccionar.
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

    final sesion = context.watch<SesionProvider>();

    if (sesion.cuentaCerrada) {
      // Si había algo abierto encima (el resumen del pedido, un diálogo),
      // se cierra para que el agradecimiento no quede tapado.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      });
      return const GraciasScreen();
    }

    return sesion.tieneSesion ? const MenuScreen() : const QrScanScreen();
  }
}