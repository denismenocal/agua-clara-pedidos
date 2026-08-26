-- Actualización: varios municipios por ruta.
-- Ejecutar en Supabase > SQL Editor después de las actualizaciones anteriores.

create table if not exists public.ruta_municipios (
    id uuid primary key default gen_random_uuid(),
    ruta_id uuid not null references public.rutas(id) on delete cascade,
    municipio text not null,
    created_at timestamptz not null default now(),
    unique(ruta_id, municipio)
);

insert into public.ruta_municipios (ruta_id, municipio)
select id, upper(trim(municipio))
from public.rutas
where municipio is not null and trim(municipio) <> ''
on conflict (ruta_id, municipio) do nothing;

create index if not exists ruta_municipios_ruta_idx
    on public.ruta_municipios(ruta_id, municipio);

alter table public.ruta_municipios enable row level security;

drop policy if exists "ruta_municipios_select_autenticados" on public.ruta_municipios;
create policy "ruta_municipios_select_autenticados" on public.ruta_municipios
for select to authenticated using (true);

drop policy if exists "ruta_municipios_admin_escritura" on public.ruta_municipios;
create policy "ruta_municipios_admin_escritura" on public.ruta_municipios
for all to authenticated using (public.es_administrador())
with check (public.es_administrador());

grant select, insert, delete on public.ruta_municipios to authenticated;
