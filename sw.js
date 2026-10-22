// Service worker de Agua Clara La Muralla
// - Permite instalar la app (clientes y personal)
// - Muestra las notificaciones push de pedidos nuevos (ver admin.html y notificar-pedido)

self.addEventListener("install", event => {
    self.skipWaiting();
});

self.addEventListener("activate", event => {
    event.waitUntil(self.clients.claim());
});

self.addEventListener("fetch", event => {
});

// Vibración de unos 2.5 segundos: largo, pausa, largo, pausa, largo
const VIBRACION_PEDIDO = [700, 250, 700, 250, 700];

self.addEventListener("push", event => {

    let datos = {};
    try {
        datos = event.data ? event.data.json() : {};
    } catch (e) {
        datos = { title: "💧 Nuevo pedido", body: event.data ? event.data.text() : "" };
    }

    const titulo = datos.title || "💧 Nuevo pedido";

    event.waitUntil(
        self.registration.showNotification(titulo, {
            body: datos.body || "Revisa la lista de pedidos.",
            icon: "img/icon-192.png",
            badge: "img/favicon_64.png",
            tag: datos.tag || "pedido-nuevo",
            renotify: true,
            requireInteraction: true,
            silent: false,
            vibrate: VIBRACION_PEDIDO,
            data: { url: datos.url || "/admin.html" }
        })
    );

});

self.addEventListener("notificationclick", event => {

    event.notification.close();
    const destino = new URL(
        (event.notification.data && event.notification.data.url) || "/admin.html",
        self.location.origin
    ).href;

    event.waitUntil((async () => {
        const ventanas = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
        for (const ventana of ventanas) {
            if (ventana.url.includes("/admin")) {
                await ventana.focus();
                try { await ventana.navigate(destino); } catch (e) {}
                return;
            }
        }
        await self.clients.openWindow(destino);
    })());

});
