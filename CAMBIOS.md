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

## 9. Cambios anotados el 2026-10-31 (sin implementar todavía)

Solo anotados; **no ejecutar** hasta que el usuario lo indique.

### N. Que la app no se vea vacía ni "se trabe" sin internet o con mala señal
Problema: al abrir la app con mala conexión se veía sin nada, sin explicar qué pasaba.
- [ ] **Mientras carga:** mensaje sencillo y visible, por ejemplo "Conectando con tus datos…" con un indicador de carga, en lugar de la pantalla vacía.
- [ ] **Si tarda o falla** (por ejemplo, más de 10 segundos o un error de red): "No hay conexión a internet" o "No se pudo conectar con tus datos", con un botón **Reintentar**.
- [ ] **Reintento automático** cuando el teléfono recupere la conexión, y cada cierto tiempo mientras siga sin conexión, sin que el usuario tenga que cerrar la app.
- [ ] **Mostrar lo último que se cargó:** guardar en el dispositivo la última información descargada y mostrarla sin conexión, con un aviso arriba como "Sin conexión · mostrando datos del 31/10 a las 10:15". En ese modo, avisar que los cambios no se pueden guardar hasta tener conexión.
- [ ] **Que la app abra aunque no haya internet:** hoy el service worker no guarda nada en caché, así que sin red el iPhone no puede ni cargar la página. Guardar la app (HTML, config.js y la librería de Supabase) para abrirla sin conexión: siempre se intenta primero la versión de internet (para no perder actualizaciones) y, si falla, se usa la guardada.
- [ ] Que ningún error de conexión deje botones sin responder o pantallas a medias: todo error muestra un mensaje claro y permite reintentar.
- Opcional, por confirmar: permitir **registrar movimientos sin conexión** y subirlos solos cuando regrese la señal.

### O. Aviso de nueva versión abajo
- [ ] El aviso "Hay una nueva versión · Actualizar" aparece **abajo** en lugar de arriba: justo encima de la barra de pestañas (sin tapar la barra ni el botón +), respetando el área segura del iPhone. En computadora, abajo al centro.

### P. Campo de monto con formato de dinero mientras se escribe
Aplica a todos los campos de monto (gasto, ingreso, retiro, apartados, confirmar pendientes, fijos, metas, saldo real).
- [ ] Mostrar el **signo de pesos** fijo al inicio del campo (`$`), sin que el usuario tenga que escribirlo.
- [ ] **Comas de miles automáticas** mientras se escribe: `1000` → `1,000`; `25000` → `25,000`; `1250000` → `1,250,000`. El cursor no debe brincar al reformatear.
- [ ] **Centavos:**
  - Si no se escriben, se ve `.00` en **tono claro** (como sugerencia) después del número: `$1,000` + `.00` gris.
  - Si se escribe el punto y nada más (`1000.`), se toma como `.00` (el `00` se sigue viendo claro).
  - Con un decimal (`1000.1`) se toma como `.10` (el `0` faltante en claro).
  - Con dos decimales (`1000.15`) se toma tal cual.
  - **Máximo dos decimales**: un tercer dígito después del punto no se acepta.
- [ ] Solo se aceptan números y un punto decimal; la coma la pone la app (si el teclado escribe coma como decimal, se convierte en punto).
- [ ] Teclado numérico con punto decimal en el iPhone.
- [ ] Al guardar se usa el valor numérico (por ejemplo `1000.1` → 1000.10).

### Q. Registrar un pago que corresponde a un fijo existente (pago atrasado o adelantado)
Caso: no se confirmó a tiempo un fijo (o se pagó antes o después de su fecha) y el usuario lo registra con el **+**.
- [ ] En el formulario del **+**, al marcar "Es fijo", primero preguntar: **"¿Es de un fijo que ya tienes?"** con la lista de fijos del mismo tipo (gasto o ingreso) y la opción "No, es un fijo nuevo" (el comportamiento actual).
- [ ] Al elegir un fijo existente:
  - Se llenan solos la categoría, el método y el monto sugerido (editable).
  - Elegir **a qué fecha programada corresponde** el pago: la app propone la fecha pendiente (sin pagar) más cercana a la fecha escrita y deja elegir otra de la lista (fechas vencidas sin pagar, la actual y la siguiente).
  - La fecha del movimiento es la que escribió el usuario (cuando realmente pagó).
- [ ] Si la fecha real es distinta a la programada, preguntar: **"Pagaste el 13/10 y estaba programado el 15/10. ¿Cambiar las próximas fechas?"**
  - **No, solo esta vez** (recomendado): el calendario del fijo no cambia; esa fecha programada queda como pagada.
  - **Sí, a partir de ahora:** el calendario se recorre según la frecuencia:
    - **Mensual:** las próximas fechas pasan al nuevo día del mes (por ejemplo, del 15 al 13).
    - **Semanal, quincenal (cada 15 días) y diario:** el ciclo vuelve a contar desde la nueva fecha.
    - **Quincena de salario (15 y último día del mes):** **no se puede cambiar**; siempre "solo esta vez". Solo se pregunta a qué quincena corresponde (la del 15 o la de fin de mes).
- [ ] Si esa fecha programada ya tenía un **pendiente por confirmar**, se marca como aceptado (no se duplica) y el monto queda como sugerencia para la próxima vez, igual que al confirmar desde Pendientes.
- [ ] Cuidar que no se registre dos veces la misma fecha programada: si ya está pagada, avisar y no permitir elegirla.
- Por confirmar: si un solo pago cubre **dos fechas atrasadas** (por ejemplo, dos quincenas), ¿registrarlo como dos movimientos o uno solo?

### R. Frecuencia bimestral
- [ ] Nueva frecuencia **Bimestral (cada 2 meses)** para fijos, junto a diario, semanal, quincenal y mensual. Se repite el mismo día cada dos meses desde la primera fecha (por ejemplo 10/ene, 10/mar, 10/may…). Si el día no existe en ese mes (31 en abril), se usa el último día del mes, igual que en mensual.
- [ ] Incluirla en el cálculo de próximos pagos, proyectado del mes, pendientes automáticos (servidor) y en el punto Q (recorrer el calendario).
- Requiere migración: agregar `bimestral` a la lista de frecuencias de `recurrences` y a `recurrence_on_or_after`.

### S. Subcategorías (opcionales)
Recomendación de Claude: **sí vale la pena**, con **un solo nivel** (categoría → subcategoría), para agrupar sin complicar el registro.
- [ ] Una categoría puede tener subcategorías. Ejemplos: **Casa** → Teléfono, Internet, Agua, Luz; **Escuela de mi hijo** → Colegiatura, Uniformes, Útiles, Transporte.
- [ ] Al registrar un gasto o ingreso: se elige la categoría y, **si tiene subcategorías**, aparece una segunda opción con sus subcategorías y **"Sin subcategoría"** (preseleccionada). Las categorías sin subcategorías funcionan como hoy.
- [ ] "+ Agregar subcategoría nueva" ahí mismo, igual que con las categorías.
- [ ] **Resumen → Por categoría:** se muestra el total de cada categoría (suma de sus subcategorías y de lo registrado sin subcategoría); al tocarla se despliega el desglose por subcategoría.
- [ ] Presupuesto por categoría (como hoy) y, opcional, por subcategoría.
- [ ] Filtros de Movimientos: por categoría (incluye sus subcategorías) o por una subcategoría concreta. El CSV incluye columna Subcategoría.
- [ ] **Ajustes → Categorías:** cada categoría muestra sus subcategorías; se pueden crear, editar, eliminar y **mover una categoría existente dentro de otra** (por ejemplo, convertir "Luz" en subcategoría de "Casa") sin perder sus movimientos.
- [ ] Al eliminar una categoría con subcategorías o movimientos: misma reasignación que hoy (elegir a dónde moverlos; nunca se borran).
- [ ] Fijos, pendientes de Siri/Gmail y la adivinanza de categoría también pueden usar subcategoría.
- Requiere migración: columna `categories.parent_id` (un solo nivel) y ajustes en la reasignación al eliminar.
