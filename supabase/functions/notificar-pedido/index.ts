// Edge Function: notificar-pedido
// La llama el disparador pedidos_notificar_nuevo (ver notificaciones-push.sql) al entrar un pedido.
// Envia una notificacion push a todos los celulares suscritos de choferes y administradores.
//
// Seguridad: no requiere JWT porque la llama la base de datos, pero solo actua sobre
// pedidos creados hace menos de 5 minutos y que aun no fueron notificados, asi que
// llamarla desde afuera no permite repetir ni inventar notificaciones.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

const respuesta = (cuerpo: unknown, estado = 200) =>
  new Response(JSON.stringify(cuerpo), {
    status: estado,
    headers: { "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method !== "POST") return respuesta({ error: "metodo" }, 405);

  let pedidoId: string | undefined;
  try {
    pedidoId = (await req.json())?.pedido_id;
  } catch (_) { /* cuerpo invalido */ }
  if (!pedidoId || !/^[0-9a-f-]{36}$/i.test(pedidoId)) {
    return respuesta({ error: "pedido_id invalido" }, 400);
  }

  // Reclamar el pedido de forma atomica: solo si es reciente y no fue notificado
  const hace5min = new Date(Date.now() - 5 * 60 * 1000).toISOString();
  const { data: pedido, error: errorPedido } = await supabase
    .from("pedidos")
    .update({ notificado_at: new Date().toISOString() })
    .eq("id", pedidoId)
    .is("notificado_at", null)
    .gte("fecha", hace5min)
    .select("id, cantidad, comentario, cliente_id")
    .maybeSingle();

  if (errorPedido) return respuesta({ error: errorPedido.message }, 500);
  if (!pedido) return respuesta({ omitido: "pedido no encontrado, viejo o ya notificado" });

  const { data: cliente } = await supabase
    .from("clientes")
    .select("nombre, municipio, barrio")
    .eq("id", pedido.cliente_id)
    .maybeSingle();

  // Llaves VAPID
  const { data: config, error: errorConfig } = await supabase
    .from("push_config")
    .select("clave, valor");
  if (errorConfig) return respuesta({ error: errorConfig.message }, 500);
  const c = Object.fromEntries((config ?? []).map((f) => [f.clave, f.valor]));
  webpush.setVapidDetails(c.vapid_sujeto, c.vapid_publica, c.vapid_privada);

  // Celulares de choferes y administradores
  const { data: personal } = await supabase
    .from("usuarios")
    .select("id")
    .in("rol", ["administrador", "chofer"]);
  const ids = (personal ?? []).map((u) => u.id);
  if (!ids.length) return respuesta({ enviados: 0 });

  const { data: suscripciones } = await supabase
    .from("push_suscripciones")
    .select("id, endpoint, p256dh, auth")
    .in("usuario_id", ids);

  const cantidad = Number(pedido.cantidad) || 1;
  const nombre = cliente?.nombre || "Cliente";
  const lugar = [cliente?.barrio, cliente?.municipio].filter(Boolean).join(", ");
  const mensaje = {
    title: "💧 Nuevo pedido",
    body: `${nombre} · ${cantidad} ${cantidad === 1 ? "botellón" : "botellones"}` +
      (lugar ? `\n${lugar}` : "") +
      (pedido.comentario ? `\n“${pedido.comentario}”` : ""),
    tag: `pedido-${pedido.id}`,
    url: "/admin.html",
  };

  let enviados = 0;
  const vencidas: string[] = [];

  await Promise.all((suscripciones ?? []).map(async (s) => {
    try {
      await webpush.sendNotification(
        { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
        JSON.stringify(mensaje),
        { TTL: 60 * 60, urgency: "high" },
      );
      enviados++;
    } catch (e) {
      const codigo = (e as { statusCode?: number }).statusCode;
      if (codigo === 404 || codigo === 410) vencidas.push(s.id);
      else console.error("Error enviando push", codigo, (e as Error).message);
    }
  }));

  // Borrar suscripciones de celulares que ya no existen o quitaron el permiso
  if (vencidas.length) {
    await supabase.from("push_suscripciones").delete().in("id", vencidas);
  }

  return respuesta({ enviados, vencidas: vencidas.length });
});
