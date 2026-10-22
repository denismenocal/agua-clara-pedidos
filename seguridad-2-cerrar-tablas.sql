-- Seguridad paso 2 - Agua Clara La Muralla
-- Cierra las tablas que estaban abiertas a cualquier persona sin sesion.
-- Requisito: index.html ya usa las funciones de seguridad-1-funciones-pedidos.sql.
-- ESTADO: APLICADO en Supabase el 22/10/2026 (ejecutado manualmente en SQL Editor y verificado).
-- Acceso resultante:
--   clientes, pedidos, viajes, clientes_mayoristas -> solo choferes y administradores
--   borrar clientes y mayoristas                    -> solo administradores
--   usuarios: cada quien lee su perfil; choferes/admin leen la lista; solo admin crea o modifica
--   (nadie puede cambiarse su propio rol)

-- ===== clientes =====
drop policy if exists "Permitir insertar clientes" on public.clientes;
drop policy if exists "Permitir consultar clientes" on public.clientes;
drop policy if exists "Permitir actualizar clientes" on public.clientes;
drop policy if exists "Permitir eliminar clientes" on public.clientes;
-- se conserva "choferes_crean_clientes_ruta" (insert para chofer/admin)

drop policy if exists "clientes_select_personal" on public.clientes;
create policy "clientes_select_personal" on public.clientes
    for select to authenticated using (public.es_chofer_o_admin());

drop policy if exists "clientes_update_personal" on public.clientes;
create policy "clientes_update_personal" on public.clientes
    for update to authenticated using (public.es_chofer_o_admin()) with check (public.es_chofer_o_admin());

drop policy if exists "clientes_delete_admin" on public.clientes;
create policy "clientes_delete_admin" on public.clientes
    for delete to authenticated using (public.es_administrador());

-- ===== clientes_mayoristas =====
drop policy if exists "ClientesMayoristas_Select" on public.clientes_mayoristas;
drop policy if exists "ClientesMayoristas_Insert" on public.clientes_mayoristas;
drop policy if exists "ClientesMayoristas_Update" on public.clientes_mayoristas;
drop policy if exists "ClientesMayoristas_Delete" on public.clientes_mayoristas;

create policy "ClientesMayoristas_Select" on public.clientes_mayoristas
    for select to authenticated using (public.es_chofer_o_admin());
create policy "ClientesMayoristas_Insert" on public.clientes_mayoristas
    for insert to authenticated with check (public.es_chofer_o_admin());
create policy "ClientesMayoristas_Update" on public.clientes_mayoristas
    for update to authenticated using (public.es_chofer_o_admin()) with check (public.es_chofer_o_admin());
create policy "ClientesMayoristas_Delete" on public.clientes_mayoristas
    for delete to authenticated using (public.es_administrador());

-- ===== pedidos =====
drop policy if exists "Permitir insertar pedidos" on public.pedidos;
drop policy if exists "Permitir consultar pedidos" on public.pedidos;
drop policy if exists "Permitir actualizar pedidos" on public.pedidos;

drop policy if exists "pedidos_select_personal" on public.pedidos;
create policy "pedidos_select_personal" on public.pedidos
    for select to authenticated using (public.es_chofer_o_admin());
drop policy if exists "pedidos_insert_personal" on public.pedidos;
create policy "pedidos_insert_personal" on public.pedidos
    for insert to authenticated with check (public.es_chofer_o_admin());
drop policy if exists "pedidos_update_personal" on public.pedidos;
create policy "pedidos_update_personal" on public.pedidos
    for update to authenticated using (public.es_chofer_o_admin()) with check (public.es_chofer_o_admin());

-- ===== viajes =====
drop policy if exists "INSERT" on public.viajes;
drop policy if exists "SELECT" on public.viajes;
drop policy if exists "UPDATE" on public.viajes;

drop policy if exists "viajes_select_personal" on public.viajes;
create policy "viajes_select_personal" on public.viajes
    for select to authenticated using (public.es_chofer_o_admin());
drop policy if exists "viajes_insert_personal" on public.viajes;
create policy "viajes_insert_personal" on public.viajes
    for insert to authenticated with check (public.es_chofer_o_admin());
drop policy if exists "viajes_update_personal" on public.viajes;
create policy "viajes_update_personal" on public.viajes
    for update to authenticated using (public.es_chofer_o_admin()) with check (public.es_chofer_o_admin());

-- ===== usuarios =====
drop policy if exists "INSERT" on public.usuarios;
drop policy if exists "SELECT" on public.usuarios;
drop policy if exists "UPDATE" on public.usuarios;

drop policy if exists "usuarios_select" on public.usuarios;
create policy "usuarios_select" on public.usuarios
    for select to authenticated using (id = auth.uid() or public.es_chofer_o_admin());
drop policy if exists "usuarios_insert_admin" on public.usuarios;
create policy "usuarios_insert_admin" on public.usuarios
    for insert to authenticated with check (public.es_administrador());
drop policy if exists "usuarios_update_admin" on public.usuarios;
create policy "usuarios_update_admin" on public.usuarios
    for update to authenticated using (public.es_administrador()) with check (public.es_administrador());
drop policy if exists "usuarios_delete_admin" on public.usuarios;
create policy "usuarios_delete_admin" on public.usuarios
    for delete to authenticated using (public.es_administrador());
