-- Vacía solo los pedidos y su historial de eventos.
TRUNCATE TABLE pedido_items, pedidos, eventos;

-- Libera las mesas que hayan quedado con una cuenta abierta.
UPDATE cuentas SET estado = 'cerrada', cerrada_en = now() WHERE estado = 'abierta';