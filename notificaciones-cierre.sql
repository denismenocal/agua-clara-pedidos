-- Notificacion push de cierres de viaje - Agua Clara La Muralla
-- Al guardar un cierre nuevo (insert en viajes), un disparador llama a la
-- Edge Function "notificar-cierre", que envia a los ADMINISTRADORES suscritos
-- un resumen: total vendido, gastos, creditos y venta neta.
-- Usa las mismas suscripciones y llaves VAPID que notificaciones-push.sql.

create extension if not exists pg_net with schema extensions;

-- Marca para no notificar dos veces el mismo cierre
alter table public.viajes add column if not exists notificado_at timestamptz;

create or replace function public.notificar_cierre_nuevo()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
    begin
        perform net.http_post(
            url := 'https://ayzddkcxeswjfpinwvth.supabase.co/functions/v1/notificar-cierre',
            body := jsonb_build_object('viaje_id', new.id),
            headers := '{"Content-Type":"application/json"}'::jsonb,
            timeout_milliseconds := 10000
        );
    exception when others then
        -- Nunca impedir que se guarde un cierre por un problema con la notificacion
        raise warning 'No se pudo solicitar la notificacion del cierre %: %', new.id, sqlerrm;
    end;
    return new;
end;
$$;

revoke all on function public.notificar_cierre_nuevo() from public, anon, authenticated;

drop trigger if exists viajes_notificar_cierre on public.viajes;
create trigger viajes_notificar_cierre
    after insert on public.viajes
    for each row execute function public.notificar_cierre_nuevo();
