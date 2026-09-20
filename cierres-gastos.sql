-- Ejecutar una sola vez en Supabase > SQL Editor.
-- Agrega los gastos del viaje al cierre existente.

alter table public.viajes
    add column if not exists gasto_combustible numeric(12,2) not null default 0,
    add column if not exists gasto_reparaciones numeric(12,2) not null default 0,
    add column if not exists gasto_otros numeric(12,2) not null default 0,
    add column if not exists total_gastos numeric(12,2) not null default 0,
    add column if not exists detalle_gastos text;

alter table public.viajes
    drop constraint if exists viajes_gasto_combustible_no_negativo,
    add constraint viajes_gasto_combustible_no_negativo check (gasto_combustible >= 0),
    drop constraint if exists viajes_gasto_reparaciones_no_negativo,
    add constraint viajes_gasto_reparaciones_no_negativo check (gasto_reparaciones >= 0),
    drop constraint if exists viajes_gasto_otros_no_negativo,
    add constraint viajes_gasto_otros_no_negativo check (gasto_otros >= 0),
    drop constraint if exists viajes_total_gastos_no_negativo,
    add constraint viajes_total_gastos_no_negativo check (total_gastos >= 0);
