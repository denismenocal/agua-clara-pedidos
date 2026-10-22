-- Notificaciones push de pedidos nuevos - Agua Clara La Muralla
-- Cada celular del personal que activa las notificaciones queda en push_suscripciones.
-- Al entrar un pedido, un disparador llama a la Edge Function "notificar-pedido",
-- que envia la notificacion a todos los celulares suscritos de choferes y administradores.
-- Las llaves VAPID privadas viven en push_config (sin acceso para anon/authenticated)
-- y NUNCA se guardan en el repositorio.

create extension if not exists pg_net with schema extensions;

-- ===== Suscripciones de cada celular =====
create table if not exists public.push_suscripciones (
    id uuid primary key default gen_random_uuid(),
    usuario_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
    endpoint text not null unique,
    p256dh text not null,
    auth text not null,
    dispositivo text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.push_suscripciones enable row level security;

drop policy if exists "push_select_propias" on public.push_suscripciones;
create policy "push_select_propias" on public.push_suscripciones
    for select to authenticated using (usuario_id = auth.uid());

drop policy if exists "push_insert_personal" on public.push_suscripciones;
create policy "push_insert_personal" on public.push_suscripciones
    for insert to authenticated with check (usuario_id = auth.uid() and public.es_chofer_o_admin());

drop policy if exists "push_update_propias" on public.push_suscripciones;
create policy "push_update_propias" on public.push_suscripciones
    for update to authenticated using (usuario_id = auth.uid()) with check (usuario_id = auth.uid());

drop policy if exists "push_delete_propias" on public.push_suscripciones;
create policy "push_delete_propias" on public.push_suscripciones
    for delete to authenticated using (usuario_id = auth.uid());

-- ===== Configuracion privada (llaves VAPID) =====
create table if not exists public.push_config (
    clave text primary key,
    valor text not null
);
alter table public.push_config enable row level security;
-- sin politicas: solo la Edge Function (service role) puede leerla
revoke all on public.push_config from anon, authenticated;

-- ===== Marca para no notificar dos veces el mismo pedido =====
alter table public.pedidos add column if not exists notificado_at timestamptz;

-- ===== Disparador al crear un pedido =====
create or replace function public.notificar_pedido_nuevo()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
    begin
        perform net.http_post(
            url := 'https://ayzddkcxeswjfpinwvth.supabase.co/functions/v1/notificar-pedido',
            body := jsonb_build_object('pedido_id', new.id),
            headers := '{"Content-Type":"application/json"}'::jsonb,
            timeout_milliseconds := 10000
        );
    exception when others then
        -- Nunca impedir que se guarde un pedido por un problema con la notificacion
        raise warning 'No se pudo solicitar la notificacion del pedido %: %', new.id, sqlerrm;
    end;
    return new;
end;
$$;

revoke all on function public.notificar_pedido_nuevo() from public, anon, authenticated;

drop trigger if exists pedidos_notificar_nuevo on public.pedidos;
create trigger pedidos_notificar_nuevo
    after insert on public.pedidos
    for each row execute function public.notificar_pedido_nuevo();

-- Las llaves se cargan aparte (no en este archivo):
-- insert into public.push_config (clave, valor) values
--   ('vapid_publica', '...'), ('vapid_privada', '...'), ('vapid_sujeto', 'https://agua-clara-pedidos.pages.dev')
-- on conflict (clave) do update set valor = excluded.valor;
