// Edge Function: whatsapp-en-camino
// La llama el disparador pedidos_whatsapp_en_camino (ver whatsapp-en-camino.sql)
// cuando un pedido pasa a "En ruta". Envia al cliente la plantilla aprobada
// por Meta con la API oficial de WhatsApp (Cloud API).
//
// Configuracion: tabla integraciones_config (whatsapp_activo, whatsapp_phone_number_id,
// whatsapp_plantilla, whatsapp_idioma) y secreto WHATSAPP_TOKEN.
//
// Seguridad: no requiere JWT porque la llama la base de datos, pero solo actua
// sobre pedidos "En ruta" a los que aun no se les envio el mensaje, y como
// mucho una vez por pedido.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

const GRAPH = "https://graph.facebook.com/v23.0";

const respuesta = (cuerpo: unknown, estado = 200) =>
  new Response(JSON.stringify(cuerpo), {
    status: estado,
    headers: { "Content-Type": "application/json" },
  });

async function marcar(id: string, estado: string) {
  await supabase.from("pedidos").update({ whatsapp_estado: estado.slice(0, 300) }).eq("id", id);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return respuesta({ error: "metodo" }, 405);

  let pedidoId: string | undefined;
  try {
    pedidoId = (await req.json())?.pedido_id;
  } catch (_) { /* cuerpo invalido */ }
  if (!pedidoId || !/^[0-9a-f-]{36}$/i.test(pedidoId)) {
    return respuesta({ error: "pedido_id invalido" }, 400);
  }

  // Configuracion
  const { data: filas, error: errorConfig } = await supabase
    .from("integraciones_config")
    .select("clave, valor");
  if (errorConfig) return respuesta({ error: errorConfig.message }, 500);
  const c = Object.fromEntries((filas ?? []).map((f) => [f.clave, f.valor]));
  const token = Deno.env.get("WHATSAPP_TOKEN");

  if (c.whatsapp_activo !== "si" || !c.whatsapp_phone_number_id || !c.whatsapp_plantilla || !token) {
    // Apagado o sin configurar: no se reclama el pedido
    return respuesta({ omitido: "whatsapp no activo o sin configurar" });
  }

  // Reclamar el pedido de forma atomica (una sola vez por pedido)
  const { data: pedido, error: errorPedido } = await supabase
    .from("pedidos")
    .update({ whatsapp_at: new Date().toISOString(), whatsapp_estado: "enviando" })
    .eq("id", pedidoId)
    .eq("estado", "En ruta")
    .is("whatsapp_at", null)
    .select("id, cantidad, cliente_id")
    .maybeSingle();

  if (errorPedido) return respuesta({ error: errorPedido.message }, 500);
  if (!pedido) return respuesta({ omitido: "pedido no esta en ruta o ya se envio" });

  const { data: cliente } = await supabase
    .from("clientes")
    .select("nombre, telefono")
    .eq("id", pedido.cliente_id)
    .maybeSingle();

  let telefono = String(cliente?.telefono ?? "").replace(/\D/g, "");
  if (telefono.length === 11 && telefono.startsWith("504")) telefono = telefono.slice(3);
  if (telefono.length !== 8) {
    await marcar(pedido.id, "error: teléfono inválido");
    return respuesta({ error: "telefono invalido" });
  }

  const cantidad = Number(pedido.cantidad) || 1;
  const nombre = (cliente?.nombre || "cliente").trim();

  const envio = await fetch(`${GRAPH}/${c.whatsapp_phone_number_id}/messages`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      messaging_product: "whatsapp",
      to: `504${telefono}`,
      type: "template",
      template: {
        name: c.whatsapp_plantilla,
        language: { code: c.whatsapp_idioma || "es" },
        components: [{
          type: "body",
          parameters: [
            { type: "text", text: nombre },
            { type: "text", text: String(cantidad) },
          ],
        }],
      },
    }),
  });

  const resultado = await envio.json().catch(() => ({}));

  if (!envio.ok) {
    const detalle = resultado?.error?.error_user_msg || resultado?.error?.message || `HTTP ${envio.status}`;
    console.error("WhatsApp error", envio.status, JSON.stringify(resultado));
    await marcar(pedido.id, `error: ${detalle}`);
    return respuesta({ error: detalle }, 200);
  }

  await marcar(pedido.id, "enviado");
  return respuesta({ enviado: true, id: resultado?.messages?.[0]?.id });
});
