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

## 8. Cambios anotados el 2026-10-30 (sin implementar todavía)

Solo anotados; **no ejecutar** hasta que el usuario lo indique.

### F. Selector de mes en cuadrícula
Hoy el encabezado muestra el mes actual ("Octubre de 2026") con flechas ‹ › a los lados para ir mes por mes.
- [ ] Las flechas ‹ › se quedan como están.
- [ ] Al **tocar el nombre del mes** (la parte de en medio) se despliega hacia abajo una ventana pequeña.
- [ ] Arriba de esa ventana va el **año** (por defecto el año en curso, por ejemplo 2026) con flechas para ir al **año anterior y al siguiente**.
- [ ] Debajo, los **12 meses en cuadrícula** (por ejemplo 3 columnas × 4 filas o 4 × 3), no en lista, para saltar fácil de un mes a otro (de octubre a enero, por ejemplo).
- [ ] Al tocar un mes se cierra la ventana y la app muestra ese mes. Resaltar el mes seleccionado y marcar de forma distinta el mes actual.
- [ ] Se cierra también al tocar fuera de la ventana. Zonas de toque de al menos 44 px; debe verse bien en los 5 temas, claro y oscuro.

### G. Una sola gráfica de gastos con periodo a elegir
Hoy hay dos gráficas en Resumen:
- **Gastos por semana:** solo gastos, semana por semana del mes que estás viendo.
- **Últimos 6 meses:** ingresos contra gastos, mes por mes.

El usuario propone unificarlas en una sola.
- [ ] Una sola tarjeta de gráfica en Resumen, con un selector arriba: **Semana · Mes · Año**.
  - **Semana:** las semanas del mes seleccionado (como la gráfica actual).
  - **Mes:** los últimos 6 o 12 meses (por definir), uno por barra.
  - **Año:** un año por barra, con los años que tengan registros.
- [ ] Recordar en el dispositivo el último periodo elegido.
- [ ] Al quitar la gráfica de 6 meses, la de categorías y "Fijos vs. variables" se acomodan para no dejar huecos.
- [ ] Segundo selector **Mostrar: Gastos · Ingresos · Ambos** (rojo para gastos, verde para ingresos), disponible en Semana, Mes y Año.
- [ ] El usuario **elige el periodo de tiempo** que abarca la gráfica (desde – hasta). Sugerencia: atajos rápidos (este mes, últimos 3, 6 o 12 meses, este año, todo) y la opción de elegir fechas, usando el mismo selector de mes en cuadrícula del punto F. Con esto se resuelve cuántos meses mostrar.
- [ ] Recordar en el dispositivo la última combinación elegida (agrupación, qué mostrar y periodo).
- Nota técnica: hoy la app carga 6 meses de movimientos; para periodos más largos hay que cargar el rango elegido o pedir totales agrupados al servidor.
