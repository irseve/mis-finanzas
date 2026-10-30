// Mis finanzas · función "notificaciones"
// - {"action":"public-key"}: regresa la llave pública para activar notificaciones en un dispositivo.
// - {"action":"send"} con cabecera x-cron-secret: envía los avisos programados que ya vencieron (la llama pg_cron).
// Las llaves VAPID se generan solas la primera vez y se guardan en public.app_secrets (solo el servidor las lee).
import { createClient } from "npm:@supabase/supabase-js@2.117.3";
import * as webpush from "jsr:@negrel/webpush@0.5.0";

// Llave de servicio: formato nuevo (sb_secret_…) si existe; si no, la clásica service_role.
function serviceKey(): string {
  try {
    const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
    const k = keys.default ?? Object.values(keys)[0];
    if (typeof k === "string" && k) return k;
  } catch { /* sin llaves nuevas */ }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
}
const db = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey(), { auth: { persistSession: false } });
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { ...CORS, "Content-Type": "application/json" } });

async function secret(name: string): Promise<string | null> {
  const { data } = await db.from("app_secrets").select("value").eq("name", name).maybeSingle();
  return data?.value ?? null;
}

let vapidCache: CryptoKeyPair | null = null;
async function vapidKeys(): Promise<CryptoKeyPair> {
  if (vapidCache) return vapidCache;
  let stored = await secret("vapid_keys");
  if (!stored) {
    const keys = await webpush.generateVapidKeys({ extractable: true });
    const exported = JSON.stringify(await webpush.exportVapidKeys(keys));
    await db.from("app_secrets").upsert({ name: "vapid_keys", value: exported }, { onConflict: "name", ignoreDuplicates: true });
    stored = await secret("vapid_keys"); // si dos llamadas compiten, ambas usan la que quedó guardada
  }
  vapidCache = await webpush.importVapidKeys(JSON.parse(stored!), { extractable: false });
  return vapidCache;
}

async function sendDue() {
  const { data: due, error } = await db.from("scheduled_notifications").select("*")
    .is("sent_at", null).lte("send_at", new Date().toISOString()).order("send_at").limit(200);
  if (error) throw error;
  if (!due?.length) return { sent: 0 };
  const users = [...new Set(due.map((n) => n.user_id))];
  const [{ data: subs }, { data: prefs }] = await Promise.all([
    db.from("push_subscriptions").select("*").in("user_id", users),
    db.from("settings").select("user_id, notify").in("user_id", users),
  ]);
  const server = await webpush.ApplicationServer.new({ contactInformation: "https://irseve.github.io/mis-finanzas/", vapidKeys: await vapidKeys() });
  const gone = new Set<string>();
  let sent = 0;
  for (const n of due) {
    const notify = prefs?.find((p) => p.user_id === n.user_id)?.notify ?? {};
    const allowed = n.kind === "prueba" || notify[n.kind] !== false; // todo activado salvo que el usuario lo apague
    if (allowed) {
      for (const s of subs ?? []) {
        if (s.user_id !== n.user_id || gone.has(s.id)) continue;
        try {
          await server.subscribe({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } })
            .pushTextMessage(JSON.stringify({ title: n.title, body: n.body, url: n.url, tag: n.kind + ":" + n.id }), { ttl: 86400 });
          sent++;
        } catch (e) {
          const status = (e as { response?: Response }).response?.status;
          if (status === 404 || status === 410) gone.add(s.id); // el dispositivo ya no existe
          else console.error("push", status, String(e));
        }
      }
    }
    await db.from("scheduled_notifications").update({ sent_at: new Date().toISOString() }).eq("id", n.id);
  }
  if (gone.size) await db.from("push_subscriptions").delete().in("id", [...gone]);
  return { sent, removed: gone.size };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const body = await req.json().catch(() => ({}));
    if (body.action === "public-key") return json({ publicKey: await webpush.exportApplicationServerKey(await vapidKeys()) });
    if (body.action === "send") {
      const expected = await secret("cron_secret");
      if (!expected || req.headers.get("x-cron-secret") !== expected) return json({ error: "No autorizado" }, 401);
      return json(await sendDue());
    }
    return json({ error: "Acción no válida" }, 400);
  } catch (e) {
    console.error(e);
    return json({ error: String((e as Error).message ?? e) }, 500);
  }
});
