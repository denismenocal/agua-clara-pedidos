-- WhatsApp automatico "tu pedido va en camino" - Agua Clara La Muralla
-- Cuando un pedido pasa a "En ruta", un disparador llama a la Edge Function
-- "whatsapp-en-camino", que envia una plantilla aprobada por Meta al cliente
-- usando la API oficial de WhatsApp (Cloud API).
--
-- Configuracion no secreta en integraciones_config (sin acceso para anon/authenticated):
--   whatsapp_activo            'si' para encender, cualquier otro valor lo apaga
--   whatsapp_phone_number_id   ID del numero en Meta (no es secreto)
--   whatsapp_plantilla         nombre de la plantilla aprobada (ej. pedido_en_camino)
--   whatsapp_idioma            codigo de idioma de la plantilla (ej. es)
-- El token de acceso de Meta va como secreto de Edge Function: WHATSAPP_TOKEN
-- (nunca en el repositorio ni en tablas).

create extension if not exists pg_net with schema extensions;

-- ===== Estado del mensaje en cada pedido =====
alter table public.pedidos add column if not exists whatsapp_estado text;
alter table public.pedidos add column if not exists whatsapp_at timestamptz;

-- ===== Configuracion privada de integraciones =====
create table if not exists public.integraciones_config (
    clave text primary key,
    valor text not null
);
alter table public.integraciones_config enable row level security;
-- sin politicas: solo las Edge Functions (service role) pueden leerla
revoke all on public.integraciones_config from anon, authenticated;

insert into public.integraciones_config (clave, valor) values
    ('whatsapp_activo', 'no'),
    ('whatsapp_plantilla', 'pedido_en_camino'),
    ('whatsapp_idioma', 'es')
on conflict (clave) do nothing;

-- ===== Disparador al pasar a "En ruta" =====
create or replace function public.whatsapp_pedido_en_camino()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
    if new.estado = 'En ruta'
       and old.estado is distinct from 'En ruta'
       and new.whatsapp_at is null then
        begin
            perform net.http_post(
                url := 'https://ayzddkcxeswjfpinwvth.supabase.co/functions/v1/whatsapp-en-camino',
                body := jsonb_build_object('pedido_id', new.id),
                headers := '{"Content-Type":"application/json"}'::jsonb,
                timeout_milliseconds := 15000
            );
        exception when others then
            -- Nunca impedir el cambio de estado por un problema con WhatsApp
            raise warning 'No se pudo solicitar el WhatsApp del pedido %: %', new.id, sqlerrm;
        end;
    end if;
    return new;
end;
$$;

revoke all on function public.whatsapp_pedido_en_camino() from public, anon, authenticated;

drop trigger if exists pedidos_whatsapp_en_camino on public.pedidos;
create trigger pedidos_whatsapp_en_camino
    after update of estado on public.pedidos
    for each row execute function public.whatsapp_pedido_en_camino();
