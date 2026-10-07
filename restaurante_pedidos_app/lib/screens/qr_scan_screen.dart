import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../config/qr_payload.dart';
import '../state/sesion_provider.dart';
import 'menu_screen.dart';
import 'union_manual_screen.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  bool _procesando = false;
  String? _error;

  Future<void> _alDetectar(BarcodeCapture captura) async {
    if (_procesando) return;
    final valor = captura.barcodes.first.rawValue;
    if (valor == null) return;

    final payload = QrPayload.parse(valor);
    if (payload == null) {
      setState(() => _error = 'Código QR no reconocido');
      return;
    }

    setState(() {
      _procesando = true;
      _error = null;
    });

    try {
      final sesion = context.read<SesionProvider>();
      await sesion.unirseDesdeQr(
        apiUrl: payload.apiBaseUrl,
        restaurante: payload.restauranteId,
        mesa: payload.mesaId,
      );
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MenuScreen()),
        );
      }
    } catch (e) {
      setState(() {
        _error = 'No se pudo unir a la mesa: $e';
        _procesando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escaneá el QR de tu mesa')),
      body: Stack(
        children: [
          MobileScanner(onDetect: _alDetectar),
          if (_procesando) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Positioned(
              bottom: 72,
              left: 16,
              right: 16,
              child: Material(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!, style: const TextStyle(color: Colors.white)),
                ),
              ),
            ),
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const UnionManualScreen()),
                ),
                child: const Text('Ingresar datos manualmente (modo prueba)'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
