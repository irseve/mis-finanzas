// Mis finanzas · Registro automático desde Gmail (BBVA)
// Pega este archivo en https://script.google.com con tu cuenta de Gmail (ver docs/gmail.md).
// Cada 5 minutos busca correos nuevos de BBVA, los manda a tu app como "pendientes por confirmar"
// y les pone la etiqueta "finanzas-registrado" para no mandarlos dos veces.

const TOKEN = "PEGA_AQUI_TU_TOKEN"; // Ajustes → Siri y correo → Generar token
const URL_FUNCION = "https://luruzajftjpqrzhgmtwj.supabase.co/functions/v1/registrar?origen=gmail";
const BUSQUEDA = "from:bbva newer_than:3d -label:finanzas-registrado";
const ETIQUETA = "finanzas-registrado";

function revisarCorreos() {
  if (TOKEN.indexOf("mf_") !== 0) throw new Error("Primero pega tu token en la línea TOKEN.");
  const etiqueta = GmailApp.getUserLabelByName(ETIQUETA) || GmailApp.createLabel(ETIQUETA);
  const hilos = GmailApp.search(BUSQUEDA, 0, 30);
  for (const hilo of hilos) {
    for (const m of hilo.getMessages()) {
      const r = UrlFetchApp.fetch(URL_FUNCION, {
        method: "post",
        contentType: "application/json",
        headers: { Authorization: "Bearer " + TOKEN },
        payload: JSON.stringify({
          message_id: m.getId(), subject: m.getSubject(), from: m.getFrom(),
          date: m.getDate().toISOString(), html: m.getBody(), text: m.getPlainBody(),
        }),
        muteHttpExceptions: true,
      });
      const code = r.getResponseCode();
      if (code === 401) throw new Error("El token no es válido o fue revocado. Genera uno nuevo en la app.");
      if (code >= 500) { console.log("Error del servidor, se reintenta en 5 minutos: " + r.getContentText()); return; }
      console.log(m.getSubject() + " → " + r.getContentText());
    }
    hilo.addLabel(etiqueta);
  }
}

// Corre esta función UNA vez: programa la revisión cada 5 minutos y revisa de inmediato.
function instalar() {
  ScriptApp.getProjectTriggers().forEach(function (t) { ScriptApp.deleteTrigger(t); });
  ScriptApp.newTrigger("revisarCorreos").timeBased().everyMinutes(5).create();
  revisarCorreos();
}
