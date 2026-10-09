import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:restaurante_pedidos_app/main.dart';

void main() {
  testWidgets('La app arranca sin tirar error', (WidgetTester tester) async {
    // Sin esto, SesionProvider explota al intentar leer SharedPreferences
    // en el entorno de test (no hay un dispositivo real detrás).
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const App());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}