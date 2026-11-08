import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/sesion_store.dart';
import '../state/cocina_provider.dart';

/// Se completa una sola vez por tablet: URL del servidor, restaurante y
/// usuario de cocina. Lo guardado se precarga la próxima vez.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // En el emulador de Android, "localhost" es el propio emulador: la PC se
  // alcanza con 10.0.2.2. En el navegador, localhost sí funciona.
  final _apiCtrl = TextEditingController(
    text: kIsWeb ? 'http://localhost:3000/api/v1' : 'http://10.0.2.2:3000/api/v1',
  );
  final _restauranteCtrl = TextEditingController();
  final _usuarioCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _precargar();
  }

  Future<void> _precargar() async {
    final config = await SesionStore().cargarConfig();
    if (!mounted) return;
    if (config['apiUrl']!.isNotEmpty) _apiCtrl.text = config['apiUrl']!;
    _restauranteCtrl.text = config['restauranteId']!;
    _usuarioCtrl.text = config['usuario']!;
  }

  @override
  void dispose() {
    _apiCtrl.dispose();
    _restauranteCtrl.dispose();
    _usuarioCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cocina = context.watch<CocinaProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Cocina · Iniciar sesión')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                  controller: _usuarioCtrl,
                  decoration: const InputDecoration(labelText: 'Usuario de cocina'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'PIN'),
                ),
                const SizedBox(height: 16),
                if (cocina.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(cocina.error!, style: const TextStyle(color: Colors.red)),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: cocina.ocupado
                        ? null
                        : () => cocina.iniciarSesion(
                              apiUrl: _apiCtrl.text,
                              restauranteId: _restauranteCtrl.text,
                              usuarioIngresado: _usuarioCtrl.text,
                              pin: _pinCtrl.text,
                            ),
                    child: cocina.ocupado
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Ingresar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
