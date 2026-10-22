# Agua Clara La Muralla — Sistema de pedidos y reparto

Contexto para trabajar en este repositorio. Fuente: resumen integral del proyecto (octubre 2026) y revisión del código.

## Arquitectura
- Frontend: archivos HTML autónomos con CSS y JS integrados. Sin framework ni build.
- Datos y login: Supabase (proyecto `ayzddkcxeswjfpinwvth`, "AguaClara_Muralla Project"). Cliente en `js/supabase.js` con la clave **publicable** (puede estar en el frontend). Nunca poner la `service_role` ni otras claves secretas en el repo: el repo es **público**.
- Publicación: Cloudflare Pages despliega automáticamente cada push a `main` → https://agua-clara-pedidos.pages.dev
- App instalable: `manifest.json` (personal, abre en login) y `manifest-clientes.json` (clientes, abre en `index.html`, con aviso de instalación para Android e iPhone) + `sw.js` (service worker básico, sin caché).

## Notificaciones push de pedidos
- `admin.html` tiene el panel "Recibe los pedidos en tu celular": suscribe el celular y lo guarda en `push_suscripciones`.
- Al insertar en `pedidos`, el disparador `pedidos_notificar_nuevo` llama (pg_net) a la Edge Function `notificar-pedido` (código en `supabase/functions/notificar-pedido/`), que envía el push a choferes y administradores y marca `pedidos.notificado_at`.
- `sw.js` muestra la notificación (vibración ~2.5 s, se queda en la cortina hasta tocarla).
- Llaves VAPID: la pública está en `admin.html`; la privada solo en la tabla `push_config` (sin acceso para anon/authenticated). Nunca ponerla en el repo.
- iPhone: solo funciona con la app instalada en la pantalla de inicio (iOS 16.4+). La vibración y el sonido los decide iOS.
- SQL: `notificaciones-push.sql`.

## Forma de trabajar (obligatoria)
- Cambios pequeños y verificables.
- Si un cambio necesita columnas, tablas o funciones nuevas: **primero el SQL en Supabase, después publicar la interfaz**, para que la app activa nunca intente usar algo que no existe.
- Guardar cada cambio de base de datos también como archivo `.sql` en el repo, escrito para poder ejecutarse más de una vez (`if not exists`, `create or replace`, `drop policy if exists`).
- Principio: todo cambio debe mantener sincronizados inventario, dinero, permisos, usuario responsable y trazabilidad. Un producto, gasto, crédito o estado nuevo debe reflejarse en la captura, en el cierre y en los reportes.

## Roles
- `usuarios.rol`: `administrador` (acceso completo) o `chofer` (pedidos/reparto, ruta del día, alta de clientes de ruta, cierre de viajes).
- Exclusivo de administrador: facturación, mayoristas, consulta de clientes, reportes, configuración de rutas, gastos y créditos.
- Las páginas verifican la sesión y el menú filtra por rol, pero **la protección real son las políticas RLS**. Funciones auxiliares: `es_administrador()`, `es_chofer_o_admin()`.
- La página pública `index.html` no tiene sesión: solo usa las funciones `pedido_buscar_cliente`, `pedido_registrar_cliente` y `pedido_crear` (ver `seguridad-1-funciones-pedidos.sql`). No debe leer ni escribir tablas directamente.

## Reglas de negocio
- Textos normalizados en MAYÚSCULAS.
- Municipios permitidos: LA UNION, MANGULILE, YOCON, EL ROSARIO, SALAMA, SILCA, JANO.
- Teléfono: 8 dígitos (en datos viejos puede estar guardado como `0000-0000`).
- Clientes tipo tienda: ubicación GPS y nombre de negocio obligatorios. Delivery solo para clientes creados desde pedidos.
- Facturación: no se agregan productos sin cliente o Consumidor Final; al agregar productos se bloquea el cambio de cliente. Consumidor Final = `CONSUMIDOR FINAL`, RTN `99999999999999`. El usuario conectado queda como vendedor. Solo tiendas activas y configuradas.
- Precios (actualmente escritos en el código):
  - Botellón Z1 público L 40 · Z1 pulpería L 35 · Z2 público L 35 · Z2 pulpería L 30
  - Botellón nuevo con agua L 150 · Pack agua en bolsa L 25 · Juguitos L 25 · Hielo L 25
- Cierre de viaje: toma conductor y camión de la sesión. Vendidos ≤ cargados; vendidos + regalados ≤ carga.
- Gastos: tipos Combustible, Reparación, Posta La Unión, Posta Yocón, Otro gasto. Montos > 0; "Otro" exige descripción. Las postas se suman en `viajes.gasto_otros` pero conservan su nombre en el detalle.
- Créditos (cliente actual: MUNICIPALIDAD LA UNION): botellón L 40, pack bolsa L 25. Son parte de lo vendido (también cuentan en ventas normales); no pueden superar lo vendido de ese producto.
- **Efectivo esperado = Venta total − Gastos − Ventas a crédito**
- **Diferencia de caja = Efectivo entregado − Efectivo esperado**
- **Venta neta = Total vendido − Gastos − Créditos**
- Gastos + créditos no pueden superar la venta total.

## Tablas principales
`usuarios`, `clientes`, `clientes_mayoristas`, `pedidos`, `productos`, `configuracion`, `empresa`, `cai_facturacion`, `facturas`, `factura_detalle`, `viajes`, `rutas`, `ruta_municipios`, `ruta_choferes`, `ruta_clientes`, `ruta_jornadas`, `ruta_visitas`.

## Pendientes conocidos
- Mover precios del código a una tabla de configuración.
- Guardar factura + detalle + CAI en una sola función atómica (RPC).
- Gastos y créditos en tablas de detalle propias.
- Notificación por WhatsApp con proveedor oficial.
- Copias de seguridad, ambiente de pruebas y pruebas de regresión antes de cambios grandes.
