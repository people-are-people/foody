class SesionMesa {
  final String cuentaId;
  final String rol; // "dueño" | "espectador"
  final String? sesionToken; // solo presente si rol == "dueño"
  final String estadoCuenta;

  SesionMesa({
    required this.cuentaId,
    required this.rol,
    this.sesionToken,
    required this.estadoCuenta,
  });

  bool get esDueno => rol == 'dueño';

  factory SesionMesa.fromJson(Map<String, dynamic> json) {
    return SesionMesa(
      cuentaId: json['cuenta_id'] as String,
      rol: json['rol'] as String,
      sesionToken: json['sesion_token'] as String?,
      estadoCuenta: json['estado_cuenta'] as String,
    );
  }
}
