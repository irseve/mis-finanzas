# Registrar gastos con Siri

Con este atajo dices **"Oye Siri, agrega un gasto"**, Siri te pregunta el monto y en qué fue, y el gasto aparece en la app como **pendiente por confirmar**. Nada se guarda como movimiento hasta que tú lo aceptas.

## 1. Genera tu token (una sola vez)

1. Abre la app → **Ajustes → Siri y correo → Generar token**.
2. Ponle de nombre "Siri" y toca **Generar**.
3. Toca **Copiar**. El token solo se muestra una vez; si lo pierdes, revócalo y genera otro.

## 2. Crea el atajo en el iPhone

Abre la app **Atajos** → **+** (arriba a la derecha) y agrega estas acciones en orden:

1. **Solicitar entrada**
   - Tipo: **Número**. Pregunta: `¿Cuánto gastaste?`
2. **Solicitar entrada**
   - Tipo: **Texto**. Pregunta: `¿En qué?`
3. *(Opcional)* **Elegir de la lista**
   - Escribe tus métodos de pago tal como están en la app, por ejemplo `Efectivo`, `BBVA Crédito`, `SPAY`.
4. **Obtener contenido de URL**
   - URL: `https://luruzajftjpqrzhgmtwj.supabase.co/functions/v1/registrar?origen=siri`
   - Toca **Mostrar más**:
     - Método: **POST**
     - Encabezados → **Agregar nuevo encabezado**: clave `Authorization`, texto `Bearer ` seguido de tu token (con un espacio después de *Bearer*).
     - Cuerpo de la solicitud: **JSON**. Agrega tres campos de tipo Texto:
       - `monto` → toca la variable **Entrada proporcionada** (la del paso 1).
       - `concepto` → **Entrada proporcionada** (la del paso 2; mantén presionado para elegir la correcta).
       - `metodo` → **Elemento elegido** (solo si hiciste el paso 3).
5. **Hablar texto** (o **Leer texto**) → elige la variable **Contenido de la URL**.

Arriba, cambia el nombre del atajo a **Agrega un gasto**. Esa es la frase para Siri.

## 3. Pruébalo

Di "Oye Siri, agrega un gasto", responde `250` y `gasolina`. Siri dirá algo como *"Listo, guardé $250.00 de gasolina para confirmar en la app."* Abre la app: verás el botón naranja **Pendientes**.

La categoría se adivina por la palabra que dices y por tus movimientos anteriores. Si no acierta, la cambias al confirmar.

**Problemas comunes**
- *"Falta tu token" o "token no válido"*: revisa que el encabezado diga exactamente `Bearer mf_…`, con un espacio.
- *"No entendí el monto"*: di solo el número, sin la palabra "pesos".
