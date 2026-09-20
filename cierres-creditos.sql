-- Ejecutar una sola vez en Supabase > SQL Editor.
-- Agrega el total y el detalle de las ventas a crédito de cada viaje.

alter table public.viajes
    add column if not exists total_credito numeric(12,2) not null default 0,
    add column if not exists detalle_credito text;

alter table public.viajes
    drop constraint if exists viajes_total_credito_no_negativo,
    add constraint viajes_total_credito_no_negativo check (total_credito >= 0);
