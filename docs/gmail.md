# Registro automático desde Gmail (BBVA)

Un pequeño programa en **tu propia cuenta de Google** revisa cada 5 minutos los correos de BBVA (retiros, compras, cargos, depósitos) y los manda a la app como **pendientes por confirmar**. Los retiros de cajero llegan como **Retiro**. Nadie más ve tus correos: el programa corre en tu cuenta y solo manda los datos del movimiento.

## 1. Genera un token (una sola vez)

App → **Ajustes → Siri y correo → Generar token** → nombre "Gmail" → **Copiar**. Puedes usar uno distinto al de Siri; así puedes revocar cada uno por separado.

## 2. Instala el programa (desde una computadora)

1. Entra a <https://script.google.com> con la cuenta de Gmail donde te llegan los correos de BBVA.
2. **Nuevo proyecto**. Arriba, cambia el nombre a `Mis finanzas Gmail`.
3. Borra todo lo que hay en el editor y pega el contenido de [`scripts/gmail-bbva.gs`](../scripts/gmail-bbva.gs).
4. En la línea `const TOKEN = "PEGA_AQUI_TU_TOKEN";` reemplaza `PEGA_AQUI_TU_TOKEN` por tu token (deja las comillas).
5. Guarda (ícono de disco).
6. Arriba, en la lista de funciones, elige **instalar** y toca **Ejecutar**.
7. Google pedirá permisos:
   - **Revisar permisos** → elige tu cuenta.
   - Si dice "Google no verificó esta app": **Configuración avanzada** → **Ir a Mis finanzas Gmail (no seguro)**. Es seguro: el programa es tuyo y solo tú lo usas.
   - **Permitir**.
8. Listo. En el registro de ejecución verás cada correo revisado y lo que respondió la app.

## 3. Cómo funciona

- Busca correos de BBVA de los últimos 3 días que aún no tengan la etiqueta **finanzas-registrado**, y se la pone al terminar.
- Cada correo se manda una sola vez; si el programa lo vuelve a mandar, la app lo ignora.
- La cuenta del correo (por ejemplo `**9607`) se usa para elegir el método de pago: si en la app tienes un método llamado, por ejemplo, `BBVA Débito 9607`, se elegirá solo.
- Los correos que no son movimientos (promociones, avisos) se ignoran.
- Si en 3 horas no confirmas los pendientes, te llega una notificación.

**Para detenerlo:** en script.google.com → tu proyecto → **Activadores** (ícono de reloj) → borra el activador. O revoca el token en la app.
