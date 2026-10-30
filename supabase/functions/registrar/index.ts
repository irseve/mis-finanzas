// Mis finanzas · función "registrar"
// Crea un PENDIENTE por confirmar en la app (nunca un movimiento directo).
//   POST ?origen=siri   {monto, concepto, metodo?, categoria?}         → responde un texto corto para que Siri lo diga
//   POST ?origen=gmail  {message_id, subject, from, date, html, text}  → lee el correo del banco (BBVA)
// Autorización: "Authorization: Bearer <token personal>" generado en Ajustes → Siri y correo.
import { createClient } from "npm:@supabase/supabase-js@2.117.3";

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
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const text = (msg: string, status = 200) => new Response(msg, { status, headers: { ...CORS, "Content-Type": "text/plain; charset=utf-8" } });
const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { ...CORS, "Content-Type": "application/json" } });

// ---------- lectura de correos BBVA (también se prueba fuera de Deno) ----------
// <parser>
const norm = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim();
const decode = (s: string) => s.replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&#36;|&dollar;/g, "$").replace(/&quot;/g, '"').replace(/&#39;/g, "'")
  .replace(/&aacute;/g, "á").replace(/&eacute;/g, "é").replace(/&iacute;/g, "í").replace(/&oacute;/g, "ó").replace(/&uacute;/g, "ú").replace(/&ntilde;/g, "ñ")
  .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(+n));
// Convierte el HTML del correo en una lista de textos (una celda o párrafo por elemento).
function tokens(html: string, plain: string): string[] {
  const src = html
    ? decode(html.replace(/<(script|style|head)[\s\S]*?<\/\1>/gi, " ").replace(/<br\s*\/?>/gi, "\n").replace(/<\/(p|div|td|th|tr|li|h\d|table|span)>/gi, "\n").replace(/<[^>]+>/g, " "))
    : plain;
  return src.split(/\n|\t/).map((x) => x.replace(/\s+/g, " ").trim()).filter(Boolean);
}
const AMOUNT = /\$\s?([\d,]+(?:\.\d{1,2})?)/;
const toAmount = (s: string) => { const m = s.match(AMOUNT) || s.match(/([\d,]+\.\d{2})/); return m ? Math.round(parseFloat(m[1].replace(/,/g, "")) * 100) / 100 : NaN; };
function toDate(s: string): string | null {
  let m = s.match(/(\d{4})-(\d{2})-(\d{2})/); if (m) return `${m[1]}-${m[2]}-${m[3]}`;
  m = s.match(/(\d{1,2})\/(\d{1,2})\/(\d{4})/); if (m) return `${m[3]}-${m[2].padStart(2, "0")}-${m[1].padStart(2, "0")}`;
  return null;
}
export function parseBank(email: { subject?: string; html?: string; text?: string; date?: string }) {
  const toks = tokens(email.html ?? "", email.text ?? "");
  const all = norm([email.subject ?? "", ...toks].join(" "));
  // Etiqueta → valor. Sirve tanto si el valor va debajo de su etiqueta como si las etiquetas de una fila van primero.
  const fields: Record<string, string> = {};
  const queue: string[] = [];
  let started = false;
  for (const t of toks) {
    if (/detalle/i.test(t)) { started = true; continue; }
    if (!started) continue;
    if (/:$/.test(t)) { queue.push(norm(t.slice(0, -1))); continue; }
    const k = queue.shift();
    if (k && !(k in fields)) fields[k] = t;
  }
  const pick = (...keys: string[]) => { for (const k of Object.keys(fields)) if (keys.some((x) => k.includes(x))) return fields[k]; return ""; };
  const type = /retiro de efectivo|retiro en cajero/.test(all) ? "retiro"
    : /(deposito|abono|recibiste|te enviaron|transferencia recibida)/.test(all) ? "ingreso"
    : /(compra|cargo|pago con tu tarjeta|pagaste|domiciliacion|transferencia enviada|enviaste)/.test(all) ? "gasto" : null;
  let amount = toAmount(pick("importe", "monto", "cantidad", "total"));
  if (!(amount > 0)) amount = toAmount(toks.join(" "));
  const date = toDate(pick("fecha")) ?? toDate(toks.join(" ")) ?? (email.date ? email.date.slice(0, 10) : null);
  const account = (pick("cuenta", "tarjeta").match(/(\d{4})\s*$/) || toks.join(" ").match(/\*+\s?(\d{4})/) || [])[1] ?? "";
  const place = pick("ubicacion", "comercio", "establecimiento", "negocio", "beneficiario", "concepto");
  if (!type || !(amount > 0)) return null;
  const note = type === "retiro" ? `Retiro de efectivo${place ? " · " + place : ""}` : place || (type === "ingreso" ? "Depósito BBVA" : "Cargo BBVA");
  return { type, amount, date, account, note: note.slice(0, 120), time: pick("hora"), folio: pick("folio") };
}
// </parser>

// ---------- utilidades ----------
const sha256 = async (s: string) => [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)))].map((b) => b.toString(16).padStart(2, "0")).join("");
const mxToday = () => new Intl.DateTimeFormat("en-CA", { timeZone: "America/Mexico_City" }).format(new Date());
const money = (n: number) => new Intl.NumberFormat("es-MX", { style: "currency", currency: "MXN" }).format(n);

// Adivina la categoría: por nombre de categoría y, si no, por movimientos anteriores con una nota parecida.
async function guessCategory(userId: string, concept: string, kind: string, hint?: string) {
  const { data: cats } = await db.from("categories").select("id,name,kind").eq("user_id", userId).eq("kind", kind);
  if (!cats?.length) return null;
  const words = norm(`${hint ?? ""} ${concept}`).split(/\W+/).filter((w) => w.length > 2);
  const byName = cats.find((c) => words.some((w) => norm(c.name).includes(w) || w.includes(norm(c.name))));
  if (byName) return byName.id;
  const { data: past } = await db.from("transactions").select("category_id,note").eq("user_id", userId).eq("type", kind).not("category_id", "is", null).order("date", { ascending: false }).limit(400);
  const votes = new Map<string, number>();
  for (const t of past ?? []) if (words.some((w) => norm(t.note ?? "").includes(w))) votes.set(t.category_id, (votes.get(t.category_id) ?? 0) + 1);
  const best = [...votes.entries()].sort((a, b) => b[1] - a[1])[0];
  return best?.[0] ?? cats.find((c) => /^otros/i.test(c.name))?.id ?? null;
}
async function guessMethod(userId: string, hint: string) {
  if (!hint) return null;
  const { data } = await db.from("payment_methods").select("id,name").eq("user_id", userId).eq("active", true);
  const h = norm(hint);
  return data?.find((m) => norm(m.name).includes(h) || h.includes(norm(m.name)))?.id ?? null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const origen = new URL(req.url).searchParams.get("origen") ?? "siri";
  try {
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
    if (!token.startsWith("mf_")) return text("Falta tu token personal. Créalo en la app, en Ajustes.", 401);
    const { data: tk } = await db.from("api_tokens").select("id,user_id,revoked").eq("token_hash", await sha256(token)).maybeSingle();
    if (!tk || tk.revoked) return text("Ese token no es válido o fue revocado. Genera uno nuevo en la app.", 401);
    await db.from("api_tokens").update({ last_used_at: new Date().toISOString() }).eq("id", tk.id);
    const body = await req.json().catch(() => ({}));

    if (origen === "gmail") {
      const p = parseBank(body);
      if (!p) return json({ ok: false, reason: "Correo no reconocido como movimiento" });
      const methodId = p.account ? await guessMethod(tk.user_id, p.account) : null;
      const categoryId = p.type === "retiro" ? null : await guessCategory(tk.user_id, p.note, p.type);
      const { error } = await db.from("pending_entries").upsert({
        user_id: tk.user_id, source: "gmail", type: p.type, amount: p.amount, category_id: categoryId, payment_method_id: methodId,
        date: p.date ?? mxToday(), note: p.note, external_id: "gmail:" + String(body.message_id ?? ""), status: "pendiente",
        raw: { subject: body.subject ?? "", from: body.from ?? "", account: p.account, time: p.time, folio: p.folio },
      }, { onConflict: "user_id,external_id", ignoreDuplicates: true });
      if (error) throw error;
      return json({ ok: true, type: p.type, amount: p.amount });
    }

    // Siri
    const amount = Math.round(parseFloat(String(body.monto ?? "").replace(/[^\d.,]/g, "").replace(/,(\d{1,2})$/, ".$1").replace(/,/g, "")) * 100) / 100;
    const concept = String(body.concepto ?? "").trim().slice(0, 120);
    if (!(amount > 0)) return text("No entendí el monto. Intenta de nuevo, por ejemplo: 250.");
    const categoryId = await guessCategory(tk.user_id, concept, "gasto", body.categoria);
    const methodId = await guessMethod(tk.user_id, String(body.metodo ?? ""));
    const { error } = await db.from("pending_entries").insert({
      user_id: tk.user_id, source: "siri", type: "gasto", amount, category_id: categoryId, payment_method_id: methodId,
      date: mxToday(), note: concept, raw: body,
    });
    if (error) throw error;
    return text(`Listo, guardé ${money(amount)}${concept ? " de " + concept : ""} para confirmar en la app.`);
  } catch (e) {
    console.error(e);
    return origen === "gmail" ? json({ error: String((e as Error).message ?? e) }, 500) : text("Algo falló al guardar. Intenta de nuevo en un momento.", 500);
  }
});
