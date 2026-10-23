-- Inventario de insumos - Agua Clara La Muralla
-- Insumos: botellones vacios nuevos, tapones y sellos de garantia.
-- Descuento automatico SOLO al guardar el cierre de viaje (tabla viajes):
--   cada botellon vendido (Z1/Z2 publico/pulperia) -> -1 tapon, -1 sello
--   cada botellon nuevo con agua (L 150)          -> -1 botellon, -1 tapon, -1 sello
-- Si un cierre se corrige o se elimina, el inventario se ajusta por la diferencia.
-- Entradas (compras) y conteo fisico se registran con funciones, solo administrador.
-- Las existencias pueden quedar negativas: un cierre nunca se bloquea por inventario.

-- ===== Insumos =====
create table if not exists public.insumos (
    id text primary key,
    nombre text not null,
    existencia integer not null default 0,
    minimo integer not null default 0 check (minimo >= 0),
    orden smallint not null default 0,
    updated_at timestamptz not null default now()
);

insert into public.insumos (id, nombre, orden) values
    ('botellon', 'Botellones', 1),
    ('tapon', 'Tapones', 2),
    ('sello', 'Sellos de garantía', 3)
on conflict (id) do nothing;

alter table public.insumos enable row level security;
drop policy if exists "insumos_select_admin" on public.insumos;
create policy "insumos_select_admin" on public.insumos
    for select to authenticated using (public.es_administrador());
-- sin politicas de escritura: solo se modifica con las funciones de abajo

-- ===== Movimientos (historial) =====
create table if not exists public.insumo_movimientos (
    id uuid primary key default gen_random_uuid(),
    insumo_id text not null references public.insumos(id),
    tipo text not null check (tipo in ('entrada','conteo','cierre')),
    cantidad integer not null,              -- cambio con signo (+ suma, - resta)
    existencia_resultante integer not null,
    viaje_id uuid references public.viajes(id) on delete set null,
    nota text,
    usuario_id uuid default auth.uid(),
    usuario_nombre text,
    created_at timestamptz not null default now()
);

create index if not exists insumo_movimientos_insumo_fecha
    on public.insumo_movimientos (insumo_id, created_at desc);

alter table public.insumo_movimientos enable row level security;
drop policy if exists "insumo_mov_select_admin" on public.insumo_movimientos;
create policy "insumo_mov_select_admin" on public.insumo_movimientos
    for select to authenticated using (public.es_administrador());

-- ===== Aplicar un cambio (uso interno) =====
create or replace function public._insumo_aplicar(
    p_insumo text, p_cantidad integer, p_tipo text,
    p_viaje uuid, p_nota text, p_usuario_nombre text
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    v_resultante integer;
begin
    if coalesce(p_cantidad, 0) = 0 then
        return null;
    end if;

    update public.insumos
       set existencia = existencia + p_cantidad,
           updated_at = now()
     where id = p_insumo
    returning existencia into v_resultante;

    if v_resultante is null then
        raise exception 'Insumo % no existe', p_insumo;
    end if;

    insert into public.insumo_movimientos
        (insumo_id, tipo, cantidad, existencia_resultante, viaje_id, nota, usuario_nombre)
    values
        (p_insumo, p_tipo, p_cantidad, v_resultante, p_viaje, p_nota, p_usuario_nombre);

    return v_resultante;
end;
$$;

revoke all on function public._insumo_aplicar(text,integer,text,uuid,text,text) from public, anon, authenticated;

-- ===== Descuento automatico por cierre =====
create or replace function public.insumos_por_cierre()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_recargas_nuevo integer := 0;
    v_nuevos_nuevo integer := 0;
    v_recargas_viejo integer := 0;
    v_nuevos_viejo integer := 0;
    v_dif_tapa integer;
    v_dif_botellon integer;
    v_viaje uuid;
    v_nota text;
    v_quien text;
    r public.viajes;
begin
    if tg_op in ('INSERT','UPDATE') then
        v_recargas_nuevo := coalesce(new.zona1_publico,0) + coalesce(new.zona1_pulperia,0)
                          + coalesce(new.zona2_publico,0) + coalesce(new.zona2_pulperia,0);
        v_nuevos_nuevo := coalesce(new.botellon_nuevo,0);
    end if;
    if tg_op in ('UPDATE','DELETE') then
        v_recargas_viejo := coalesce(old.zona1_publico,0) + coalesce(old.zona1_pulperia,0)
                          + coalesce(old.zona2_publico,0) + coalesce(old.zona2_pulperia,0);
        v_nuevos_viejo := coalesce(old.botellon_nuevo,0);
    end if;

    -- tapones y sellos: todos los botellones vendidos; botellones: solo los nuevos
    v_dif_tapa := -((v_recargas_nuevo + v_nuevos_nuevo) - (v_recargas_viejo + v_nuevos_viejo));
    v_dif_botellon := -(v_nuevos_nuevo - v_nuevos_viejo);

    if v_dif_tapa = 0 and v_dif_botellon = 0 then
        return coalesce(new, old);
    end if;

    if tg_op = 'DELETE' then
        r := old; v_viaje := null;
    else
        r := new; v_viaje := new.id;
    end if;

    v_quien := coalesce(nullif(trim(r.chofer),''), 'Cierre');
    v_nota := 'Viaje #' || coalesce(r.numero_viaje::text,'?')
           || ' · ' || coalesce(nullif(trim(r.camion),''),'sin camión')
           || ' · ' || to_char(r.fecha,'DD/MM/YYYY')
           || case tg_op when 'UPDATE' then ' (cierre corregido)'
                         when 'DELETE' then ' (cierre eliminado)' else '' end;

    perform public._insumo_aplicar('tapon', v_dif_tapa, 'cierre', v_viaje, v_nota, v_quien);
    perform public._insumo_aplicar('sello', v_dif_tapa, 'cierre', v_viaje, v_nota, v_quien);
    perform public._insumo_aplicar('botellon', v_dif_botellon, 'cierre', v_viaje, v_nota, v_quien);

    return coalesce(new, old);
end;
$$;

revoke all on function public.insumos_por_cierre() from public, anon, authenticated;

drop trigger if exists viajes_insumos on public.viajes;
create trigger viajes_insumos
    after insert or update of zona1_publico, zona1_pulperia, zona2_publico, zona2_pulperia, botellon_nuevo
       or delete on public.viajes
    for each row execute function public.insumos_por_cierre();

-- ===== Entrada (compra) o conteo fisico - solo administrador =====
-- p_tipo = 'entrada': p_cantidad es lo que se suma (> 0)
-- p_tipo = 'conteo' : p_cantidad es lo que se conto fisicamente (>= 0); se ajusta la diferencia
create or replace function public.insumo_registrar(
    p_insumo text, p_tipo text, p_cantidad integer, p_nota text
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    v_actual integer;
    v_cambio integer;
    v_nombre text;
    v_nota text := nullif(trim(coalesce(p_nota,'')),'');
begin
    if not public.es_administrador() then
        raise exception 'Solo un administrador puede modificar el inventario.';
    end if;
    if p_tipo not in ('entrada','conteo') then
        raise exception 'Tipo de movimiento no válido.';
    end if;
    if p_cantidad is null or p_cantidad < 0 or (p_tipo = 'entrada' and p_cantidad = 0) then
        raise exception 'Escribe una cantidad válida.';
    end if;
    if p_cantidad > 1000000 then
        raise exception 'La cantidad es demasiado grande.';
    end if;
    if length(coalesce(v_nota,'')) > 300 then
        raise exception 'La nota es demasiado larga.';
    end if;

    select existencia into v_actual from public.insumos where id = p_insumo for update;
    if not found then
        raise exception 'Insumo no válido.';
    end if;

    select nombre into v_nombre from public.usuarios where id = auth.uid();

    if p_tipo = 'entrada' then
        v_cambio := p_cantidad;
    else
        v_cambio := p_cantidad - v_actual;
        v_nota := coalesce(v_nota || ' · ', '') || 'Conteo físico: ' || p_cantidad
                  || ' (sistema tenía ' || v_actual || ')';
        if v_cambio = 0 then
            -- dejar constancia del conteo aunque cuadre
            insert into public.insumo_movimientos
                (insumo_id, tipo, cantidad, existencia_resultante, nota, usuario_nombre)
            values (p_insumo, 'conteo', 0, v_actual, v_nota, v_nombre);
            return v_actual;
        end if;
    end if;

    return public._insumo_aplicar(p_insumo, v_cambio, p_tipo, null, v_nota, v_nombre);
end;
$$;

revoke all on function public.insumo_registrar(text,text,integer,text) from public, anon;
grant execute on function public.insumo_registrar(text,text,integer,text) to authenticated;

-- ===== Existencia minima para aviso - solo administrador =====
create or replace function public.insumo_definir_minimo(p_insumo text, p_minimo integer)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if not public.es_administrador() then
        raise exception 'Solo un administrador puede modificar el inventario.';
    end if;
    if p_minimo is null or p_minimo < 0 or p_minimo > 1000000 then
        raise exception 'Escribe un mínimo válido.';
    end if;
    update public.insumos set minimo = p_minimo, updated_at = now() where id = p_insumo;
    if not found then
        raise exception 'Insumo no válido.';
    end if;
end;
$$;

revoke all on function public.insumo_definir_minimo(text,integer) from public, anon;
grant execute on function public.insumo_definir_minimo(text,integer) to authenticated;
