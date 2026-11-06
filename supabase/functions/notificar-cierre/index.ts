// Edge Function: notificar-cierre
// La llama el disparador viajes_notificar_cierre (ver notificaciones-cierre.sql) al guardar un cierre.
// Envia a los ADMINISTRADORES suscritos un resumen del cierre:
//   total vendido, gastos, creditos, venta neta (vendido - gastos - creditos),
//   transferencia a cuenta y efectivo esperado (venta neta - transferencia).
//
// Seguridad: no requiere JWT porque la llama la base de datos, pero solo actua sobre
// cierres guardados hace menos de 10 minutos y que aun no fueron notificados.

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

const lempiras = (n: number) =>
  "L " + n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

Deno.serve(async (req) => {
  if (req.method !== "POST") return respuesta({ error: "metodo" }, 405);

  let viajeId: string | undefined;
  try {
    viajeId = (await req.json())?.viaje_id;
  } catch (_) { /* cuerpo invalido */ }
  if (!viajeId || !/^[0-9a-f-]{36}$/i.test(viajeId)) {
    return respuesta({ error: "viaje_id invalido" }, 400);
  }

  // Reclamar el cierre de forma atomica: solo si es reciente y no fue notificado
  const hace10min = new Date(Date.now() - 10 * 60 * 1000).toISOString();
  const { data: viaje, error: errorViaje } = await supabase
    .from("viajes")
    .update({ notificado_at: new Date().toISOString() })
    .eq("id", viajeId)
    .is("notificado_at", null)
    .gte("created_at", hace10min)
    .select("id, fecha, camion, chofer, numero_viaje, total_venta, total_gastos, total_credito, total_transferencia, efectivo_entregado, diferencia")
    .maybeSingle();

  if (errorViaje) return respuesta({ error: errorViaje.message }, 500);
  if (!viaje) return respuesta({ omitido: "cierre no encontrado, viejo o ya notificado" });

  // Llaves VAPID
  const { data: config, error: errorConfig } = await supabase
    .from("push_config")
    .select("clave, valor");
  if (errorConfig) return respuesta({ error: errorConfig.message }, 500);
  const c = Object.fromEntries((config ?? []).map((f) => [f.clave, f.valor]));
  webpush.setVapidDetails(c.vapid_sujeto, c.vapid_publica, c.vapid_privada);

  // Solo administradores
  const { data: admins } = await supabase
    .from("usuarios")
    .select("id")
    .eq("rol", "administrador");
  const ids = (admins ?? []).map((u) => u.id);
  if (!ids.length) return respuesta({ enviados: 0 });

  const { data: suscripciones } = await supabase
    .from("push_suscripciones")
    .select("id, endpoint, p256dh, auth")
    .in("usuario_id", ids);

  const vendido = Number(viaje.total_venta) || 0;
  const gastos = Number(viaje.total_gastos) || 0;
  const creditos = Number(viaje.total_credito) || 0;
  const neta = vendido - gastos - creditos;
  const transferencia = Number(viaje.total_transferencia) || 0;
  const esperado = neta - transferencia;

  const quien = [viaje.camion, viaje.chofer].filter(Boolean).join(" · ");
  const mensaje = {
    title: `🧾 Cierre viaje #${viaje.numero_viaje ?? "?"}${quien ? " · " + quien : ""}`,
    body:
      `Total vendido: ${lempiras(vendido)}\n` +
      `Gastos + créditos: ${lempiras(gastos + creditos)} (G ${lempiras(gastos)} · C ${lempiras(creditos)})\n` +
      `Venta neta: ${lempiras(neta)}\n` +
      `Transferencia: ${lempiras(transferencia)}\n` +
      `Efectivo esperado: ${lempiras(esperado)} · Entregado: ${lempiras(Number(viaje.efectivo_entregado) || 0)}`,
    tag: `cierre-${viaje.id}`,
    url: "/menu.html",
  };

  let enviados = 0;
  const vencidas: string[] = [];

  await Promise.all((suscripciones ?? []).map(async (s) => {
    try {
      await webpush.sendNotification(
        { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
        JSON.stringify(mensaje),
        { TTL: 6 * 60 * 60, urgency: "high" },
      );
      enviados++;
    } catch (e) {
      const codigo = (e as { statusCode?: number }).statusCode;
      if (codigo === 404 || codigo === 410) vencidas.push(s.id);
      else console.error("Error enviando push", codigo, (e as Error).message);
    }
  }));

  if (vencidas.length) {
    await supabase.from("push_suscripciones").delete().in("id", vencidas);
  }

  return respuesta({ enviados, vencidas: vencidas.length });
});
