# Mis finanzas: plan de cambios

Este documento es la guía de trabajo para Claude Code. Implementa los cambios **por fases, una fase por sesión**, en el orden indicado. Al terminar cada fase, marca sus casillas aquí mismo y sube todo a `main`.

---

## 1. Contexto del proyecto

- **Qué es:** app web personal de finanzas (PWA) que el dueño usa sobre todo desde su **iPhone**, instalada en la pantalla de inicio desde Safari (modo standalone). También se usa ocasionalmente en computadora.
- **Hosting:** GitHub Pages, repositorio `irseve/mis-finanzas`, rama `main`, raíz `/`. URL: `https://irseve.github.io/mis-finanzas/`.
- **Archivos actuales:**
  - `index.html`: toda la app (HTML, CSS y JS en un solo archivo, sin build).
  - `config.js`: `SUPABASE_URL` y `SUPABASE_KEY` (llave publishable, pública por diseño).
  - `manifest.json`, `apple-touch-icon.png`, `icon-192.png`, `icon-512.png`.
  - `schema.sql`: esquema inicial ya aplicado en Supabase.
- **Backend:** Supabase (Postgres + Auth + Realtime). Librería `@supabase/supabase-js@2.117.3` cargada por CDN (jsDelivr, build UMD).
- **Tablas actuales** (todas con RLS `user_id = auth.uid()`): `settings`, `categories`, `fixed_expenses`, `transactions`.
- **Auth:** correo + contraseña. El registro público está **desactivado**; el usuario actual se creó desde el panel de Supabase.
- **Idioma y región:** interfaz en español de México, moneda **MXN** (`Intl.NumberFormat("es-MX")`), zona horaria `America/Mexico_City`.
- **Ya implementado:** gastos e ingresos con fecha, categorías editables (nombre, color, presupuesto), gastos fijos con "marcar pagado", resumen mensual, gráficas por semana y de 6 meses, exportar CSV, tema claro/oscuro según el sistema, sincronización en tiempo real, barra inferior más alta con iconos de línea (punto 19).

## 2. Reglas de trabajo

1. **Sube los cambios directo a `main`** al terminar cada fase, con un mensaje de commit claro en español.
2. **Nunca pierdas ni alteres datos existentes.** Todo cambio de base de datos va en una migración nueva en `migrations/NNN_descripcion.sql`, idempotente (`if not exists`, etc.). Si tienes acceso a Supabase por MCP, aplícala; si no, al final indícale al usuario exactamente qué archivo correr en el SQL Editor **antes** de abrir la app.
3. **Seguridad:**
   - Toda tabla nueva lleva RLS activado y políticas por usuario.
   - La `service_role key` y cualquier secreto **jamás** van en el frontend ni en el repositorio. Solo como secretos de Edge Functions.
   - Los tokens personales (Siri, Gmail) se guardan hasheados.
4. **Móvil primero:** todo debe verse y usarse bien en iPhone en modo standalone (safe areas, zonas de toque de al menos 44 px, teclado numérico para montos).
5. **Incrementa la versión** de la app en cada cambio (ver punto 20): `APP_VERSION` y `APP_DATE` en `index.html`, `version.json` y el `?v=` de `config.js` para que el iPhone detecte la actualización.
6. Puedes dividir `index.html` en varios archivos (`app.js`, `styles.css`, módulos) si ayuda al mantenimiento, siempre sin paso de build y con versiones fijadas en los scripts de CDN.
7. Al terminar cada fase, explícale al usuario **en lenguaje sencillo** qué cambió, cómo probarlo en su iPhone y si debe hacer algún paso manual.

## 3. Decisiones pendientes

Antes de implementar lo que dependa de estas decisiones, **pregúntale al usuario**. Mientras tanto, usa el valor por defecto indicado.

| Tema | Pregunta | Valor por defecto |
|---|---|---|
| Recurrentes (punto 6) | Si el usuario cambia el monto de un recurrente al confirmarlo, ¿el próximo mes se sugiere el último monto pagado o el original? | El último monto pagado, siempre editable. |
| Gmail (punto 10) | ¿De qué banco llegan los correos de retiro/cargo? Se necesita un correo de ejemplo (con datos tapados). | No implementar el parser hasta tener el ejemplo. |
| Ingresos (punto 4) | ¿Se quiere un acceso más visible para registrar ingresos? | Botón rápido "Ingreso" en el formulario o junto al botón +. |
| Rediseño (punto 16) | Paleta e icono finales. | Presentar opciones y esperar elección. |

---

## 4. Fases

### Fase 0 · Actualizaciones de la app (punto 20) · PRIORIDAD MÁXIMA
Problema: la app instalada en la pantalla de inicio del iPhone conserva la versión vieja en caché (GitHub Pages usa `max-age=600` y iOS cachea aún más).

- [x] Constante de versión visible (por ejemplo `APP_VERSION = "1.4.0"` y fecha) y un `version.json` en la raíz con la misma versión.
- [x] Al abrir la app y en cada `visibilitychange` → visible: `fetch("version.json?t=" + Date.now(), { cache: "no-store" })`. Si la versión es distinta, mostrar un aviso "Hay una nueva versión · Actualizar".
- [x] En **Ajustes → Opciones avanzadas**: mostrar la versión instalada y un botón **"Buscar actualizaciones"** que fuerce la descarga sin caché y recargue la app (por ejemplo `location.replace("./?v=" + Date.now())`). Si no hay cambios, mostrar "Ya tienes la versión más reciente".
- [x] Los recursos propios (`config.js`, CSS y JS separados) se cargan con un parámetro de versión (`?v=APP_VERSION`).
- [ ] Si se agrega un service worker (necesario en la Fase 4), su estrategia debe ser *network-first* para HTML y `version.json`, y debe activarse de inmediato (`skipWaiting` + `clients.claim`). *(Aún no hay service worker; se aplica en la Fase 4.)*

**Criterio de aceptación:** después de reinstalar la app una última vez, un cambio subido a `main` aparece en el iPhone con el aviso o con el botón, sin volver a reinstalar.

### Fase 1 · Modelo de datos ampliado (puntos 8, 9 y la base de los puntos 1–3, 6, 13 y 18)

**Métodos de pago (punto 8)**
- [ ] Tabla `payment_methods` (`id`, `user_id`, `name`, `kind` en `credito | debito | transferencia | spay | efectivo | otro`, `color`, `active`).
- [ ] Métodos por defecto: Efectivo, Transferencia, SPAY. El usuario agrega sus tarjetas con nombre propio (por ejemplo "BBVA Crédito").
- [ ] Columna `payment_method_id` en `transactions`. Selector en el formulario (recordar el último usado). Filtro por método en Movimientos y desglose por método en Resumen.
- [ ] Sección de métodos de pago en Ajustes (crear, editar, desactivar), igual que las categorías.

**Retiros de efectivo (punto 9)**
- [ ] Nuevo `type` en `transactions`: `retiro` (además de `gasto`, `ingreso` y `ahorro`, este último usado en la Fase 7).
- [ ] Un retiro **no cuenta como gasto**: es un movimiento de una cuenta/método a "Efectivo". Los gastos pagados en efectivo se registran con el método Efectivo.
- [ ] Mostrar el saldo estimado de efectivo: retiros − gastos en efectivo del periodo.

**Recurrentes y recordatorios (base de los puntos 1–3, 6 y 13)**
- [ ] Generalizar `fixed_expenses` en una tabla `recurrences` (migrar los datos existentes sin perder nada) con:
  - `name`, `amount` (último monto), `original_amount`, `category_id`, `payment_method_id`.
  - `type` (`gasto | ingreso`).
  - Frecuencia: `every` (número) + `unit` (`day | week | month`); para mensual, el día del mes.
  - `mode`: `confirmar` (genera un pendiente por confirmar) o `recordatorio` (pago manual, solo avisa).
  - `next_date`, `active`.
- [ ] Cada transacción generada por un recurrente guarda `recurrence_id`. **Editar el monto de un mes no modifica meses pasados** (punto 6): cada mes es un registro independiente.
- [ ] Renombrar la pestaña "Fijos" a **"Recurrentes"**.

### Fase 2 · Recurrentes desde el formulario y bandeja de pendientes (puntos 1, 2, 3, 6 y 11)
- [ ] En el formulario de gasto/ingreso, un interruptor **"Repetir cada mes"** (con opción de otra frecuencia) que crea el recurrente con la fecha del registro como base (punto 1).
- [ ] Tabla `pending_entries` (`id`, `user_id`, `source` en `recurrente | siri | gmail`, `type`, `amount`, `category_id`, `payment_method_id`, `date`, `note`, `raw` jsonb, `recurrence_id`, `external_id` único para no duplicar, `status` en `pendiente | aceptado | descartado`, `created_at`).
- [ ] Generación de pendientes de recurrentes con `mode = confirmar` cuando llega su fecha (punto 2). Hacerlo del lado del servidor con `pg_cron`, para que exista aunque la app no se abra.
- [ ] **Bandeja "Pendientes por confirmar"** (punto 11): contador visible (badge) en la barra inferior o en el encabezado. Cada pendiente se puede editar (monto, categoría, método, fecha y nota) y luego **Aceptar** (se crea la transacción) o **Descartar** (puntos 3 y 11).
- [ ] Al aceptar un recurrente con monto distinto, actualizar `recurrences.amount` al nuevo monto, solo para sugerencias futuras (ver decisiones pendientes).

### Fase 3 · Gastado vs. esperado del mes (puntos 17 y 4)
- [ ] En Resumen: barra con dos segmentos, **gastado** (sólido) y **por pagar** (claro o rayado). El total es lo **esperado del mes**.
- [ ] Números: "Gastado $X · Por pagar $Y · Esperado $Z".
- [ ] "Por pagar" = recurrentes y recordatorios con fecha en lo que resta del mes que aún no tienen transacción, más los pendientes no aceptados.
- [ ] Lista de **próximos pagos** del mes con fecha, nombre y monto, cada uno con acción "Marcar pagado".
- [ ] Comparación con el ingreso del mes: "Después de los pagos pendientes te quedarán $W".
- [ ] Punto 4: acceso rápido para registrar ingresos (según la decisión pendiente).

### Fase 4 · Notificaciones push (base de los puntos 2, 11, 13 y 15)
- [ ] Service worker (`sw.js`) con manejo de `push` y `notificationclick` (abrir la app en la sección correspondiente: pendientes, recurrentes, etc.).
- [ ] Botón "Activar notificaciones" en Ajustes. En iOS la solicitud de permiso **debe** hacerse desde un toque del usuario y solo funciona con la app instalada en la pantalla de inicio. Si se abre en el navegador, explicar esto.
- [ ] Llaves VAPID: la pública en el frontend; la privada como secreto de Supabase.
- [ ] Tabla `push_subscriptions` (por usuario y dispositivo; varios dispositivos por usuario).
- [ ] Tabla `scheduled_notifications` (`user_id`, `kind`, `title`, `body`, `url`, `send_at`, `sent_at`).
- [ ] Edge Function `send-push` + `pg_cron` cada minuto que envía las notificaciones vencidas y elimina las suscripciones inválidas (410/404).
- [ ] Notificaciones reales:
  - Pendientes acumulados: "Tienes N gastos pendientes por confirmar", indicando el origen (Siri, correo o recurrente).
  - Recordatorio de pago manual (punto 13): "Recuerda pagar: Predial · $X".
  - Recurrente por confirmar llegado su día.
- [ ] Preferencias en Ajustes para activar o desactivar cada tipo.

### Fase 5 · Usuarios y administradores (puntos 14 y 15)
- [ ] Tabla `profiles` (`user_id`, `display_name`, `role` en `admin | user`). El usuario actual (dueño) es `admin`.
- [ ] Un admin puede ver la lista de usuarios, **invitar o crear usuarios** (Edge Function con la service role, nunca desde el frontend) y **asignar o quitar el rol admin**. No permitir quitar el último admin.
- [ ] **Privacidad:** el rol admin **no** da acceso a las finanzas de otros usuarios. Las políticas RLS de datos financieros siguen siendo `user_id = auth.uid()` sin excepción.
- [ ] Sección **Administración** visible solo para admins (verificado también del lado del servidor).
- [ ] **Probar notificación** (punto 15), solo para admins:
  - Al tocarlo, pide **en cuánto tiempo**: número + unidad (segundos, minutos, horas o días).
  - Pide el **tipo**: registro automático por correo (Gmail), registro de Siri, pago recurrente por confirmar o recordatorio de pago manual.
  - Programa una fila en `scheduled_notifications` para el usuario actual, con el texto real de ese tipo marcado como prueba.
  - Nota para el usuario: con `pg_cron` las pruebas en segundos pueden tardar hasta ~1 minuto. Si `pg_cron` admite intervalos en segundos, úsalos.

### Fase 6 · Registro con Siri automático (punto 7)
- [ ] Tabla `api_tokens` (`user_id`, `name`, `token_hash`, `last_used_at`, `revoked`). En Ajustes, el usuario genera un **token personal** (se muestra una sola vez) y puede revocarlo.
- [ ] Edge Function `siri-add` (POST con `Authorization: Bearer <token>`): recibe `monto`, `concepto` y, opcionalmente, `metodo` y `categoria`. Crea un **pendiente** (`source = siri`), intenta adivinar la categoría por el concepto y el historial, y responde un texto corto para que Siri lo diga ("Listo, guardé $250 de gasolina para confirmar").
- [ ] Si el pendiente no se confirma en unas horas, programar la notificación "Tienes gastos de Siri pendientes por confirmar".
- [ ] **Guía paso a paso en español** para crear el Atajo en la app Atajos del iPhone, con el menor número de pasos:
  - Frase: "Agrega un gasto".
  - Preguntas: monto (teclado numérico) y concepto (dictado); método de pago opcional.
  - Acción "Obtener contenido de URL" (POST JSON) y "Decir" con la respuesta.

  Escríbela en `docs/siri.md` y muéstrala también dentro de la app, en Ajustes.

### Fase 7 · Metas de ahorro e inversión (punto 18)
- [ ] Tabla `goals` (`name`, `target_amount`, `target_date` opcional, `color`). Las aportaciones son transacciones con `type = ahorro` y `goal_id`; no cuentan como gasto, pero sí se descuentan del disponible.
- [ ] Barra de progreso por meta.
- [ ] **Sugerencia inteligente del mes:** ingreso del mes − gastos esperados (Fase 3) − promedio del gasto variable de los últimos 3 meses − un margen de seguridad (por ejemplo 10% del ingreso). Nunca negativa; redondear a múltiplos de $50 o $100. Mostrar en qué se basa el cálculo.
- [ ] En Resumen: renglón "Sugerencia de inversión del mes: $X · Pendiente / Apartado".
- [ ] Notificación mensual, por ejemplo al registrar el salario: "Ya llegó tu ingreso. Te sugiero apartar $X para tu meta".
- [ ] La app sugiere **cuánto** apartar, no **dónde** invertir.

### Fase 8 · Registro automático desde Gmail (punto 10) · REQUIERE DECISIÓN
- [ ] Antes de empezar, pedir al usuario el banco y un correo de ejemplo (con datos tapados).
- [ ] Google Apps Script en la **cuenta personal de Google** del usuario: revisa cada 5–10 minutos los correos del banco (filtro y etiqueta de Gmail), extrae monto, fecha y tipo (retiro o cargo) y hace POST a la Edge Function `ingest-email` con token personal.
- [ ] `ingest-email` crea un pendiente (`source = gmail`) usando el ID del mensaje como `external_id` para no duplicar. Los retiros de cajero llegan como `type = retiro`.
- [ ] Guía paso a paso en `docs/gmail.md` para instalar el script.

### Fase 9 · Rediseño visual (puntos 16 y 12)
- [ ] **Antes de aplicar nada**, presentar 3–4 propuestas, cada una con icono, paleta en modo claro y paleta en modo oscuro, colores más llamativos que los actuales, vistas lado a lado como se verían en un iPhone. Esperar la elección del usuario.
- [ ] Aplicar la paleta elegida con variables CSS en `:root` y `@media (prefers-color-scheme: dark)`.
- [ ] Punto 12: que la barra de estado del iPhone combine con el tema (`theme-color` con `media` para claro y oscuro; revisar `apple-mobile-web-app-status-bar-style`).
- [ ] Regenerar `apple-touch-icon.png`, `icon-192.png` e `icon-512.png` con el icono elegido y actualizar `manifest.json`.
- [ ] Ajustar los iconos de la barra inferior a la nueva paleta.

---

## 5. Registro de puntos (referencia)

| # | Cambio | Fase | Estado |
|---|---|---|---|
| 1 | Marcar gasto como recurrente al registrarlo | 2 | Pendiente |
| 2 | Aviso para confirmar el recurrente al llegar su fecha | 2 / 4 | Pendiente |
| 3 | Editar el monto al confirmar | 2 | Pendiente |
| 4 | Registrar ingresos (ya existe; acceso más visible) | 3 | Parcial |
| 5 | Editar categorías | — | Hecho |
| 6 | Editar un mes no modifica los meses pasados | 1 / 2 | Pendiente |
| 7 | Siri automático, con confirmación en la app | 6 | Pendiente |
| 8 | Métodos de pago | 1 | Pendiente |
| 9 | Retiros de efectivo | 1 | Pendiente |
| 10 | Registro automático desde Gmail | 8 | Requiere decisión |
| 11 | Bandeja de pendientes + notificación | 2 / 4 | Pendiente |
| 12 | Tema claro/oscuro automático (barra de estado) | 9 | Parcial |
| 13 | Recordatorios de pagos manuales | 1 / 4 | Pendiente |
| 14 | Usuarios y administradores | 5 | Pendiente |
| 15 | Botón "Probar notificación" (solo admins) | 5 | Pendiente |
| 16 | Rediseño de icono y colores | 9 | Pendiente |
| 17 | Gastado vs. esperado del mes | 3 | Pendiente |
| 18 | Metas de ahorro e inversión con sugerencia | 7 | Pendiente |
| 19 | Barra inferior más alta con iconos | — | Hecho |
| 20 | Actualizaciones de la app (botón y aviso) | 0 | Hecho (v1.4.0) |

---

## 6. Nuevos cambios anotados (sin implementar todavía)

Dictados por el usuario el 2026-10-30. Solo anotados; **no ejecutar** hasta que el usuario lo indique.

### A. Pestaña "Fijos" (se conserva el nombre)
- [ ] Mantener la pestaña **Fijos** (sustituye el cambio de nombre a "Recurrentes" de la Fase 1).
- [ ] Mostrar un **resumen de gastos fijos**: "Estos son tus gastos fijos" y el **total al mes**.
- [ ] Agrupar por frecuencia: diario, semanal, quincenal, mensual. **Solo mostrar los grupos que tengan gastos** (si no hay semanales, no aparece el grupo semanal).
- [ ] Se puede seguir agregando gastos fijos desde esta pestaña.

### B. Gastos fijos desde "Agregar movimiento"
- [ ] Al agregar un movimiento de tipo **gasto**, opción **"Es fijo"**.
- [ ] Si es fijo, elegir la frecuencia: **diario, semanal, quincenal o mensual**.
- [ ] Ese gasto aparece en la pestaña Fijos. Es decir, los gastos fijos se configuran tanto desde Fijos como desde Movimientos.

### C. Agregar categoría desde el formulario
- [ ] En la lista de categorías del formulario de movimiento, agregar al final una opción **"+ Agregar categoría nueva"** que permita crearla ahí mismo y quede seleccionada.

### D. Eliminar categorías en Ajustes, con reasignación
- [ ] En Ajustes se listan todas las categorías guardadas y se puede **eliminar** cualquiera.
- [ ] Si la categoría tiene movimientos o gastos fijos registrados, mostrar una advertencia: "Hay movimientos registrados en esta categoría", con la **lista de esos movimientos** (por ejemplo: "Tienes un gasto fijo de Colegiatura de $2,000").
- [ ] Preguntar **a qué categoría moverlos**: elegir una existente (por ejemplo "Otros") o **crear una categoría nueva** en ese momento.
- [ ] Solo después de reasignar se elimina la categoría. Nunca se borran movimientos.

### E. Ingresos fijos (por ejemplo, el salario)
- [ ] Los **ingresos también pueden ser fijos**, con las mismas frecuencias que los gastos.
- [ ] El monto puede cambiar en cada pago (por ejemplo, por horas extra). Por eso, **cada vez que toca un ingreso fijo llega una notificación** para que el usuario indique la cantidad real recibida.
- [ ] Al registrarlo se puede escribir el monto del momento. Sugerir el último monto, siempre editable.

### Decisiones confirmadas por el usuario
- **Frecuencias, contadas desde la fecha del registro:**
  - Quincenal: cada 15 días desde la fecha del registro, **excepto el salario** (ver abajo).
  - **Quincena de salario (estilo México):** los pagos de salario son **el día 15 y el último día de cada mes** (28, 29, 30 o 31, según el mes). **No** sumar 15 días, para que no se desfase en meses de 31 días ni en febrero. Usar esta regla de forma predeterminada en la categoría Salario.
  - Mensual: el mismo día de cada mes. Por ejemplo, un cobro registrado el día 13 se repite el 13 de cada mes.
  - Semanal y diario: igual, a partir de la fecha del registro.
- **Total del mes en Fijos:** solo **suma lo ya registrado** en el mes, sin promedios ni equivalentes. Lo **proyectado** según los fijos configurados se muestra aparte (Fase 3, "esperado del mes").
- **Ingresos fijos:** sí existen (ver punto E).
