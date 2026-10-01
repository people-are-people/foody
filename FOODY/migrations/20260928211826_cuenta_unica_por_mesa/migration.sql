CREATE UNIQUE INDEX una_cuenta_abierta_por_mesa
  ON cuentas (mesa_id) WHERE estado = 'abierta';