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

0. **No cambiar la app sin permiso explícito (regla del usuario, 2026-10-31):** cuando el usuario pida algo, **solo anotarlo** en este archivo y **preguntar**. No modificar la app ni subir cambios a `main` hasta que el usuario diga explícitamente que se apliquen (por ejemplo "actualiza los cambios"), porque quiere juntar varios cambios y aplicarlos al mismo tiempo. Excepción: anotar en este archivo.
0b. **Avisar cada cambio (regla del usuario, 2026-11-03):** cada vez que se suba un cambio o actualización, mandar una notificación al iPhone del usuario con lo que cambió.
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
| Recurrentes (punto 6) | **Resuelto:** el último monto, siempre editable (ver sección 6). | — |
| Gmail (punto 10) | **Resuelto:** BBVA (correo de ejemplo: retiro de efectivo). | — |
| Ingresos (punto 4) | **Resuelto:** botones "+ Gasto" (rojo) y "+ Ingreso" (verde) en Resumen. | — |
| Rediseño (punto 16) | **Resuelto:** 5 temas a elegir; icono opción A. | — |

---

**Para dejar todo funcionando: [`docs/INSTALACION.md`](docs/INSTALACION.md).**

## 4. Fases

### Fase 0 · Actualizaciones de la app (punto 20) · PRIORIDAD MÁXIMA
Problema: la app instalada en la pantalla de inicio del iPhone conserva la versión vieja en caché (GitHub Pages usa `max-age=600` y iOS cachea aún más).

- [x] Constante de versión visible (por ejemplo `APP_VERSION = "1.4.0"` y fecha) y un `version.json` en la raíz con la misma versión.
- [x] Al abrir la app y en cada `visibilitychange` → visible: `fetch("version.json?t=" + Date.now(), { cache: "no-store" })`. Si la versión es distinta, mostrar un aviso "Hay una nueva versión · Actualizar".
- [x] En **Ajustes → Opciones avanzadas**: mostrar la versión instalada y un botón **"Buscar actualizaciones"** que fuerce la descarga sin caché y recargue la app (por ejemplo `location.replace("./?v=" + Date.now())`). Si no hay cambios, mostrar "Ya tienes la versión más reciente".
- [x] Los recursos propios (`config.js`, CSS y JS separados) se cargan con un parámetro de versión (`?v=APP_VERSION`).
- [x] Si se agrega un service worker (necesario en la Fase 4), su estrategia debe ser *network-first* para HTML y `version.json`, y debe activarse de inmediato (`skipWaiting` + `clients.claim`). *(v1.8.0: `sw.js` sin caché, solo notificaciones.)*

**Criterio de aceptación:** después de reinstalar la app una última vez, un cambio subido a `main` aparece en el iPhone con el aviso o con el botón, sin volver a reinstalar.

### Fase 1 · Modelo de datos ampliado (puntos 8, 9 y la base de los puntos 1–3, 6, 13 y 18)

**Métodos de pago (punto 8)**
- [x] Tabla `payment_methods` (`id`, `user_id`, `name`, `kind` en `credito | debito | transferencia | spay | efectivo | otro`, `color`, `active`).
- [x] Métodos por defecto: Efectivo, Transferencia, SPAY. El usuario agrega sus tarjetas con nombre propio (por ejemplo "BBVA Crédito").
- [x] Columna `payment_method_id` en `transactions`. Selector en el formulario (recordar el último usado). Filtro por método en Movimientos y desglose por método en Resumen.
- [x] Sección de métodos de pago en Ajustes (crear, editar, desactivar), igual que las categorías.

**Retiros de efectivo (punto 9)**
- [x] Nuevo `type` en `transactions`: `retiro` (además de `gasto`, `ingreso` y `ahorro`, este último usado en la Fase 7).
- [x] Un retiro **no cuenta como gasto**: es un movimiento de una cuenta/método a "Efectivo". Los gastos pagados en efectivo se registran con el método Efectivo.
- [x] Mostrar el saldo estimado de efectivo: retiros − gastos en efectivo del periodo.

**Recurrentes y recordatorios (base de los puntos 1–3, 6 y 13)**
- [x] Generalizar `fixed_expenses` en una tabla `recurrences` (migrar los datos existentes sin perder nada) con:
  - `name`, `amount` (último monto), `original_amount`, `category_id`, `payment_method_id`.
  - `type` (`gasto | ingreso`).
  - Frecuencia: columna `freq` (`diario | semanal | quincenal | mensual | salario`) + `start_date`; para mensual, `day` (día del mes). Ver sección 6.
  - `mode`: `confirmar` (genera un pendiente por confirmar) o `recordatorio` (pago manual, solo avisa).
  - `next_date`, `active`.
- [x] Cada transacción generada por un recurrente guarda `recurrence_id`. **Editar el monto de un mes no modifica meses pasados** (punto 6): cada mes es un registro independiente.
- [x] ~~Renombrar la pestaña "Fijos" a "Recurrentes"~~: por decisión del usuario se queda como **"Fijos"** (sección 6).

### Fase 2 · Recurrentes desde el formulario y bandeja de pendientes (puntos 1, 2, 3, 6 y 11)
- [x] En el formulario de gasto/ingreso, un interruptor **"Repetir cada mes"** (con opción de otra frecuencia) que crea el recurrente con la fecha del registro como base (punto 1).
- [x] Tabla `pending_entries` (`id`, `user_id`, `source` en `recurrente | siri | gmail`, `type`, `amount`, `category_id`, `payment_method_id`, `date`, `note`, `raw` jsonb, `recurrence_id`, `external_id` único para no duplicar, `status` en `pendiente | aceptado | descartado`, `created_at`).
- [x] Generación de pendientes de recurrentes con `mode = confirmar` cuando llega su fecha (punto 2). Hacerlo del lado del servidor con `pg_cron`, para que exista aunque la app no se abra.
- [x] **Bandeja "Pendientes por confirmar"** (punto 11): contador visible (badge) en la barra inferior o en el encabezado. Cada pendiente se puede editar (monto, categoría, método, fecha y nota) y luego **Aceptar** (se crea la transacción) o **Descartar** (puntos 3 y 11).
- [x] Al aceptar un recurrente con monto distinto, actualizar `recurrences.amount` al nuevo monto, solo para sugerencias futuras (ver decisiones pendientes).

### Fase 3 · Gastado vs. esperado del mes (puntos 17 y 4)
- [x] En Resumen: barra con dos segmentos, **gastado** (sólido) y **por pagar** (claro o rayado). El total es lo **esperado del mes**.
- [x] Números: "Gastado $X · Por pagar $Y · Esperado $Z".
- [x] "Por pagar" = recurrentes y recordatorios con fecha en lo que resta del mes que aún no tienen transacción, más los pendientes no aceptados.
- [x] Lista de **próximos pagos** del mes con fecha, nombre y monto, cada uno con acción "Marcar pagado".
- [x] Comparación con el ingreso del mes: "Después de los pagos pendientes te quedarán $W".
- [x] Punto 4: acceso rápido para registrar ingresos (según la decisión pendiente).

### Fase 4 · Notificaciones push (base de los puntos 2, 11, 13 y 15)
- [x] Service worker (`sw.js`) con manejo de `push` y `notificationclick` (abrir la app en la sección correspondiente: pendientes, recurrentes, etc.).
- [x] Botón "Activar notificaciones" en Ajustes. En iOS la solicitud de permiso **debe** hacerse desde un toque del usuario y solo funciona con la app instalada en la pantalla de inicio. Si se abre en el navegador, explicar esto.
- [x] Llaves VAPID: se generan solas en la función `notificaciones` y se guardan en `app_secrets` (tabla sin acceso para usuarios); la app pide la pública.
- [x] Tabla `push_subscriptions` (por usuario y dispositivo; varios dispositivos por usuario).
- [x] Tabla `scheduled_notifications` (`user_id`, `kind`, `title`, `body`, `url`, `send_at`, `sent_at`).
- [x] Edge Function `notificaciones` (acción send) + `pg_cron` cada minuto (solo la llama si hay avisos vencidos) que envía las notificaciones vencidas y elimina las suscripciones inválidas (410/404).
- [x] Notificaciones reales:
  - Pendientes acumulados: "Tienes N gastos pendientes por confirmar", indicando el origen (Siri, correo o recurrente).
  - Recordatorio de pago manual (punto 13): "Recuerda pagar: Predial · $X".
  - Recurrente por confirmar llegado su día.
- [x] Preferencias en Ajustes para activar o desactivar cada tipo.

### Fase 5 · Usuarios y administradores (puntos 14 y 15)
- [x] Tabla `profiles` (`user_id`, `display_name`, `role` en `admin | user`). El usuario actual (dueño) es `admin`.
- [x] Un admin puede ver la lista de usuarios, **invitar o crear usuarios** (Edge Function con la service role, nunca desde el frontend) y **asignar o quitar el rol admin**. No permitir quitar el último admin.
- [x] **Privacidad:** el rol admin **no** da acceso a las finanzas de otros usuarios. Las políticas RLS de datos financieros siguen siendo `user_id = auth.uid()` sin excepción.
- [x] Sección **Administración** visible solo para admins (verificado también del lado del servidor).
- [x] **Probar notificación** (punto 15), solo para admins:
  - Al tocarlo, pide **en cuánto tiempo**: número + unidad (segundos, minutos, horas o días).
  - Pide el **tipo**: registro automático por correo (Gmail), registro de Siri, pago recurrente por confirmar o recordatorio de pago manual.
  - Programa una fila en `scheduled_notifications` para el usuario actual, con el texto real de ese tipo marcado como prueba.
  - Nota para el usuario: con `pg_cron` las pruebas en segundos pueden tardar hasta ~1 minuto. Si `pg_cron` admite intervalos en segundos, úsalos.

### Fase 6 · Registro con Siri automático (punto 7)
- [x] Tabla `api_tokens` (`user_id`, `name`, `token_hash`, `last_used_at`, `revoked`). En Ajustes, el usuario genera un **token personal** (se muestra una sola vez) y puede revocarlo.
- [x] Edge Function `registrar?origen=siri` (POST con `Authorization: Bearer <token>`): recibe `monto`, `concepto` y, opcionalmente, `metodo` y `categoria`. Crea un **pendiente** (`source = siri`), intenta adivinar la categoría por el concepto y el historial, y responde un texto corto para que Siri lo diga ("Listo, guardé $250 de gasolina para confirmar").
- [x] Si el pendiente no se confirma en unas horas, programar la notificación "Tienes gastos de Siri pendientes por confirmar".
- [x] **Guía paso a paso en español** para crear el Atajo en la app Atajos del iPhone, con el menor número de pasos:
  - Frase: "Agrega un gasto".
  - Preguntas: monto (teclado numérico) y concepto (dictado); método de pago opcional.
  - Acción "Obtener contenido de URL" (POST JSON) y "Decir" con la respuesta.

  Escríbela en `docs/siri.md` y muéstrala también dentro de la app, en Ajustes.

### Fase 7 · Metas de ahorro e inversión (punto 18)
- [x] Tabla `goals` (`name`, `target_amount`, `target_date` opcional, `color`). Las aportaciones son transacciones con `type = ahorro` y `goal_id`; no cuentan como gasto, pero sí se descuentan del disponible.
- [x] Barra de progreso por meta.
- [x] **Sugerencia inteligente del mes:** ingreso del mes − gastos esperados (Fase 3) − promedio del gasto variable de los últimos 3 meses − un margen de seguridad (por ejemplo 10% del ingreso). Nunca negativa; redondear a múltiplos de $50 o $100. Mostrar en qué se basa el cálculo.
- [x] En Resumen: renglón "Sugerencia de inversión del mes: $X · Pendiente / Apartado".
- [x] Notificación, por ejemplo al registrar el salario: "Ya llegó tu ingreso. Te sugiero apartar $X para tu meta".
- [x] La app sugiere **cuánto** apartar, no **dónde** invertir.

### Fase 8 · Registro automático desde Gmail (punto 10) · BBVA
- [x] Antes de empezar, pedir al usuario el banco y un correo de ejemplo (con datos tapados).
- [x] Google Apps Script en la **cuenta personal de Google** del usuario: revisa cada 5–10 minutos los correos del banco (filtro y etiqueta de Gmail), extrae monto, fecha y tipo (retiro o cargo) y hace POST a la Edge Function `registrar?origen=gmail` con token personal (la lectura del correo se hace en el servidor). Archivo: `scripts/gmail-bbva.gs`.
- [x] `registrar?origen=gmail` crea un pendiente (`source = gmail`) usando el ID del mensaje como `external_id` para no duplicar. Los retiros de cajero llegan como `type = retiro`.
- [x] Guía paso a paso en `docs/gmail.md` para instalar el script.

### Fase 9 · Rediseño visual (puntos 16 y 12)
- [x] **Antes de aplicar nada**, presentar 3–4 propuestas, cada una con icono, paleta en modo claro y paleta en modo oscuro, colores más llamativos que los actuales, vistas lado a lado como se verían en un iPhone. Esperar la elección del usuario.
- [x] *(Decisión del usuario: incluir todas como temas a elegir en Ajustes → Tema: Bosque, Esmeralda, Océano, Mandarina y Ciruela, cada uno claro/oscuro, más Apariencia automática/clara/oscura. **Regla: en todos los temas el gasto es rojo y el ingreso verde.** Hecho en v1.6.0.)* Aplicar la paleta elegida con variables CSS en `:root` y `@media (prefers-color-scheme: dark)`.
- [x] Punto 12 (v1.6.0: `theme-color` sigue al tema y a la apariencia elegidos): que la barra de estado del iPhone combine con el tema (`theme-color` con `media` para claro y oscuro; revisar `apple-mobile-web-app-status-bar-style`).
- [x] *(Elegido: opción A, $ blanco sobre verde. Hecho en v1.7.0.)* Regenerar `apple-touch-icon.png`, `icon-192.png` e `icon-512.png` con el icono elegido y actualizar `manifest.json`.
- [x] Ajustar los iconos de la barra inferior a la nueva paleta (usan el color del tema).

---

## 5. Registro de puntos (referencia)

| # | Cambio | Fase | Estado |
|---|---|---|---|
| 1 | Marcar gasto como recurrente al registrarlo | 2 | Hecho (v1.5.0) |
| 2 | Aviso para confirmar el recurrente al llegar su fecha | 2 / 4 | Hecho (v1.8.0) |
| 3 | Editar el monto al confirmar | 2 | Hecho (v1.5.0) |
| 4 | Registrar ingresos (ya existe; acceso más visible) | 3 | Hecho (v1.5.0) |
| 5 | Editar categorías | — | Hecho |
| 6 | Editar un mes no modifica los meses pasados | 1 / 2 | Hecho (v1.5.0) |
| 7 | Siri automático, con confirmación en la app | 6 | Hecho (v1.8.0) |
| 8 | Métodos de pago | 1 | Hecho (v1.5.0) |
| 9 | Retiros de efectivo | 1 | Hecho (v1.5.0) |
| 10 | Registro automático desde Gmail | 8 | Hecho (v1.8.0, BBVA) |
| 11 | Bandeja de pendientes + notificación | 2 / 4 | Hecho (v1.8.0) |
| 12 | Tema claro/oscuro automático (barra de estado) | 9 | Hecho (v1.6.0) |
| 13 | Recordatorios de pagos manuales | 1 / 4 | Hecho (v1.8.0) |
| 14 | Usuarios y administradores | 5 | Hecho (v1.8.0) |
| 15 | Botón "Probar notificación" (solo admins) | 5 | Hecho (v1.8.0) |
| 16 | Rediseño de icono y colores | 9 | Hecho (temas v1.6.0, icono v1.7.0) |
| 17 | Gastado vs. esperado del mes | 3 | Hecho (v1.5.0) |
| 18 | Metas de ahorro e inversión con sugerencia | 7 | Hecho (v1.8.0) |
| 19 | Barra inferior más alta con iconos | — | Hecho |
| 20 | Actualizaciones de la app (botón y aviso) | 0 | Hecho (v1.4.0) |
| 21 | Recuperar contraseña por correo y cambiarla desde Ajustes | — | Hecho (v1.7.0). Requiere la URL de la app en Supabase → Authentication → URL Configuration |

---

## 6. Nuevos cambios anotados (sin implementar todavía)

Dictados por el usuario el 2026-10-30. Solo anotados; **no ejecutar** hasta que el usuario lo indique.

**Dónde encajan:** A, B y E se implementan con la Fase 1 (tabla de fijos/recurrentes con frecuencias diario, semanal, quincenal, mensual y salario 15/último día) y la Fase 2 (opción "Es fijo" en el formulario y aviso para capturar el monto). C y D se implementan junto con la Fase 1. Donde esta sección contradiga las fases anteriores, **manda esta sección** (por ejemplo, la pestaña se sigue llamando "Fijos").

### A. Pestaña "Fijos" (se conserva el nombre)
- [x] Mantener la pestaña **Fijos** (sustituye el cambio de nombre a "Recurrentes" de la Fase 1).
- [x] Mostrar un **resumen de gastos fijos**: "Estos son tus gastos fijos" y el **total al mes**.
- [x] Agrupar por frecuencia: diario, semanal, quincenal, mensual. **Solo mostrar los grupos que tengan gastos** (si no hay semanales, no aparece el grupo semanal).
- [x] Se puede seguir agregando gastos fijos desde esta pestaña.

### B. Gastos fijos desde "Agregar movimiento"
- [x] Al agregar un movimiento de tipo **gasto**, opción **"Es fijo"**.
- [x] Si es fijo, elegir la frecuencia: **diario, semanal, quincenal o mensual**.
- [x] Ese gasto aparece en la pestaña Fijos. Es decir, los gastos fijos se configuran tanto desde Fijos como desde Movimientos.

### C. Agregar categoría desde el formulario
- [x] En la lista de categorías del formulario de movimiento, agregar al final una opción **"+ Agregar categoría nueva"** que permita crearla ahí mismo y quede seleccionada.

### D. Eliminar categorías en Ajustes, con reasignación
- [x] En Ajustes se listan todas las categorías guardadas y se puede **eliminar** cualquiera.
- [x] Si la categoría tiene movimientos o gastos fijos registrados, mostrar una advertencia: "Hay movimientos registrados en esta categoría", con la **lista de esos movimientos** (por ejemplo: "Tienes un gasto fijo de Colegiatura de $2,000").
- [x] Preguntar **a qué categoría moverlos**: elegir una existente (por ejemplo "Otros") o **crear una categoría nueva** en ese momento.
- [x] Solo después de reasignar se elimina la categoría. Nunca se borran movimientos.

### E. Ingresos fijos (por ejemplo, el salario)
- [x] Los **ingresos también pueden ser fijos**, con las mismas frecuencias que los gastos.
- [x] El monto puede cambiar en cada pago (por ejemplo, por horas extra). Por eso, **cada vez que toca un ingreso fijo llega una notificación** para que el usuario indique la cantidad real recibida.
- [x] Al registrarlo se puede escribir el monto del momento. Sugerir el último monto, siempre editable.

### Decisiones confirmadas por el usuario
- **Frecuencias, contadas desde la fecha del registro:**
  - Quincenal: cada 15 días desde la fecha del registro, **excepto el salario** (ver abajo).
  - **Quincena de salario (estilo México):** los pagos de salario son **el día 15 y el último día de cada mes** (28, 29, 30 o 31, según el mes). **No** sumar 15 días, para que no se desfase en meses de 31 días ni en febrero. Esta regla aplica **solo al salario**; los demás fijos quincenales van cada 15 días desde la fecha del registro. Si el 15 o el último día cae en fin de semana o día festivo, el aviso llega **ese mismo día** (no se adelanta).
  - Mensual: el mismo día de cada mes. Por ejemplo, un cobro registrado el día 13 se repite el 13 de cada mes.
  - Semanal y diario: igual, a partir de la fecha del registro.
- **Total del mes en Fijos:** solo **suma lo ya registrado** en el mes, sin promedios ni equivalentes. Lo **proyectado** según los fijos configurados se muestra aparte (Fase 3, "esperado del mes").
- **Ingresos fijos:** sí existen (ver punto E).

---

## 7. Pendientes para después (al final, cuando todo lo demás esté pulido)

- [ ] **Asistente de voz dentro de la app.** Un botón de micrófono para dar órdenes habladas: "agrega un gasto de 250 de gasolina con BBVA", "borra el gasto de ayer del Oxxo", "cambia la colegiatura a 2,100". La voz se convierte en texto y una IA interpreta la orden en una Edge Function, con la llave guardada como secreto en Supabase. La app **siempre muestra lo que entendió y pide confirmar** antes de guardar, borrar o modificar. Costo aproximado: centavos por orden.

---

## 8. Cambios del 2026-10-30 — implementados en v1.9.0

Pendiente de esta lista: tasa de CETES automática con Banxico (requiere token; por ahora la tasa se escribe a mano) y decidir si descontar el ISR (por ahora se muestra rendimiento bruto).

### F. Selector de mes en cuadrícula
Hoy el encabezado muestra el mes actual ("Octubre de 2026") con flechas ‹ › a los lados para ir mes por mes.
- [x] Las flechas ‹ › se quedan como están.
- [x] Al **tocar el nombre del mes** (la parte de en medio) se despliega hacia abajo una ventana pequeña.
- [x] Arriba de esa ventana va el **año** (por defecto el año en curso, por ejemplo 2026) con flechas para ir al **año anterior y al siguiente**.
- [x] Debajo, los **12 meses en cuadrícula** (por ejemplo 3 columnas × 4 filas o 4 × 3), no en lista, para saltar fácil de un mes a otro (de octubre a enero, por ejemplo).
- [x] Al tocar un mes se cierra la ventana y la app muestra ese mes. Resaltar el mes seleccionado y marcar de forma distinta el mes actual.
- [x] Se cierra también al tocar fuera de la ventana. Zonas de toque de al menos 44 px; debe verse bien en los 5 temas, claro y oscuro.

### G. Una sola gráfica de gastos con periodo a elegir
Hoy hay dos gráficas en Resumen:
- **Gastos por semana:** solo gastos, semana por semana del mes que estás viendo.
- **Últimos 6 meses:** ingresos contra gastos, mes por mes.

El usuario propone unificarlas en una sola.
- [x] Una sola tarjeta de gráfica en Resumen, con un selector arriba: **Semana · Mes · Año**.
  - **Semana:** las semanas del mes seleccionado (como la gráfica actual).
  - **Mes:** los últimos 6 o 12 meses (por definir), uno por barra.
  - **Año:** un año por barra, con los años que tengan registros.
- [x] Recordar en el dispositivo el último periodo elegido.
- [x] Al quitar la gráfica de 6 meses, la de categorías y "Fijos vs. variables" se acomodan para no dejar huecos.
- [x] Segundo selector **Mostrar: Gastos · Ingresos · Ambos** (rojo para gastos, verde para ingresos), disponible en Semana, Mes y Año.
- [x] El usuario **elige el periodo de tiempo** que abarca la gráfica (desde – hasta). Sugerencia: atajos rápidos (este mes, últimos 3, 6 o 12 meses, este año, todo) y la opción de elegir fechas, usando el mismo selector de mes en cuadrícula del punto F. Con esto se resuelve cuántos meses mostrar.
- [x] Recordar en el dispositivo la última combinación elegida (agrupación, qué mostrar y periodo).
- Nota técnica: hoy la app carga 6 meses de movimientos; para periodos más largos hay que cargar el rango elegido o pedir totales agrupados al servidor.

### H. Un solo botón para agregar
Hoy hay muchos lugares para agregar: el botón flotante **+**, "+ Gasto" y "+ Ingreso" en Resumen, "Agregar el primero" o "Agregar movimiento" cuando no hay datos, "Nuevo fijo" en Fijos, "Aportar" en Metas, etc. El usuario quiere simplificar.
- [x] El **botón flotante +** es la única forma de agregar movimientos. Visible en todas las pestañas, en la misma posición.
- [x] Quitar "+ Gasto" y "+ Ingreso" del Resumen y los botones de agregar de los mensajes vacíos (dejar solo un texto como "Toca + para agregar tu primer movimiento").
- [x] El formulario del + ya permite elegir Gasto, Ingreso, Retiro o Ahorro y marcar "Es fijo", así que cubre todos los casos, incluidos los fijos.
- [x] Botones que **no** son para agregar movimientos se quedan: "Marcar pagado", "Confirmar", "Editar", y en Ajustes "Nueva categoría", "Nuevo método", etc.
- Por confirmar con el usuario:
  - ~~En Fijos, ¿quitar también "Nuevo fijo"?~~ **Resuelto:** sí. Todo se agrega con el +, que permite marcar "Es fijo" y elegir la categoría.
  - ~~En Metas, ¿quitar "Aportar"?~~ **Resuelto:** sí. Cada aportación se hace con **+ → Ahorro**; la sección de metas se queda para consultar.
  - ~~Color del +~~ **Resuelto:** el + usa el **color principal del tema** (ya no rojo). Dentro del formulario, Gasto sigue en rojo e Ingreso en verde.
- [x] **Pestaña Fijos solo informativa:** sin botón "Nuevo fijo" ni "Registrar los pendientes del mes". Muestra el resumen (pagado, proyectado, por frecuencia) y la lista de fijos. Se conserva tocar un fijo para **editarlo, pausarlo o eliminarlo**, porque es el único lugar donde se administran.
- Por confirmar: el usuario comentó que "en la pantalla principal también pone gastos" (frase incompleta). Posible duplicado entre Resumen (Próximos pagos, Gastos fijos, Fijos vs. variables) y la pestaña Fijos. Preguntar qué quiere quitar o juntar.

### I. Ajustes agrupados, sin mostrar todo de golpe
Hoy Ajustes muestra todas las secciones abiertas una tras otra (categorías, métodos, notificaciones, Siri, administración, tema, moneda, cuenta, versión) y se ve muy cargado.
- [x] Al entrar a Ajustes se ve solo una **lista corta de grupos**, estilo Ajustes del iPhone: icono, nombre, un resumen pequeño (por ejemplo "11 categorías", "Activadas", "Bosque · Automática") y una flecha ›.
- [x] Al tocar un grupo se abre su pantalla con el botón **‹ Ajustes** para regresar. Recomendado sobre un acordeón (que se despliega en la misma lista) porque es lo que el usuario ya conoce del iPhone y no alarga la página.
- [x] Grupos propuestos:
  1. **Categorías:** de gasto y de ingreso (crear, editar, eliminar con reasignación).
  2. **Métodos de pago.**
  3. **Notificaciones:** activar en este dispositivo y qué avisos recibir.
  4. **Siri y correo:** tokens y guías.
  5. **Apariencia:** tema y modo claro/oscuro.
  6. **Cuenta:** correo con el que entras, moneda, cambiar contraseña, cerrar sesión.
  7. **Administración** (solo administradores): usuarios y probar notificación.
  8. **Acerca de:** versión instalada y "Buscar actualizaciones".
- [x] La app recuerda en qué grupo estabas si cambias de pestaña y regresas.
- **Resuelto:** pantallas separadas, con esos grupos y ese orden (aprobado por el usuario).

### J. "Apartados": dinero destinado a ahorro e inversión (reemplaza la sección Metas)
El usuario aparta dinero en distintos lugares (Nu, CETES, GBM, etc.) para no gastarlo, y el lugar **cambia en cada aportación**.
- [x] Nombre propuesto por Claude: **Apartados** (pestaña y sección). Abarca ahorro e inversión, y "apartar" es como se dice en México (por confirmar con el usuario; alternativas: Ahorro e inversión, Fondos).
- [x] **Lugares:** lista editable (Nu, CETES, GBM, cuenta de ahorro, efectivo…), cada uno con su **tipo: Ahorro o Inversión**. Se pueden crear desde el formulario con "+ Agregar lugar nuevo".
- [x] **Aportar:** con **+ → Ahorro** (renombrar a "Apartar"). Se elige **el lugar en cada aportación** (la app sugiere el último usado) y, de forma opcional, una **meta**. Sin botón "Aportar" en la sección.
- [x] **Metas opcionales:** objetivo con monto y fecha (por ejemplo "Fondo de emergencia $50,000"). Una meta puede juntar dinero de varios lugares.
- [x] **Pantalla Apartados:**
  - Total apartado, total en ahorro y total en inversión.
  - Desglose por lugar (cuánto hay en Nu, CETES, GBM…).
  - Metas con su barra de progreso.
  - Historial de aportaciones (fecha, monto, lugar, meta) al tocar un lugar o una meta.
- [x] La sugerencia mensual de cuánto apartar se mantiene; sigue sin decir **dónde** invertir.
- Requiere migración nueva: tabla `savings_places` (nombre, tipo ahorro | inversion, color, activo) con RLS, `transactions.place_id`, y `goals` sigue para metas opcionales.
- **Resuelto:** el nombre **Apartados** fue aprobado por el usuario.
- [x] **Sacar dinero de un apartado** (aprobado): movimiento "Sacar de apartado" con monto, lugar y meta opcional. Resta del total de ese lugar y de la meta. No cuenta como ingreso; si luego se gasta, ese gasto se registra aparte con su método.

### L. Rendimientos estimados de los apartados
Objetivo: que el saldo de cada lugar crezca solo con un **estimado** de sus rendimientos, sabiendo que no es exacto.
- [x] Cada lugar tiene un **rendimiento anual estimado (%)**. La app calcula el saldo estimado con interés compuesto diario sobre cada aportación desde su fecha (restando lo que se sacó).
- [x] **Origen de la tasa**, según el lugar:
  - **CETES:** automático con la tasa oficial publicada por **Banxico** (API SIE, gratuita; requiere registrar un token de consulta y guardarlo como secreto en Supabase). Se actualiza sola una vez al día con `pg_cron`. Plazos: 28, 91, 182 y 364 días.
  - **Nu, cuentas de ahorro y otras cajitas:** la tasa es pública, pero no hay un servicio oficial para consultarla. El usuario la escribe (por ejemplo 9% anual) y la cambia cuando el banco la cambie. Mostrar la fecha de la última actualización.
  - **GBM, acciones, ETF y fondos:** se ligan al **instrumento** (ver punto M) para calcular el valor con precios de mercado.
- [x] **Actualizar saldo real:** el usuario escribe cuánto dice su app de Nu, GBM, etc. La diferencia se registra como **rendimiento** (o pérdida) y el estimado vuelve a partir de ese saldo.
- [x] Mostrar siempre "**estimado**" junto al saldo calculado, y el rendimiento acumulado por lugar y en total (ahorro vs. inversión).
- Pendiente de decidir: ¿descontar el ISR retenido sobre intereses o mostrar rendimiento bruto?

### K. Quitar la pestaña Fijos (aprobado por el usuario)
Objetivo: no ver lo mismo en varios lados ni tener botones de más.
- [x] **Quitar la pestaña Fijos** de la barra inferior.
- [x] En **Resumen**, una sola tarjeta **"Fijos del mes"** que junta lo que hoy está repetido (Gastos fijos, Fijos vs. variables, Próximos pagos y la pestaña Fijos): pagado, por pagar y proyectado, y los próximos pagos con "Marcar pagado".
- [x] Al tocar esa tarjeta se abre el **detalle de fijos**: la lista completa agrupada por frecuencia, donde se edita, pausa o elimina cada fijo.
- [x] La barra inferior queda: **Resumen · Movimientos · Apartados · Ajustes**. Apartados ocupa el lugar de Fijos porque es información distinta (ahorro e inversión) que hoy está escondida al fondo del Resumen.
- [x] En Movimientos, filtro rápido "Solo fijos" para ver los pagos de fijos registrados.

### M. Inversiones ligadas a un instrumento (por ejemplo VOO, S&P 500, en GBM)
- [x] Al apartar dinero en un lugar de tipo Inversión, opción **"¿En qué instrumento?"** con un **buscador** por nombre o clave de pizarra (por ejemplo `VOO`, `IVVPESO`, `NAFTRAC`, una acción como `AAPL`).
- [x] En cada compra se registra el **número de títulos** (como lo muestra GBM). Si el usuario solo sabe el monto, la app calcula los títulos aproximados con el precio de ese día.
- [x] **Valor actual = títulos × precio más reciente**, en pesos. Si el instrumento cotiza en dólares (como VOO), se convierte con el **tipo de cambio FIX de Banxico** del día. Mostrar "estimado" y la fecha y hora del precio.
- [x] Precios actualizados una vez al día (o al abrir Apartados) con una Edge Function y `pg_cron`; se guardan en la base para no consultar de más.
- [x] Por instrumento: lo invertido, el valor actual, la ganancia o pérdida en pesos y en %.
- [x] "Actualizar saldo real" sigue disponible para corregir con lo que diga GBM.
- [x] **Vender o sacar:** registrar títulos vendidos y monto recibido; calcula la ganancia realizada.
- **Fuente de precios (preferencia del usuario: "lo que sale en Google", sin registrarse en nada):**
  1. **Recomendado:** los datos públicos de **Yahoo Finanzas** (los mismos precios que muestra Google). No requieren registro ni llave. No es un servicio oficial, así que podría dejar de funcionar algún día; en ese caso la app avisa y queda "Actualizar saldo real".
  2. **Alternativa "de Google":** la función `GOOGLEFINANCE` de Google Sheets, leída por el mismo programa de Google Apps Script que se instala para Gmail, que manda los precios a Supabase. Es exactamente el dato de Google, pero requiere una hoja de cálculo en la cuenta del usuario.
  3. Servicios con llave gratuita (Twelve Data, Finnhub, Alpha Vantage) solo si las dos anteriores fallan.
  - Validar antes de construir que VOO (y lo que use el usuario) se obtenga bien. Ninguna fuente es de GBM; los valores son aproximados.
- La app muestra valores; **no recomienda** en qué invertir.

---

## 9. Cambios del 2026-10-31 — implementados en v2.0.0 (autorizados por el usuario)

Requiere la migración `004_bimestral_subcategorias.sql`.

### N. Que la app no se vea vacía ni "se trabe" sin internet o con mala señal
Problema: al abrir la app con mala conexión se veía sin nada, sin explicar qué pasaba.
- [x] **Mientras carga:** mensaje sencillo y visible, por ejemplo "Conectando con tus datos…" con un indicador de carga, en lugar de la pantalla vacía.
- [x] **Si tarda o falla** (por ejemplo, más de 10 segundos o un error de red): "No hay conexión a internet" o "No se pudo conectar con tus datos", con un botón **Reintentar**.
- [x] **Reintento automático** cuando el teléfono recupere la conexión, y cada cierto tiempo mientras siga sin conexión, sin que el usuario tenga que cerrar la app.
- [x] **Mostrar lo último que se cargó:** guardar en el dispositivo la última información descargada y mostrarla sin conexión, con un aviso arriba como "Sin conexión · mostrando datos del 31/10 a las 10:15". En ese modo, avisar que los cambios no se pueden guardar hasta tener conexión.
- [x] **Que la app abra aunque no haya internet:** hoy el service worker no guarda nada en caché, así que sin red el iPhone no puede ni cargar la página. Guardar la app (HTML, config.js y la librería de Supabase) para abrirla sin conexión: siempre se intenta primero la versión de internet (para no perder actualizaciones) y, si falla, se usa la guardada.
- [x] Que ningún error de conexión deje botones sin responder o pantallas a medias: todo error muestra un mensaje claro y permite reintentar.
- **Decisión del usuario:** **no** se permite registrar nada sin conexión (no se guardan movimientos para subirlos después). Ver punto U.

### O. Aviso de nueva versión abajo
- [x] El aviso "Hay una nueva versión · Actualizar" aparece **abajo** en lugar de arriba: justo encima de la barra de pestañas (sin tapar la barra ni el botón +), respetando el área segura del iPhone. En computadora, abajo al centro.

### P. Campo de monto con formato de dinero mientras se escribe
Aplica a todos los campos de monto (gasto, ingreso, retiro, apartados, confirmar pendientes, fijos, metas, saldo real).
- [x] Mostrar el **signo de pesos** fijo al inicio del campo (`$`), sin que el usuario tenga que escribirlo.
- [x] **Comas de miles automáticas** mientras se escribe: `1000` → `1,000`; `25000` → `25,000`; `1250000` → `1,250,000`. El cursor no debe brincar al reformatear.
- [x] **Centavos:**
  - Si no se escriben, se ve `.00` en **tono claro** (como sugerencia) después del número: `$1,000` + `.00` gris.
  - Si se escribe el punto y nada más (`1000.`), se toma como `.00` (el `00` se sigue viendo claro).
  - Con un decimal (`1000.1`) se toma como `.10` (el `0` faltante en claro).
  - Con dos decimales (`1000.15`) se toma tal cual.
  - **Máximo dos decimales**: un tercer dígito después del punto no se acepta.
- [x] Solo se aceptan números y un punto decimal; la coma la pone la app (si el teclado escribe coma como decimal, se convierte en punto).
- [x] Teclado numérico con punto decimal en el iPhone.
- [x] Al guardar se usa el valor numérico (por ejemplo `1000.1` → 1000.10).

### Q. Registrar un pago que corresponde a un fijo existente (pago atrasado o adelantado)
Caso: no se confirmó a tiempo un fijo (o se pagó antes o después de su fecha) y el usuario lo registra con el **+**.
- [x] En el formulario del **+**, al marcar "Es fijo", primero preguntar: **"¿Es de un fijo que ya tienes?"** con la lista de fijos del mismo tipo (gasto o ingreso) y la opción "No, es un fijo nuevo" (el comportamiento actual).
- [x] Al elegir un fijo existente:
  - Se llenan solos la categoría, el método y el monto sugerido (editable).
  - Elegir **a qué fecha programada corresponde** el pago: la app propone la fecha pendiente (sin pagar) más cercana a la fecha escrita y deja elegir otra de la lista (fechas vencidas sin pagar, la actual y la siguiente).
  - La fecha del movimiento es la que escribió el usuario (cuando realmente pagó).
- [x] Si la fecha real es distinta a la programada, preguntar: **"Pagaste el 13/10 y estaba programado el 15/10. ¿Cambiar las próximas fechas?"**
  - **No, solo esta vez** (recomendado): el calendario del fijo no cambia; esa fecha programada queda como pagada.
  - **Sí, a partir de ahora:** el calendario se recorre según la frecuencia:
    - **Mensual:** las próximas fechas pasan al nuevo día del mes (por ejemplo, del 15 al 13).
    - **Semanal, quincenal (cada 15 días) y diario:** el ciclo vuelve a contar desde la nueva fecha.
    - **Quincena de salario (15 y último día del mes):** **no se puede cambiar**; siempre "solo esta vez". Solo se pregunta a qué quincena corresponde (la del 15 o la de fin de mes).
- [x] Si esa fecha programada ya tenía un **pendiente por confirmar**, se marca como aceptado (no se duplica) y el monto queda como sugerencia para la próxima vez, igual que al confirmar desde Pendientes.
- [x] Cuidar que no se registre dos veces la misma fecha programada: si ya está pagada, avisar y no permitir elegirla.
- **Decisión del usuario:** cada movimiento cubre **una sola fecha programada**. Si un pago cubre dos fechas atrasadas, se registra un movimiento por cada fecha. (Así funciona desde v2.0.0; no requiere cambios.)

### R. Frecuencia bimestral
- [x] Nueva frecuencia **Bimestral (cada 2 meses)** para fijos, junto a diario, semanal, quincenal y mensual. Se repite el mismo día cada dos meses desde la primera fecha (por ejemplo 10/ene, 10/mar, 10/may…). Si el día no existe en ese mes (31 en abril), se usa el último día del mes, igual que en mensual.
- [x] Incluirla en el cálculo de próximos pagos, proyectado del mes, pendientes automáticos (servidor) y en el punto Q (recorrer el calendario).
- Requiere migración: agregar `bimestral` a la lista de frecuencias de `recurrences` y a `recurrence_on_or_after`.

### S. Subcategorías (opcionales)
Recomendación de Claude: **sí vale la pena**, con **un solo nivel** (categoría → subcategoría), para agrupar sin complicar el registro.
- [x] Una categoría puede tener subcategorías. Ejemplos: **Casa** → Teléfono, Internet, Agua, Luz; **Escuela de mi hijo** → Colegiatura, Uniformes, Útiles, Transporte.
- [x] Al registrar un gasto o ingreso: se elige la categoría y, **si tiene subcategorías**, aparece una segunda opción con sus subcategorías y **"Sin subcategoría"** (preseleccionada). Las categorías sin subcategorías funcionan como hoy.
- [x] "+ Agregar subcategoría nueva" ahí mismo, igual que con las categorías.
- [x] **Resumen → Por categoría:** se muestra el total de cada categoría (suma de sus subcategorías y de lo registrado sin subcategoría); al tocarla se despliega el desglose por subcategoría.
- [x] Presupuesto por categoría (como hoy) y, opcional, por subcategoría.
- [x] Filtros de Movimientos: por categoría (incluye sus subcategorías) o por una subcategoría concreta. El CSV incluye columna Subcategoría.
- [x] **Ajustes → Categorías:** cada categoría muestra sus subcategorías; se pueden crear, editar, eliminar y **mover una categoría existente dentro de otra** (por ejemplo, convertir "Luz" en subcategoría de "Casa") sin perder sus movimientos.
- [x] Al eliminar una categoría con subcategorías o movimientos: misma reasignación que hoy (elegir a dónde moverlos; nunca se borran).
- [x] Fijos, pendientes de Siri/Gmail y la adivinanza de categoría también pueden usar subcategoría.
- Requiere migración: columna `categories.parent_id` (un solo nivel) y ajustes en la reasignación al eliminar.

### T. Sección "Por confirmar" con detalle de cada movimiento
Hoy los pendientes se ven en el botón naranja del encabezado y en "Fijos del mes" solo con un botón "Confirmar" que abre un formulario.
- [x] Sección clara **"Por confirmar"** (gastos e ingresos), visible en el Resumen (tarjeta arriba con los primeros y "Ver todos ›") y desde el botón naranja del encabezado.
- [x] Cada renglón se puede **tocar completo** para entrar a su **pantalla de detalle** (con la animación de deslizar y el gesto para regresar).
- [x] **Detalle** de un movimiento por confirmar:
  - Monto, fecha, categoría (y subcategoría), método de pago y nota.
  - **De dónde viene:** fijo (nombre, frecuencia, fecha programada), Siri (lo que se dijo) o correo del banco (asunto, cuenta **9607, hora, cajero o comercio, folio).
  - Si es un fijo: los **últimos pagos** de ese fijo (fechas y montos) para comparar.
  - Acciones: **Confirmar** (permite editar antes los datos), **Descartar**, y "Ver o editar el fijo" si aplica.
- [x] Opción "Confirmar todos" para los que no necesitan cambios, con confirmación previa.

---

## 10. Cambios del 2026-10-31 (segunda tanda) — implementados en v2.0.1 (autorizados por el usuario)

### U. Bloquear registros sin conexión
Hoy, sin internet, el **+** abre el formulario y solo al tocar "Agregar" sale el error "Sin conexión".
- [x] Sin conexión, el botón **+** se ve desactivado (gris) y al tocarlo dice: "Sin conexión: no puedes registrar movimientos hasta que vuelva el internet".
- [x] Lo mismo para todo lo que guarda o borra datos: editar o eliminar movimientos, confirmar o descartar pendientes, "Marcar pagado", fijos, categorías, métodos, lugares, metas, saldo real, tema de notificaciones, tokens, etc. Se pueden **ver** los datos guardados, pero no cambiarlos.
- [x] Si se pierde la conexión con un formulario abierto, al tocar "Agregar" o "Guardar" se avisa y **no se cierra** el formulario (para no perder lo escrito); al volver la señal se puede guardar.
- [x] Al volver la conexión, todo se reactiva solo.

---

## 11. Cambios del 2026-10-31 (tercera tanda) — implementados en v2.0.2 (autorizados por el usuario)

Nota X: además, para pagos anteriores a la primera fecha del fijo, el calendario se extiende hacia atrás con la misma regla (antes un salario del 30/sep de un fijo creado en octubre se asignaba al 15/oct).

### V. Cantidad encima de cada barra de la gráfica
Hoy el número solo sale en algunas barras (no en "Ambos" ni cuando hay más de 12 barras).
- [x] Mostrar siempre la cantidad encima de **cada** barra, en Semana, Mes y Año, y en Gastos, Ingresos y Ambos (en "Ambos", una cifra sobre la barra verde y otra sobre la roja, cada una de su color).
- [x] Formato corto para que quepa: `$950`, `$12,500`, y con muchas barras o cifras grandes, abreviado (`$12.5k`, `$1.2M`). Si no cabe horizontal, la cifra va vertical sobre la barra.
- [x] Las barras en cero no muestran cifra.

### W. Confirmar con un solo toque
Hoy "Confirmar" abre la ventana para revisar monto, categoría, etc.
- [x] El botón **Confirmar** registra el movimiento de inmediato con sus datos actuales, sin abrir ninguna ventana (en "Fijos del mes", en la lista "Por confirmar" y en el detalle).
- [x] Aviso breve "Confirmado: Colegiatura $2,000" con opción **Deshacer** por unos segundos, por si se tocó por error.
- [x] Si se quiere cambiar algo antes, se usa un botón aparte **Editar** (en el detalle del movimiento por confirmar), que abre la ventana actual.

### X. Pago de un fijo existente: sin el menú "¿A qué fecha corresponde?"
Problema (captura del usuario): al registrar el salario del **30 de septiembre**, el campo Fecha decía 30/sep pero el menú de abajo proponía **31 de octubre**. El menú se calcula al elegir el fijo y no siempre se actualiza al cambiar la fecha en el iPhone; además, si la fecha ya estaba pagada, propone otra. Confunde tener dos fechas.
- [x] Quitar el menú "¿A qué fecha corresponde?". La única fecha es la del campo **Fecha** y el usuario elige la que quiera.
- [x] La app asigna sola el pago a la fecha programada **más cercana sin pagar** a esa fecha (para salario: 30/sep → quincena del 30 de septiembre) y lo muestra en una línea pequeña debajo: "Se registrará como el pago del 30 de septiembre".
- [x] Recalcular esa línea en cuanto cambie la fecha (escuchar también el evento `input`, que es el que dispara el iPhone).
- [x] Si la fecha programada más cercana **ya está pagada**, decirlo: "El pago del 30 de septiembre ya está registrado; este se tomará como el del 15 de octubre", para evitar duplicados sin sorpresas.
- [x] Si no hay ninguna fecha programada cerca (más de un periodo de distancia), registrar el movimiento ligado al fijo con su propia fecha, sin marcar otra como pagada.
- [x] La pregunta "¿Cambiar las próximas fechas?" solo aparece si la fecha elegida es distinta a la programada (nunca para salario).

---

## 12. Cambios del 2026-11-02 — implementados en v2.1.0 (autorizados por el usuario)

Requiere la migración `005_semestral_anual_avisos_faceid.sql`, la función nueva `passkeys` y volver a desplegar `notificaciones`.
Valores usados donde faltaba confirmar: resumen diario activado de inicio; cierre de sesión 5 min en celular y 15 en navegador (configurable 2/5/15/30); trimestral **no** agregado (pendiente de respuesta).
Nota AA/AB: el bloqueo con Face ID quedó integrado en el inicio de sesión: al cerrarse la sesión por inactividad, en el celular se vuelve a entrar con Face ID/huella.

### Y. Frecuencias semestral y anual
- [x] **Semestral (cada 6 meses):** el mismo día cada 6 meses desde la primera fecha (por ejemplo 10/ene y 10/jul).
- [x] **Anual (cada año):** el mismo día y mes cada año (por ejemplo predial, tenencia, seguro del auto). Si la fecha es 29 de febrero, en años no bisiestos se usa el 28.
- [x] Igual que bimestral: si el día no existe en ese mes, se usa el último día del mes.
- [x] Incluirlas en: formulario del +, editar fijo, pestaña de fijos (agrupadas), próximos pagos, proyectado del mes, pendientes automáticos del servidor, avisos, pago de un fijo existente (asignar la fecha más cercana, también hacia atrás) y "¿Cambiar las próximas fechas?".
- [x] En "Fijos del mes", los semestrales y anuales solo aparecen en el mes que les toca; en el detalle de fijos se muestra cuándo es el próximo (por ejemplo "Próximo: 10 de enero de 2027").
- Requiere migración 005: agregar `semestral` y `anual` a las frecuencias y a `recurrence_on_or_after` (mismo cálculo que mensual/bimestral con saltos de 6 y 12 meses).
- **Decisión del usuario:** no se agrega trimestral.

### Z. Corregir avisos de "por confirmar" que no llegan (reporte del usuario)
Diagnóstico: la notificación de prueba sí llega (el envío funciona), pero los avisos de pendientes no, por tres fallas de diseño:
1. Al abrir la app, `generate_pending_entries` (llamada por el usuario) **borra** los avisos aún no enviados de fijos ("pend:rec:%"). Si se abre la app antes de las 9:00, el aviso del día se pierde.
2. Los pendientes que crea la app al abrirse (antes que la tarea de las 00:05, o atrasados) **nunca programan aviso**.
3. Solo hay recordatorio diario para pendientes de Siri/Gmail; los fijos sin confirmar no se vuelven a recordar.

Cambios (requiere migración 005 y actualizar la función `notificaciones`):
- [x] No borrar avisos al abrir la app; programar aviso para todo pendiente nuevo, lo cree el servidor o la app.
- [x] Guardar en cada aviso a qué pendiente corresponde; justo antes de enviarlo, **no mandarlo si ese pendiente ya se confirmó o descartó** (así no llegan avisos de algo ya atendido).
- [x] **Resumen diario a las 9:00 a.m.** si hay movimientos por confirmar de cualquier origen (fijos, Siri, correo): "Tienes 3 movimientos por confirmar · Sueldo $15,000, Colegiatura $2,000…". Un solo aviso al día, aunque se haya abierto la app.
- [x] El resumen diario es **opcional**: casilla "Resumen diario de pendientes (9:00 a.m.)" en Ajustes → Notificaciones, junto a las demás preferencias. Decisión del usuario.
  - Por confirmar: ¿activado o desactivado de inicio? (propuesta: activado).
- [x] Mantener el aviso individual el día que toca cada fijo (9:00 a.m., o al momento si ya pasó esa hora).
- [x] Verificar con el usuario que las tareas automáticas (`generar-pendientes`, `recordar-pendientes`, `enviar-notificaciones`) estén activas.

### AA. Desbloquear la app con Face ID o huella (propuesta, por confirmar)
Es posible con la tecnología estándar de los navegadores para Face ID/Touch ID (WebAuthn/passkeys), que funciona en la app instalada en el iPhone (iOS 16 o más reciente).
- Opción recomendada · **Bloqueo de la app con Face ID:**
  - [ ] En Ajustes → Cuenta, interruptor "Pedir Face ID al abrir". Al activarlo, el iPhone pide Face ID una vez para registrar el dispositivo.
  - [ ] Al abrir la app (y al volver a ella después de X minutos en segundo plano, a elegir: al momento, 1, 5 o 15 minutos), la pantalla queda cubierta con un botón **"Desbloquear con Face ID"**; los datos no se muestran hasta desbloquear.
  - [ ] Si Face ID falla o no está disponible: "Usar contraseña" (inicia sesión de nuevo con correo y contraseña).
  - [ ] Es un bloqueo del dispositivo: la sesión sigue guardada en el teléfono, pero nadie puede ver tus finanzas sin tu cara o huella. Cada dispositivo se configura por separado.
- **Precisiones del usuario (2026-11-02):**
  - [ ] **Solo en el celular con la app instalada** (iPhone o Android, abierta desde el icono). En el navegador web o en computadora **no** se pide biometría ni aparece la opción.
  - [ ] **No se elige el método: lo decide el teléfono.** El sistema usa lo que tenga: Face ID o Touch ID en iPhone; huella o reconocimiento facial en Android. Si el teléfono no tiene biometría, usa su código o patrón de desbloqueo.
  - [ ] Antes de mostrar la opción, la app revisa que el teléfono tenga un método de desbloqueo disponible; si no lo tiene, la opción no aparece.
  - [ ] Textos según el equipo: "Desbloquear con Face ID" en iPhone, "Desbloquear con huella o rostro" en Android.
- **Decisión del usuario:** sí quiere la opción completa (iniciar sesión con Face ID/huella), ver punto AB.
- Opción más completa (más trabajo) · **Iniciar sesión sin contraseña con passkey:** reemplaza correo y contraseña por Face ID también al iniciar sesión en un dispositivo nuevo. Requiere una función nueva en el servidor para verificar la llave; se puede hacer después si se quiere.

### AB. Iniciar sesión con Face ID/huella y cerrar sesión automáticamente
- [x] **Inicio de sesión con passkey** (en el celular con la app instalada): después del primer inicio con correo y contraseña, ofrecer "Usar Face ID para entrar". Las siguientes veces, el botón **"Entrar con Face ID"** (o "con huella" en Android) inicia sesión sin escribir la contraseña. El teléfono decide el método (Face ID, Touch ID, huella, rostro o código).
- [x] En navegador web y computadora: solo correo y contraseña (como hoy).
- [x] Requiere: función nueva en el servidor que registre y verifique las llaves (passkeys) y abra la sesión; tabla de llaves por usuario y dispositivo (se pueden ver y borrar en Ajustes → Cuenta).
- [x] **Cierre de sesión automático** tras un tiempo sin usar la app. Al volver se pide Face ID/huella (celular) o contraseña (navegador).
- **Decisiones del usuario:** el cierre automático aplica **también en el navegador**.
- Referencia investigada: la app de BBVA México se cierra sola tras **2 minutos** sin actividad (folleto oficial de la app); la banca en línea y el estándar de pagos con tarjeta (PCI DSS) usan **15 minutos** de inactividad como referencia común.
- [x] Propuesta de Claude (por confirmar): **celular 5 minutos** (volver a entrar es solo Face ID) y **navegador 15 minutos** (hay que escribir la contraseña). Configurable en Ajustes → Cuenta: 2, 5, 15 o 30 minutos.
- [x] Un minuto antes de cerrar en el navegador, aviso "Tu sesión se cerrará por inactividad · Seguir conectado".

### AC. Animación de bienvenida al iniciar sesión
- [x] Al iniciar sesión (con contraseña o Face ID), pantalla de bienvenida de 2–3 segundos: la palabra **"Hola"** se va "escribiendo" en letra manuscrita con trazo animado (inspirada en el saludo del iPhone, con diseño propio), sobre el color del tema; luego aparece "Irving" (nombre del perfil) y la pantalla se desvanece hacia el Resumen.
- [x] Se puede saltar tocando la pantalla. Respeta "Reducir movimiento" (solo aparece el texto, sin animación).
- **Decisiones del usuario:** aparece **cada vez que se entra a la sesión**. Texto: **"Hola" + el nombre** (por ejemplo "Hola Irving"), con el **mismo tipo de animación que el saludo del iPhone**: letra cursiva de trazo continuo que se va dibujando como si se escribiera a mano.
- Nota: el letrero "hello" del iPhone y su tipografía son diseño propio de Apple y no se pueden copiar tal cual; se recrea el mismo efecto con una tipografía cursiva de trazo similar (libre, de Google Fonts) convertida en trazos animados.

---

## 13. Cambios del 2026-11-02 (segunda tanda) — implementados en v2.2.0 (autorizados por el usuario)

Requiere las migraciones 006 y 007 y volver a desplegar `notificaciones` y `admin-usuarios`. Pendiente de confirmar: ocultar montos en los avisos (AI, opcional).

### AD. El nombre de la bienvenida sale de los datos de la cuenta
- [x] Guardar el nombre en el **perfil de la cuenta** (datos del usuario en Supabase, `full_name`), no en un campo que el usuario escribe en la app. La app lo lee de la sesión, así que "Hola Irving" sale desde el primer inicio, en cualquier dispositivo.
- [x] Se quita el campo "Tu nombre" de Ajustes → Cuenta (solo se muestra el nombre).
- [x] Administración: al **agregar o invitar** un usuario se captura su nombre; el administrador puede corregirlo en la lista de usuarios.
- [x] Para la cuenta actual: llenarlo una vez desde el servidor (migración o una línea de SQL) con el nombre que confirme el usuario.
- **Decisión del usuario:** el nombre de la cuenta actual es **"Irving"** (solo el nombre, sin apellido).

### AE. Pantalla de inicio de sesión que recuerda la cuenta y prioriza Face ID
- [x] Al cerrar sesión, la pantalla de inicio muestra la **última cuenta usada** (nombre y correo, por ejemplo "Irving · isegura@…") ya escrita; la **contraseña nunca se guarda ni se muestra**.
- [x] Si Face ID / huella está activado en ese teléfono: el botón principal es **"Entrar con Face ID"** y el campo de contraseña aparece **atenuado/plegado**, con el enlace "Entrar con contraseña" para desplegarlo.
- [x] Si no está activado (o en el navegador): se ve el correo ya escrito y el campo de contraseña normal.
- [x] Enlace "Usar otra cuenta" para borrar el correo recordado y escribir otro.

### AG. Al iniciar sesión, siempre al Resumen
- [x] Cada vez que se inicia sesión (con contraseña o Face ID, incluso tras el cierre por inactividad) la app abre en **Resumen**, en el mes actual, sin importar en qué pantalla se quedó antes (Ajustes, un lugar de Apartados, Fijos, etc.).
- [x] Al solo volver a la app sin que se haya cerrado la sesión, se queda donde estaba (como hoy).

### AH. Mandar avisos a pedido desde el chat con Claude — implementado (migración 006, autorizado por el usuario)
- [x] Nueva acción en la función `notificaciones`: `{"action":"custom","title","body","minutes"}` con `Authorization: Bearer <token personal>` (los mismos tokens de Siri/Gmail, guardados hasheados). Programa un aviso para el dueño del token, al momento o en N minutos (máximo 7 días), con tipo "mensaje".
- [x] El token solo permite mandar avisos y registrar pendientes; no da acceso a ver datos. Se revoca en Ajustes → Siri y correo.
- [x] El usuario genera un token "Claude" y lo comparte en el chat; Claude envía los avisos con una llamada a la función cuando el usuario lo pida.
- Requiere migración (agregar el tipo "mensaje" a los avisos) y volver a desplegar `notificaciones`.

### AI. Avisos y varias cuentas en un mismo teléfono
- Hoy un teléfono solo puede recibir avisos de la primera cuenta que los activó, y los sigue recibiendo aunque entre otra cuenta o se cierre sesión.
- [x] "Cerrar sesión" a mano apaga los avisos en ese teléfono; el cierre por inactividad no.
- [x] Si otra cuenta activa los avisos en ese teléfono, el teléfono pasa a esa cuenta (desde el servidor).
- **Decisión del usuario:** los avisos siguen mostrando montos; la privacidad en la pantalla bloqueada queda a cargo de la configuración del iPhone (Configuración → Notificaciones → Finanzas → Mostrar vistas previas). No requiere cambios en la app.

### AF. El aviso "¿Usar llave de acceso?" del iPhone
- Es la ventana de seguridad de Apple (nombre de la cuenta + Continuar → Face ID); la app no la puede quitar ni cambiar.
- **Decisión del usuario:** el acceso con Face ID **se queda como está** (botón + ventana de Apple). No se agrega el modo autocompletar ni se hace app nativa.
- ~~Opcional: usar el modo "autocompletar" de llaves de acceso: al tocar el campo de correo, el iPhone ofrece la llave arriba del teclado y basta tocarla y mirar el teléfono, sin la ventana grande. Se mantiene también el botón "Entrar con Face ID".~~

---

## 14. Cambios anotados el 2026-11-02 (tercera tanda) — ✅ aplicados en la versión 2.3.0 (2026-11-03)

### AJ. "Fijos del mes": botones a la derecha y confirmación para pagos fuera de fecha
- [ ] En cada renglón de "Fijos del mes" (y en "Por confirmar"), el botón **Marcar pagado / Marcar recibido / Confirmar** va **a la derecha**, en la misma línea que el nombre y el monto (hoy en el teléfono baja a otra línea a la izquierda).
- [ ] Si el pago está **fuera de fecha** (vencido), al tocar **Marcar pagado** (gastos) o **Marcar recibido** (ingresos) aparece una ventana de confirmación:
  - "¿Seguro que quieres marcar como pagado este movimiento fuera de fecha?"
  - Muestra nombre, monto y la fecha en que estaba programado (por ejemplo "Gasolina · $600 · programado el 2/10").
  - Botones: **Cancelar** y **Sí, marcar pagado** (o "Sí, marcar recibido").
- [ ] Los que están en fecha se marcan directo, como hoy.
- Por confirmar con el usuario:
  - ¿Con qué fecha se registra el movimiento vencido: la **programada** (como hoy) o la de **hoy**? Propuesta: dar las dos opciones en la ventana. **Decidido (2026-11-03): la ventana ofrece las dos fechas** (programada u hoy).
  - ¿La confirmación aplica también al botón **Confirmar** de los pendientes vencidos?

### AK. Gráfica: al elegir Mes o Año, mostrar todo el historial
Problema (usuario): al elegir **Mes** solo aparece noviembre, y en **Año** solo 2026. Causa: el periodo se queda en "Este mes" aunque se cambie la agrupación, así que solo hay una barra.
- [ ] Al tocar **Mes**, el periodo cambia solo a **"Todo"**: una barra por cada mes desde el primer movimiento registrado hasta hoy.
- [ ] Al tocar **Año**, el periodo cambia solo a **"Todo"**: una barra por cada año con movimientos (cuánto se gastó o ganó en cada año).
- [ ] Al tocar **Semana**, el periodo vuelve a **"Este mes"** (las semanas del mes elegido).
- [ ] Después se puede seguir eligiendo otro periodo en el menú (por ejemplo, Mes con "Últimos 6 meses").
- [ ] Quitar del menú las combinaciones que solo darían una barra (por ejemplo "Este mes" cuando se agrupa por Mes, o "Este año" cuando se agrupa por Año).
- [ ] Revisar que "Todo" cargue los movimientos de todos los años (hoy la app solo tiene a mano los últimos 6 meses y pide el resto al servidor).

### AL. Grupos de gastos (por ejemplo "Casa", "Médicos", "Innecesarios")
Objetivo del usuario: marcar gastos en grupos propios y ver al final del mes cuánto se fue en cada uno (sobre todo "Innecesarios") para tomar decisiones.
- Diferencia con las categorías: la **categoría** dice *qué* es (Comida, Gasolina); el **grupo** es una etiqueta propia de *para qué* o *cómo lo juzgo* (Casa, Médicos, Innecesarios). Un "Café" puede ser categoría Comida y grupo Innecesarios.
- [ ] **Cada gasto puede estar en un solo grupo** (o en ninguno). No se puede meter un gasto en varios grupos.
- [ ] **Ajustes → Grupos:** crear, editar (nombre y color), eliminar. Al eliminar un grupo con gastos, los gastos se quedan sin grupo o se pasan a otro (nunca se borran).
- [ ] **Formulario del +:** campo opcional **"Grupo"** (Sin grupo / Casa / Médicos / Innecesarios… / "+ Agregar grupo nuevo"). También al confirmar pendientes, al editar un movimiento y en los fijos (un fijo puede tener grupo y sus pagos lo heredan).
- [ ] **Resumen:** tarjeta **"Por grupo"** con el total del mes de cada grupo, su % del gasto y la comparación con el mes anterior (por ejemplo "Innecesarios $1,850 · 9% · ↑ $400 vs octubre"). Tocar un grupo muestra sus gastos.
- [ ] **Movimientos:** filtro por grupo; el grupo aparece como etiqueta en cada gasto. CSV con columna Grupo.
- [ ] **Tope mensual opcional** por grupo (por ejemplo "Innecesarios: máximo $1,500"), con barra de avance en la tarjeta.
- Requiere migración: tabla `expense_groups` (RLS por usuario) y columna `group_id` en `transactions`, `recurrences` y `pending_entries`.
- **Decisiones del usuario:** los grupos son **solo para gastos**. El **tope mensual es opcional** por grupo (se puede poner o no). La tarjeta "Por grupo" va en el **Resumen**.
- [ ] Avisos del tope: dentro de la app (barra en ámbar al 80% y roja al pasarse) y **notificación** al llegar al 80% y al rebasar el tope (una vez por mes y grupo; se puede apagar en Ajustes → Notificaciones).

### AM. Rediseño del Resumen: limpio y fácil de entender (propuesta de Claude, por aprobar)
Investigación (resumen): las guías de diseño de tableros y finanzas coinciden en **mostrar primero un resumen y dar el detalle solo al tocar** (revelación progresiva), poner arriba **la cifra más importante**, agrupar lo relacionado y usar gráficas de barras o líneas. Apps como Copilot ponen arriba un **"Libre para gastar"** del mes, y Monarch destaca **cuánto te quedará**.

Propuesta (máximo 5 bloques, siempre en el mismo orden):
1. **¿Cómo voy este mes?** Una sola cifra grande: **"Te quedan $X"** (ingresos + por recibir − gastado − por pagar − apartado), con una barra Gastado / Por pagar / Libre y una línea "Gastaste $9,650 de $24,898".
2. **Necesita tu atención** (solo aparece si hay algo): pendientes por confirmar, pagos vencidos y topes de grupo rebasados, en una lista corta; tocar lleva a cada uno.
3. **Próximos pagos:** los 3 más cercanos y "Ver todos".
4. **¿En qué se fue?** Una sola tarjeta con selector **Categorías · Grupos · Métodos**: los 5 principales con barra y % (y tope en grupos); "Ver todo" para el resto.
5. **Tendencia:** la gráfica (mes a mes por defecto), con la comparación contra el mes anterior.
- [ ] Se quitan del Resumen (o se mueven a su detalle): "Fijos vs. variables" (al detalle de Fijos), "Gastos más grandes" (a Movimientos, como orden "Más grandes"), cifras repetidas.
- [ ] Antes de aplicarlo, mostrar al usuario una maqueta visual para aprobarla.
- Maqueta hecha (claro y oscuro): https://claude.ai/artifact/CvW4v86VpMUM9xhVash2go
- **Decisiones del usuario sobre la maqueta:**
  - Se quita la línea "unos $X por día" debajo de "Te quedan libres".
- **Decisión del usuario sobre el botón Pagar** de un pago vencido en "Necesita tu atención": abre la misma ventana de AJ (nombre, monto editable, método y fecha programada; botones **Registrar con fecha programada**, **Registrar con fecha de hoy** y **Cancelar**) y registra el gasto sin salir del Resumen.
- **Decisión del usuario sobre los vencidos:** "Necesita tu atención" busca los pagos vencidos **de cualquier mes, sin límite de tiempo** (no solo del mes que se está viendo).
  - Vencido = fecha programada de un fijo que ya pasó y que no está registrado (por pagar) o cuyo pendiente no se ha confirmado.
  - Se busca desde la fecha de inicio de cada fijo hasta ayer.
  - Hoy la app solo los marca dentro del mes abierto (`monthPlan`); al cambiar de mes se pierden de vista. Con este cambio siguen apareciendo hasta que se pagan, se confirman o se descartan.
  - Cada uno muestra la fecha en que estaba programado (por ejemplo "Internet $599 · era el 30 oct").
- **Decisión del usuario sobre la cifra principal:** un botón **muy discreto** (icono pequeño de flechas ⇅, en gris, junto a la etiqueta) cambia entre **"Te quedan libres $X"** y **"Gastado este mes $X"** (en rojo, con "de $ingresos · N%").
  - La app recuerda la última elección en ese teléfono.
  - Por defecto: "Te quedan libres".

### AN. Ver rápido el mes anterior y volver siempre al mes en curso
Necesidad del usuario: los primeros días del mes casi no hay nada registrado y se quiere repasar el mes que acaba de cerrar, sin perder que la app abra siempre en el mes en curso.
- [ ] **Tarjeta "Cierre del mes"** arriba del Resumen, **del día 1 al 5** de cada mes:
  - "**Octubre cerró** · Gastaste $12,250 de $24,898.60 de ingresos · te sobraron $12,648.60" y el enlace **"Ver resumen de octubre ›"**, que cambia el Resumen a ese mes.
  - Desaparece sola el día 6, o antes si se cierra con la ✕ (se recuerda en ese teléfono para ese mes).
  - **Decisión del usuario:** si se gastó menos que los ingresos del mes: "te sobraron **$X**" en **verde**; si se gastó más: "**te pasaste por $X**" en **rojo**. (La base es lo ingresado ese mes; hoy la app no tiene presupuesto general.)
- [ ] **Siempre volver al mes en curso:**
  - Al iniciar sesión (ya se hace hoy).
  - También al abrir la app tras **30 minutos** o más sin usarla.
  - Mientras se ve otro mes, aparece un botón pequeño **"Volver a noviembre"** (con el nombre del mes en curso) para regresar de un toque.
- Nota: las flechas ‹ › a los lados del mes **ya existían** en la app (Claude las propuso por error como algo nuevo); se quedan como están.

---

## 15. Versión 2.3.0 (2026-11-03): qué se aplicó

El usuario pidió "aplica cambios". Se aplicaron AJ, AK, AL, AM y AN:
- [x] **AJ.** Botones a la derecha en "Próximos pagos" y "Necesita tu atención". Al marcar un fijo **vencido** (o confirmar un pendiente de fijo vencido) aparece la ventana "¿Seguro que quieres marcar como pagado este movimiento fuera de fecha?", con monto y método editables y dos botones: **Con la fecha programada** y **Con la fecha de hoy**.
- [x] **AK.** Gráfica: Mes y Año cambian el periodo a "Todo"; Semana regresa a "Este mes"; ya no se ofrecen periodos de una sola barra. Por defecto: mes a mes con todo el historial.
- [x] **AL.** Grupos de gastos (solo gastos, uno por gasto): Ajustes → Grupos de gastos (crear, editar, eliminar moviendo sus gastos), campo Grupo en el +, en pendientes y en fijos, pestaña Grupos en "¿En qué se fue?", filtro y etiqueta en Movimientos, columna Grupo en el CSV, tope mensual opcional (ámbar al 80%, rojo al rebasar) y aviso al 80% y al rebasarlo (una vez por mes y grupo; se apaga en Ajustes → Notificaciones). **Requiere la migración 008.**
- [x] **AM.** Resumen nuevo: ¿Cómo voy este mes? (Te quedan libres ⇄ Gastado con el botón discreto, se recuerda en el teléfono) · Necesita tu atención (por confirmar, vencidos de cualquier mes, topes rebasados) · Próximos pagos (3) · ¿En qué se fue? (Categorías · Grupos · Métodos) · Tendencia. "Fijos vs. variables" pasó al detalle de Fijos y "Gastos más grandes" a Movimientos (botón "Más grandes").
- [x] **AN.** Tarjeta "Octubre cerró" del día 1 al 5 (te sobraron en verde / te pasaste por en rojo), botón "Volver a noviembre" cuando se ve otro mes, y la app vuelve al mes en curso al abrirla tras 30 minutos.
- Detalle: los vencidos solo cuentan desde el día en que el fijo se dio de alta en la app (para que un fijo con fecha de inicio antigua no aparezca con meses "vencidos").

### Regla nueva del usuario (2026-11-03)
- **Cada vez que se suba un cambio o actualización, mandar una notificación al iPhone del usuario** (con su token de Claude, solo en la conversación; el token no se guarda en el repositorio).

---

## 16. Cambios anotados el 2026-11-03 (después de la versión 2.3.0) — ✅ aplicados en la versión 2.3.1

### AO. Colores fijos en "¿Cómo voy este mes?"
Problema (usuario): la cifra grande cambia de color según el tema (hoy usa el color principal del tema: verde en Bosque, morado en Ciruela, naranja en Mandarina…).
- [ ] **"Te quedan libres"** siempre en **verde** (color de ingresos) en todos los temas.
- [ ] **"Gastado este mes"** y **"Te faltan"** siempre en **rojo** (color de gastos) en todos los temas.
- Misma regla que ya se usa en todo: lo que queda o entra, verde; lo gastado o lo que falta, rojo.

### AP. Igualar el Resumen a la maqueta aprobada (por confirmar con el usuario)
Problema (usuario): en la versión 2.3.0 se aplicó el contenido de la maqueta, pero no su aspecto (Claude reutilizó los estilos que ya tenía la app).
Diferencias encontradas:
1. Títulos de sección: en la maqueta son etiquetas chicas, grises y en mayúsculas ("NECESITA TU ATENCIÓN"); en la app son títulos negros en negrita.
2. Tendencia: en la maqueta es una gráfica simple de 6 meses sin controles, con el mes actual en rojo y los anteriores en gris; en la app quedó la gráfica anterior con todos sus controles y todas las barras en rojo.
3. Botones: en la maqueta "Pagar" es texto verde sin fondo y "Próximos pagos" no tiene botones; en la app son botones rellenos rojos y verdes.
4. Iconos de la barra de abajo: en la maqueta casa, lista, cartera y engrane, con la pestaña activa en verde; en la app quedaron los de antes, con la pestaña activa en negro.
5. Encabezado: en la maqueta "Hola, Irving" arriba de "Resumen" y el mes en una pastilla; en la app quedó el encabezado de siempre.
Propuesta de Claude para lo que choca con cambios anteriores:
- Gráfica como en la maqueta; los controles de AK (Semana, Mes, Año…) quedan en un botón pequeño "Ajustar".
- Botones de "Próximos pagos" (pedidos en AJ) como texto verde discreto, igual que el "Pagar" de la maqueta.
- **Decisión del usuario:** "Sí, igual todo a la maqueta". Aplicado en 2.3.1:
  - Títulos chicos, grises y en mayúsculas en el Resumen; tarjetas sin borde y más redondeadas.
  - Tendencia simple de 6 meses (mes elegido en rojo, los demás en gris) con "Ajustar" para abrir la gráfica completa y "Listo" para volver.
  - "Pagar" y las acciones de "Próximos pagos" como texto verde; en "Próximos pagos" la acción va debajo del monto.
  - Barra de abajo con casa, lista, cartera y engrane; la pestaña activa en el color del tema; + redondo.
  - Encabezado "Hola, nombre" + título de la pantalla, y el mes en una pastilla ("Noviembre 2026 ⌄"). Las flechas ‹ › se ocultaron porque la maqueta no las tiene (se pueden regresar).
  - El botón "Pendientes" del encabezado ya no aparece en el Resumen (está en "Necesita tu atención"); sigue en las demás pantallas.
  - Apartado en azul fijo, como en la maqueta.

---

## 17. Cambios anotados el 2026-11-03 — ✅ aplicados en la versión 2.4.0

### AQ. Llevar el estilo del Resumen a las demás pantallas
Pedido del usuario: aplicar los mismos conceptos del Resumen a las demás opciones, con una maqueta de cada una, y rediseñar Movimientos (la parte de arriba tiene demasiadas cosas).
Maquetas (mismo lienzo que el Resumen): https://claude.ai/artifact/CvW4v86VpMUM9xhVash2go
Conceptos que se repiten en todas: encabezado "Hola, nombre" + título, etiquetas chicas grises en mayúsculas, tarjetas sin borde, la cifra más importante primero y en grande, verde lo que entra o queda y rojo lo gastado, acciones como texto verde y el detalle solo al tocar.
- [ ] **Movimientos:** arriba solo el buscador y un botón de filtros (con un numerito cuando hay filtros activos), y el selector Todos · Gastos · Ingresos. Los filtros activos aparecen como fichas que se quitan con ✕. Tarjeta con Gastos (rojo) e Ingresos (verde) del mes. La lista va por día, con el total del día, y cada movimiento con su icono de color, categoría y método, y fichas "Fijo" o del grupo.
- [ ] **Hoja de filtros** (se abre desde abajo): Ordenar (Más recientes / Más grandes), Grupo, Categoría, Método de pago, Solo fijos, Limpiar filtros y **Exportar CSV** (sale de la pantalla principal).
- [ ] **Fijos:** selector Gastos fijos · Ingresos fijos; tarjeta "¿Cómo van mis fijos?" con lo pagado de lo que toca en el mes y Fijos vs. variables; lista por frecuencia con el estado en color (Pagado ✓ verde, Por pagar en ámbar, Vencido en rojo); "+ Nuevo fijo".
- [ ] **Por confirmar:** tarjeta con cuántos faltan y el botón "Confirmar los N como están"; lista separada en "Del correo y de Siri" y "De tus fijos", con icono del origen y "Confirmar" en texto verde debajo del monto; los vencidos en ámbar.
- [ ] **Apartados:** tarjeta "¿Cuánto tengo apartado?" con el total en azul (color de Apartado), el rendimiento en verde y la barra Ahorro / Inversión; tarjeta "Este mes" con la sugerencia y cuánto falta; "Dónde está" con cada lugar, su valor y su ganancia; Metas con barra. Sin selector de mes (los apartados no son por mes).
- [ ] **Ajustes:** tarjeta de la cuenta arriba (nombre, correo, Face ID), y la lista en tres secciones con icono de color: Tu dinero (Categorías, Grupos, Métodos, **Fijos**), Avisos y atajos (Notificaciones, Siri y correo) y App (Apariencia, **Seguridad**, Usuarios, Acerca de). "Cerrar sesión" en rojo al final.
- Propuestas de Claude dentro de la maqueta: entrar a Fijos también desde Ajustes, y separar "Seguridad" (Face ID y cierre de sesión) de "Cuenta".
- **Decisiones del usuario sobre las maquetas (2026-11-03):** Por confirmar, Apartados y Ajustes quedan aprobadas tal como están. Movimientos y Fijos se ajustan así (maqueta actualizada):
  - [ ] **Movimientos sin selector de mes:** se ven todos los movimientos, de cualquier mes, del más nuevo al más viejo.
    - Al abrir carga **los 10 últimos**. Abajo hay un botón discreto (texto verde) **"Mostrar más movimientos"** que carga 10 más.
    - Después de esa primera vez, al llegar al final de la lista se cargan **solos** los siguientes 10, sin tocar nada.
    - Mientras carga: tres renglones de muestra con un brillo que se mueve y un círculo girando con "Cargando más movimientos…". Los nuevos aparecen suavemente (subiendo y apareciendo). Sin saltos.
    - Cuando ya no hay más: palomita y **"Ya no hay más movimientos"** con la fecha del primer movimiento registrado.
    - Al cambiar de mes en la lista aparece un separador con el nombre del mes ("Octubre 2026").
    - Propuesta de Claude: la tarjeta de arriba muestra los Gastos e Ingresos de **este mes**, y la hoja de filtros gana un filtro **Fechas** (para buscar un periodo, ya que no hay selector de mes).
  - [ ] **Fijos sin selector de mes:** lista de todos los fijos agrupados por frecuencia (Mensual, Bimestral, Semanal…), cada uno con el estado de su siguiente pago: Pagado ✓ (verde), Por pagar (gris) o Pendiente (rojo, cuando ya pasó la fecha).
    - Arriba, "¿Cuánto se va en fijos?": cuánto suman al mes los gastos fijos y qué parte de los ingresos fijos es (los semanales y bimestrales se cuentan como su equivalente al mes).
    - Se quita "Fijos vs. variables" (era por mes).
  - [ ] **Detalle de un fijo (pantalla nueva):** al tocar un fijo se abre su historial: Pendiente (con "Pagar"), Próximos (Por pagar, con "Marcar pagado" en el siguiente) y Pagados (con la fecha real en que se pagó). Arriba el monto, cada cuánto, método, categoría y grupo, y cuánto se ha pagado en el año. "Editar" abre el formulario de siempre.

- **Aplicado en 2.4.0 (2026-11-03)**, copiando el diseño de las maquetas (medidas, colores, letras y acomodo), no solo el contenido, como pidió el usuario ("recuerda actualizar el diseño, no como la vez pasada"). Cada pantalla se revisó contra su maqueta en claro y oscuro antes de subir.
  - Encabezado: "Hola, nombre" + título; en las pantallas de detalle, "‹ Resumen / ‹ Fijos / ‹ Ajustes…" arriba del título. El selector de mes solo aparece en el Resumen.
  - El botón + solo aparece donde lo tiene la maqueta (Resumen, Movimientos y Apartados; en Apartados abre directo "Apartar").
  - Movimientos carga del servidor de 10 en 10 con todos los filtros (la búsqueda, el orden y el CSV usan todos los movimientos, no solo los cargados). Sin conexión usa lo guardado en el teléfono.
  - Fijos se puede abrir desde el Resumen ("Ver todos") y desde Ajustes → Fijos; el "‹" regresa a donde estabas.
  - Ajustes: nueva página "Seguridad" (contraseña, tiempo para cerrar sesión y Face ID); "Cuenta" queda con nombre, correo y moneda; "Administración" ahora se llama "Usuarios"; "Cerrar sesión" va al final de Ajustes.

---

## 18. Cambios anotados el 2026-11-03 — AS ✅ aplicado en la versión 2.5.0; AT por decidir

### AR. Privacidad entre usuarios (pregunta del usuario: "que nadie, ni siquiera yo, pueda ver los datos de cada usuario")
Revisión de Claude (2026-11-03):
- **Ya está:** todas las tablas tienen seguridad por fila (cada persona solo puede leer y cambiar lo suyo). Las funciones de la base que se saltan esa regla solo trabajan con la cuenta de quien las llama o solo las usa el servidor. Ser administrador en la app **no** da acceso a las finanzas de nadie: la función de usuarios solo ve correo, nombre y rol.
- **Lo que no se puede evitar con la configuración actual:** quien sea dueño del proyecto de Supabase (el panel, el SQL Editor y la llave de servicio) puede ver todos los datos, porque se guardan legibles en la base. Para que ni el dueño pueda verlos haría falta **cifrado de extremo a extremo** (cada usuario cifra sus datos en su teléfono con una clave que solo él sabe).
  - Costo de ese cifrado: el servidor ya no podría leer montos ni nombres, así que dejarían de funcionar o habría que rehacer los avisos con monto, los fijos que se crean solos, el aviso de topes, Siri y el correo de BBVA, la búsqueda y los totales del servidor. Si alguien olvida su clave de cifrado, **pierde sus datos** (nadie puede recuperarlos).
- Propuesta de Claude (por confirmar):
  - [ ] Quitar "Crear cuenta" del inicio de sesión y desactivar el registro abierto en Supabase (Authentication → Sign In / Providers → "Allow new users to sign up" apagado). Así solo entra quien el administrador invita.
  - [ ] Proteger el acceso del dueño: verificación en dos pasos en Supabase y en GitHub, y no compartir la llave de servicio.
  - [ ] Un aviso de privacidad corto para los usuarios invitados, que diga quién administra el sistema.
  - [ ] (Opcional, proyecto grande) cifrado de extremo a extremo, con los costos de arriba.

### AS. "Agregar como app" desde el inicio de sesión
Pedido del usuario: un botón pequeño en el inicio de sesión que lleve a una pantalla con los pasos para agregar la app en el iPhone, con el mismo diseño de la app. Maqueta: https://claude.ai/artifact/CvW4v86VpMUM9xhVash2go (fila "Agregar como app").
- [ ] **Inicio de sesión:** debajo de la tarjeta, un renglón discreto "Agregar como app en tu iPhone · Pantalla completa, avisos y Face ID ›". Solo aparece si la app **no** está abierta ya desde el icono.
- [ ] **Pantalla "Agregar como app":** tarjeta con el icono y para qué sirve; selector **iPhone · Android**; en iPhone 4 pasos con dibujos (1. Abrir en Safari, con "Copiar enlace"; 2. Botón Compartir; 3. "Agregar a inicio"; 4. "Agregar"); al final "¡Listo! Ábrela desde el icono" y el botón "Entendido". En Android, los pasos de Chrome (⋮ → Instalar app).
- [ ] La app elige sola la pestaña iPhone o Android según el teléfono, y si se abrió fuera de Safari en el iPhone, resalta el paso 1.
- [ ] (Propuesta) También en Ajustes → Acerca de, "Agregar como app", si se abrió desde el navegador.
- En la maqueta se quitó "Crear cuenta" (depende de la decisión en AR).
- **Decisiones del usuario (2026-11-03):**
  - El registro se queda **abierto para cualquiera** ("Crear cuenta" se queda en el inicio de sesión). Se descarta cerrar el registro de AR.
  - Pasos de iPhone corregidos para iOS 26: en Safari se toca **«⋯» → «Compartir»** (en iOS anterior, el botón Compartir directo), luego **«Agregar a inicio»** (o «Ver más») y se deja **activado «Abrir como app web»** antes de tocar «Agregar». Maqueta actualizada.
  - El usuario quiere **privacidad total** (que ni el dueño pueda ver los datos). Pendiente: que confirme si se hace el cifrado de extremo a extremo (ver AT).

### AT. Cifrado de extremo a extremo (propuesta, por confirmar)
Cómo funcionaría:
- Cada usuario tiene una **llave personal** que se crea en su teléfono y **nunca** se envía al servidor sin cifrar. Montos, notas, nombres de categorías, métodos, fijos, metas y lugares se cifran en el teléfono antes de guardarse; en Supabase solo queda texto ilegible. Ni el dueño desde el panel ni la llave de servicio pueden leerlo.
- La llave se protege con una **clave de cifrado** (o la contraseña) del usuario, y se puede abrir con **Face ID** en su teléfono.
- **Código de recuperación** (24 palabras) que el usuario guarda al crear la cuenta. Si olvida la clave y no tiene el código, sus datos se pierden; nadie puede recuperarlos.
- Lo que entra desde fuera (Siri, correo de BBVA, fijos que se crean solos) se cifra en el servidor con una llave **pública** del usuario: el servidor puede cerrar el candado pero no abrirlo.
- Cambios que trae: avisos sin montos ni nombres ("Tienes un pago por confirmar"); el aviso de topes lo calcula el teléfono al registrar; búsqueda y totales en el teléfono; al entrar por primera vez después del cambio se cifran los datos existentes.
- Límite honesto: quien publica el código de la app podría, en teoría, cambiarlo para robar llaves; la privacidad depende de confiar en el código que se publica (es igual en cualquier app con cifrado de extremo a extremo).

- **Aplicado en 2.5.0 (2026-11-03):** el usuario pidió "aplica todos los cambios". Se aplicó AS con el diseño de la maqueta:
  - Inicio de sesión sin borde (como las demás tarjetas) y debajo el renglón "Agregar como app en tu iPhone"; solo aparece si la app no está abierta desde el icono.
  - Guía "Agregar como app" con selector iPhone · Android (elige solo según el teléfono), los 4 pasos de iOS 26 con dibujos, "Copiar enlace" y "¡Listo!". Si en el iPhone se abrió en Chrome u otro navegador, el paso 1 se resalta y avisa.
  - También en Ajustes → Acerca de, si se abrió desde el navegador.
  - "Crear cuenta" se queda (registro abierto, decisión del usuario). El cifrado (AT) no se aplicó: el usuario preguntó cómo lograrlo sin código de recuperación, como WhatsApp.
- **AT, opción "como WhatsApp" (propuesta de Claude, 2026-11-03):** guardar la llave de cifrado protegida con la **llave de acceso (Face ID)** del usuario, que el iPhone sincroniza en el Llavero de iCloud (también cifrado de extremo a extremo por Apple). Al cambiar de iPhone con la misma cuenta de Apple, la llave llega sola y los datos se abren con Face ID, sin guardar ningún código. Opcional: una contraseña de respaldo solo para quien la quiera. Si alguien pierde el acceso a su cuenta de Apple y no puso respaldo, sus datos se pierden.
