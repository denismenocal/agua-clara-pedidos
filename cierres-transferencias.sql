-- Se puede ejecutar más de una vez en Supabase > SQL Editor.
-- Agrega al cierre de viaje el dinero recibido por transferencia a cuenta.
-- Efectivo esperado = Venta total − Gastos − Créditos − Transferencias.
-- (El tipo de gasto "Descuento" no necesita columna: se suma en gasto_otros
--  y conserva su nombre en detalle_gastos, igual que las postas.)

alter table public.viajes
    add column if not exists total_transferencia numeric(12,2) not null default 0;

alter table public.viajes
    drop constraint if exists viajes_total_transferencia_no_negativo,
    add constraint viajes_total_transferencia_no_negativo check (total_transferencia >= 0);
