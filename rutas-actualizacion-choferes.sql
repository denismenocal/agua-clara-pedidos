-- Actualización: varios choferes por ruta y registro de clientes desde rutas.
-- Ejecutar en Supabase > SQL Editor después de rutas.sql.

create table if not exists public.ruta_choferes (
    id uuid primary key default gen_random_uuid(),
    ruta_id uuid not null references public.rutas(id) on delete cascade,
    usuario_id uuid not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default now(),
    unique(ruta_id, usuario_id)
);

insert into public.ruta_choferes (ruta_id, usuario_id)
select id, usuario_id
from public.rutas
where usuario_id is not null
on conflict (ruta_id, usuario_id) do nothing;

create index if not exists ruta_choferes_usuario_idx
    on public.ruta_choferes(usuario_id, ruta_id);

alter table public.ruta_choferes enable row level security;

create or replace function public.es_chofer_o_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from public.usuarios
        where id = auth.uid() and rol in ('chofer','administrador')
    );
$$;

drop policy if exists "ruta_choferes_select_autenticados" on public.ruta_choferes;
create policy "ruta_choferes_select_autenticados" on public.ruta_choferes
for select to authenticated using (true);

drop policy if exists "ruta_choferes_admin_escritura" on public.ruta_choferes;
create policy "ruta_choferes_admin_escritura" on public.ruta_choferes
for all to authenticated using (public.es_administrador())
with check (public.es_administrador());

drop policy if exists "ruta_clientes_chofer_insert" on public.ruta_clientes;
create policy "ruta_clientes_chofer_insert" on public.ruta_clientes
for insert to authenticated with check (
    exists (
        select 1 from public.ruta_choferes rc
        where rc.ruta_id = ruta_clientes.ruta_id
          and rc.usuario_id = auth.uid()
    )
);

drop policy if exists "jornadas_select_propias_o_admin" on public.ruta_jornadas;
create policy "jornadas_select_propias_o_admin" on public.ruta_jornadas
for select to authenticated using (
    usuario_id = auth.uid() or public.es_administrador() or exists (
        select 1 from public.ruta_choferes rc
        where rc.ruta_id = ruta_jornadas.ruta_id
          and rc.usuario_id = auth.uid()
    )
);

drop policy if exists "jornadas_insert_propias_o_admin" on public.ruta_jornadas;
create policy "jornadas_insert_propias_o_admin" on public.ruta_jornadas
for insert to authenticated with check (
    usuario_id = auth.uid() or public.es_administrador()
);

drop policy if exists "jornadas_update_propias_o_admin" on public.ruta_jornadas;
create policy "jornadas_update_propias_o_admin" on public.ruta_jornadas
for update to authenticated using (
    usuario_id = auth.uid() or public.es_administrador() or exists (
        select 1 from public.ruta_choferes rc
        where rc.ruta_id = ruta_jornadas.ruta_id
          and rc.usuario_id = auth.uid()
    )
) with check (
    usuario_id = auth.uid() or public.es_administrador() or exists (
        select 1 from public.ruta_choferes rc
        where rc.ruta_id = ruta_jornadas.ruta_id
          and rc.usuario_id = auth.uid()
    )
);

drop policy if exists "visitas_select_propias_o_admin" on public.ruta_visitas;
create policy "visitas_select_propias_o_admin" on public.ruta_visitas
for select to authenticated using (
    public.es_administrador() or exists (
        select 1
        from public.ruta_jornadas j
        left join public.ruta_choferes rc
            on rc.ruta_id = j.ruta_id and rc.usuario_id = auth.uid()
        where j.id = jornada_id
          and (j.usuario_id = auth.uid() or rc.usuario_id is not null)
    )
);

drop policy if exists "visitas_insert_propias_o_admin" on public.ruta_visitas;
create policy "visitas_insert_propias_o_admin" on public.ruta_visitas
for insert to authenticated with check (
    public.es_administrador() or exists (
        select 1
        from public.ruta_jornadas j
        left join public.ruta_choferes rc
            on rc.ruta_id = j.ruta_id and rc.usuario_id = auth.uid()
        where j.id = jornada_id
          and (j.usuario_id = auth.uid() or rc.usuario_id is not null)
    )
);

drop policy if exists "visitas_update_propias_o_admin" on public.ruta_visitas;
create policy "visitas_update_propias_o_admin" on public.ruta_visitas
for update to authenticated using (
    public.es_administrador() or exists (
        select 1
        from public.ruta_jornadas j
        left join public.ruta_choferes rc
            on rc.ruta_id = j.ruta_id and rc.usuario_id = auth.uid()
        where j.id = jornada_id
          and (j.usuario_id = auth.uid() or rc.usuario_id is not null)
    )
) with check (
    public.es_administrador() or exists (
        select 1
        from public.ruta_jornadas j
        left join public.ruta_choferes rc
            on rc.ruta_id = j.ruta_id and rc.usuario_id = auth.uid()
        where j.id = jornada_id
          and (j.usuario_id = auth.uid() or rc.usuario_id is not null)
    )
);

-- Esta política se suma a las políticas existentes de clientes.
drop policy if exists "choferes_crean_clientes_ruta" on public.clientes;
create policy "choferes_crean_clientes_ruta" on public.clientes
for insert to authenticated with check (
    public.es_chofer_o_admin()
);

grant select, insert, delete on public.ruta_choferes to authenticated;
grant insert on public.clientes to authenticated;
grant execute on function public.es_chofer_o_admin() to authenticated;
