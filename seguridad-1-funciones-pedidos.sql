-- Seguridad paso 1 - Agua Clara La Muralla
-- Funciones para la pagina publica de pedidos (index.html).
-- Permiten SOLO buscar un cliente por telefono, registrar un cliente Delivery y crear un pedido,
-- sin exponer las tablas completas a usuarios sin sesion.
-- YA APLICADO en Supabase el 22/10/2026 (migracion funciones_publicas_pedidos).

create or replace function public.pedido_buscar_cliente(p_telefono text)
returns table (id uuid, nombre text, municipio text, barrio text, referencia text)
language sql
stable
security definer
set search_path = public
as $$
    select c.id, c.nombre, c.municipio, c.barrio, c.referencia
    from public.clientes c
    where p_telefono ~ '^[0-9]{8}$'
      and c.telefono in (p_telefono, substr(p_telefono,1,4) || '-' || substr(p_telefono,5))
    limit 1;
$$;

create or replace function public.pedido_registrar_cliente(
    p_telefono text,
    p_nombre text,
    p_municipio text,
    p_barrio text,
    p_referencia text,
    p_latitud double precision,
    p_longitud double precision
)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    v_id uuid;
    v_municipio text := upper(trim(coalesce(p_municipio,'')));
begin
    if p_telefono is null or p_telefono !~ '^[0-9]{8}$' then
        raise exception 'El teléfono debe tener 8 dígitos.';
    end if;
    if coalesce(trim(p_nombre),'') = '' or coalesce(trim(p_barrio),'') = '' then
        raise exception 'Completa nombre y barrio.';
    end if;
    if v_municipio not in ('LA UNION','MANGULILE','YOCON','EL ROSARIO','SALAMA','SILCA','JANO') then
        raise exception 'Municipio no válido.';
    end if;
    if p_latitud is null or p_longitud is null
       or p_latitud not between -90 and 90 or p_longitud not between -180 and 180 then
        raise exception 'Comparte tu ubicación para poder realizar la entrega.';
    end if;
    if length(p_nombre) > 120 or length(p_barrio) > 120 or length(coalesce(p_referencia,'')) > 300 then
        raise exception 'Algún dato es demasiado largo.';
    end if;

    -- Evitar duplicados: si el telefono ya existe, devolver ese cliente
    select c.id into v_id
    from public.clientes c
    where c.telefono in (p_telefono, substr(p_telefono,1,4) || '-' || substr(p_telefono,5))
    limit 1;

    if v_id is not null then
        return v_id;
    end if;

    insert into public.clientes (telefono, nombre, municipio, barrio, referencia, latitud, longitud, tipo_cliente)
    values (p_telefono, upper(trim(p_nombre)), v_municipio, upper(trim(p_barrio)),
            nullif(upper(trim(coalesce(p_referencia,''))),''), p_latitud, p_longitud, 'Delivery')
    returning clientes.id into v_id;

    return v_id;
end;
$$;

create or replace function public.pedido_crear(
    p_cliente_id uuid,
    p_cantidad integer,
    p_comentario text
)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    v_id uuid;
begin
    if p_cliente_id is null or not exists (select 1 from public.clientes where id = p_cliente_id) then
        raise exception 'Primero verifica o registra tu número de celular.';
    end if;
    if p_cantidad is null or p_cantidad < 1 or p_cantidad > 100 then
        raise exception 'Selecciona una cantidad válida de botellones.';
    end if;
    if length(coalesce(p_comentario,'')) > 500 then
        raise exception 'El comentario es demasiado largo.';
    end if;

    insert into public.pedidos (cliente_id, cantidad, comentario)
    values (p_cliente_id, p_cantidad, nullif(trim(coalesce(p_comentario,'')),''))
    returning pedidos.id into v_id;

    return v_id;
end;
$$;

revoke all on function public.pedido_buscar_cliente(text) from public;
revoke all on function public.pedido_registrar_cliente(text,text,text,text,text,double precision,double precision) from public;
revoke all on function public.pedido_crear(uuid,integer,text) from public;

grant execute on function public.pedido_buscar_cliente(text) to anon, authenticated;
grant execute on function public.pedido_registrar_cliente(text,text,text,text,text,double precision,double precision) to anon, authenticated;
grant execute on function public.pedido_crear(uuid,integer,text) to anon, authenticated;
