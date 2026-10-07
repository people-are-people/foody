import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/sesion_provider.dart';
import 'menu_screen.dart';

/// Pantalla de prueba: permite simular el escaneo de un QR escribiendo
/// los datos a mano. Útil mientras no hay impresos QR reales para
/// probar en un dispositivo o emulador. Marcada a propósito como "modo
/// prueba" — no debería quedar accesible así en producción.
class UnionManualScreen extends StatefulWidget {
  const UnionManualScreen({super.key});

  @override
  State<UnionManualScreen> createState() => _UnionManualScreenState();
}

class _UnionManualScreenState extends State<UnionManualScreen> {
  // 10.0.2.2 es el alias especial que usa el emulador de Android para
  // llegar al localhost de tu máquina. En el simulador de iOS, en
  // cambio, "localhost" funciona directo.
  final _apiCtrl = TextEditingController(text: 'http://10.0.2.2:3000/api/v1');
  final _restauranteCtrl = TextEditingController();
  final _mesaCtrl = TextEditingController();
  bool _cargando = false;
  String? _error;

  Future<void> _unirse() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await context.read<SesionProvider>().unirseDesdeQr(
            apiUrl: _apiCtrl.text.trim(),
            restaurante: _restauranteCtrl.text.trim(),
            mesa: _mesaCtrl.text.trim(),
          );
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MenuScreen()),
        );
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  void dispose() {
    _apiCtrl.dispose();
    _restauranteCtrl.dispose();
    _mesaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Unirse manualmente (modo prueba)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _apiCtrl,
              decoration: const InputDecoration(labelText: 'URL base de la API'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _restauranteCtrl,
              decoration: const InputDecoration(labelText: 'restauranteId'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _mesaCtrl,
              decoration: const InputDecoration(labelText: 'mesaId'),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            ElevatedButton(
              onPressed: _cargando ? null : _unirse,
              child: _cargando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Unirme'),
            ),
          ],
        ),
      ),
    );
  }
}
