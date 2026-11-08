import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/login_screen.dart';
import 'screens/tablero_screen.dart';
import 'services/impresora_tickets.dart';
import 'state/cocina_provider.dart';

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      // Cuando esté la impresora real, se reemplaza ImpresoraSimulada() por
      // la clase nueva que implemente ImpresoraTickets. Es el único cambio.
      create: (_) => CocinaProvider(impresora: ImpresoraSimulada()),
      child: MaterialApp(
        title: 'Cocina',
        theme: ThemeData(colorSchemeSeed: Colors.deepOrange, useMaterial3: true),
        home: const _Inicio(),
      ),
    );
  }
}

/// Al abrir, intenta retomar la sesión guardada; si no hay, va al login.
class _Inicio extends StatefulWidget {
  const _Inicio();

  @override
  State<_Inicio> createState() => _InicioState();
}

class _InicioState extends State<_Inicio> {
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _restaurar();
  }

  Future<void> _restaurar() async {
    await context.read<CocinaProvider>().intentarRestaurarSesion();
    if (mounted) setState(() => _cargando = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final tieneSesion = context.watch<CocinaProvider>().tieneSesion;
    return tieneSesion ? const TableroScreen() : const LoginScreen();
  }
}
