# Dejar todo listo (versión 1.9.0)

Sigue los pasos en orden. Los pasos 1 a 4 se hacen una sola vez, desde una computadora, en <https://supabase.com/dashboard> → tu proyecto.

## 1. Actualizar la base de datos

1. **Database → Extensions**: busca y activa **pg_cron** y **pg_net** (si ya están activas, sigue).
2. **SQL Editor → New query**: pega todo [`migrations/001_metodos_fijos_pendientes_metas.sql`](../migrations/001_metodos_fijos_pendientes_metas.sql) → **Run**. Si ya la corriste antes, no pasa nada por correrla otra vez.
3. **New query** otra vez: pega todo [`migrations/002_notificaciones_usuarios_siri_gmail.sql`](../migrations/002_notificaciones_usuarios_siri_gmail.sql) → **Run**.
4. Y lo mismo con [`migrations/003_apartados_inversiones.sql`](../migrations/003_apartados_inversiones.sql) (Apartados e inversiones).

Atajo: [`migrations/instalar_todo.sql`](../migrations/instalar_todo.sql) trae los tres juntos; pégalo una sola vez.

Debe decir *Success*. Si aparece un aviso de que pg_cron o pg_net no están disponibles, actívalos (paso 1) y vuelve a correr la 002. Ninguna de las dos borra tus datos.

## 2. Instalar las 4 funciones del servidor

Repite esto para cada función de la tabla:

1. **Edge Functions → Deploy a new function → Via Editor**.
2. Nombre: exactamente el de la tabla.
3. Borra el código de ejemplo y pega el archivo completo → **Deploy function**.
4. Ya creada, entra a la función → **Details** (o **Settings**) → apaga **Verify JWT** (puede decir *Enforce JWT verification* o *Verify JWT with legacy secret*) → **Save**. Cada función revisa por su cuenta quién la llama.

| Nombre | Archivo a pegar | Para qué |
|---|---|---|
| `notificaciones` | [`supabase/functions/notificaciones/index.ts`](../supabase/functions/notificaciones/index.ts) | Enviar avisos al iPhone |
| `admin-usuarios` | [`supabase/functions/admin-usuarios/index.ts`](../supabase/functions/admin-usuarios/index.ts) | Agregar usuarios y administradores |
| `registrar` | [`supabase/functions/registrar/index.ts`](../supabase/functions/registrar/index.ts) | Recibir gastos de Siri y de Gmail |
| `precios` | [`supabase/functions/precios/index.ts`](../supabase/functions/precios/index.ts) | Buscar instrumentos (VOO, NAFTRAC…) y actualizar sus precios |

No hace falta configurar ningún secreto: las funciones usan las llaves que Supabase ya les da, y las llaves de notificaciones se crean solas la primera vez.

## 3. Permitir el enlace de recuperación de contraseña e invitaciones

**Authentication → URL Configuration**:
- **Site URL**: `https://irseve.github.io/mis-finanzas/`
- **Redirect URLs** → **Add URL**: `https://irseve.github.io/mis-finanzas/`

## 4. Instalar la app de nuevo en el iPhone (icono nuevo)

1. Borra el icono actual de "Finanzas" (tus datos están en Supabase, no se pierden).
2. Abre `https://irseve.github.io/mis-finanzas/` en **Safari**. Si no ves el icono verde con $, espera 10 minutos y recarga.
3. Inicia sesión y revisa en **Ajustes → Opciones avanzadas** que diga **1.8.0**.
4. **Compartir → Agregar a inicio**.

De aquí en adelante, ábrela siempre desde el icono.

## 5. Activar notificaciones (en el iPhone, desde el icono)

1. **Ajustes → Notificaciones → Activar notificaciones** → **Permitir**.
2. Elige qué avisos quieres recibir con las casillas.
3. Prueba: **Ajustes → Administración → Probar notificación** → `30 segundos`, tipo *Registro de Siri* → **Programar prueba**. Cierra la app; en 30 a 90 segundos debe llegarte el aviso. Al tocarlo se abre la app en Pendientes.

## 6. Siri (opcional)

Sigue [`docs/siri.md`](siri.md): generas un token en **Ajustes → Siri y correo** y creas el atajo "Agrega un gasto" en la app Atajos.

## 7. Gmail con BBVA (opcional, desde una computadora)

Sigue [`docs/gmail.md`](gmail.md): generas otro token y pegas el programa [`scripts/gmail-bbva.gs`](../scripts/gmail-bbva.gs) en script.google.com.

## 8. Elegir tu tema

**Ajustes → Tema** y **Apariencia**.

---

### Si algo no funciona

- **Aviso amarillo "Falta actualizar la base de datos"**: corre el archivo que indica (paso 1).
- **"Falta instalar la función notificaciones"** al activar avisos: revisa el paso 2 y que el nombre sea exactamente `notificaciones`.
- **No llega la notificación de prueba**:
  - Revisa que la app esté instalada desde Safari y abierta desde el icono.
  - Revisa en el iPhone **Configuración → Notificaciones → Finanzas**.
  - En Supabase, **Edge Functions → notificaciones → Logs** muestra los errores.
- **Siri dice "token no válido"**: revisa que el encabezado sea `Bearer mf_…`, con un espacio.
