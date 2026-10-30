// Mis finanzas · función "precios"
// Precios de instrumentos (ETF, acciones, fondos) con los datos públicos de Yahoo Finanzas. Son aproximados.
//   {"action":"search","q":"VOO"}                      → instrumentos que coinciden (usuario con sesión)
//   {"action":"add","symbol":"VOO"}                    → guarda el instrumento y su precio de hoy (usuario con sesión)
//   {"action":"price-at","symbol":"VOO","date":"…"}    → precio de cierre de ese día y tipo de cambio a pesos
//   {"action":"update"} + cabecera x-cron-secret       → actualiza todos los precios (lo llama pg_cron)
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
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { ...CORS, "Content-Type": "application/json" } });

// <yahoo>
const UA = { "User-Agent": "Mozilla/5.0 (mis-finanzas)" };
const TYPES = new Set(["ETF", "EQUITY", "MUTUALFUND", "INDEX", "CRYPTOCURRENCY"]);
// Clave del tipo de cambio a pesos en Yahoo: dólar = MXN=X, euro = EURMXN=X…
export const fxSymbol = (currency: string) => currency === "USD" ? "MXN=X" : `${currency}MXN=X`;

export async function yahooSearch(q: string) {
  const r = await fetch(`https://query2.finance.yahoo.com/v1/finance/search?q=${encodeURIComponent(q)}&quotesCount=10&newsCount=0`, { headers: UA });
  if (!r.ok) throw new Error("Yahoo search " + r.status);
  const d = await r.json();
  return (d.quotes ?? []).filter((x: any) => TYPES.has(x.quoteType) && x.symbol)
    .map((x: any) => ({ symbol: x.symbol, name: x.longname || x.shortname || x.symbol, exchange: x.exchDisp || x.exchange || "", type: x.typeDisp || x.quoteType }));
}
// Último precio, o el cierre de un día concreto (date = "YYYY-MM-DD").
export async function yahooPrice(symbol: string, date?: string) {
  let url = `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(symbol)}?interval=1d&range=5d`;
  if (date) {
    const t = Math.floor(Date.parse(date + "T00:00:00Z") / 1000);
    url = `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(symbol)}?interval=1d&period1=${t - 7 * 86400}&period2=${t + 86400}`;
  }
  const r = await fetch(url, { headers: UA });
  if (!r.ok) throw new Error(`Yahoo ${symbol} ${r.status}`);
  const res = (await r.json()).chart?.result?.[0];
  if (!res) throw new Error(`Sin datos para ${symbol}`);
  const m = res.meta;
  let price = m.regularMarketPrice, at = (m.regularMarketTime ?? Date.now() / 1000) * 1000;
  if (date) { // último cierre en o antes de ese día (fines de semana y feriados toman el día hábil anterior)
    const ts: number[] = res.timestamp ?? [], close: (number | null)[] = res.indicators?.quote?.[0]?.close ?? [];
    for (let i = ts.length - 1; i >= 0; i--) if (close[i] != null && new Date(ts[i] * 1000).toISOString().slice(0, 10) <= date) { price = close[i]; at = ts[i] * 1000; break; }
  }
  return { symbol: m.symbol as string, name: (m.longName || m.shortName || m.symbol) as string, currency: (m.currency || "USD") as string, exchange: (m.fullExchangeName || m.exchangeName || "") as string, price: price as number, at: new Date(at).toISOString() };
}
// </yahoo>

async function save(p: Awaited<ReturnType<typeof yahooPrice>>) {
  await db.from("instruments").upsert({ symbol: p.symbol, name: p.name, currency: p.currency, exchange: p.exchange, price: p.price, price_at: p.at }, { onConflict: "symbol" });
}
async function addWithFx(symbol: string) {
  const p = await yahooPrice(symbol);
  if (p.currency !== "MXN") await save(await yahooPrice(fxSymbol(p.currency)));
  await save(p);
  return p;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const body = await req.json().catch(() => ({}));
    if (body.action === "update") {
      const { data: secret } = await db.from("app_secrets").select("value").eq("name", "cron_secret").maybeSingle();
      if (!secret?.value || req.headers.get("x-cron-secret") !== secret.value) return json({ error: "No autorizado" }, 401);
      const { data: rows } = await db.from("instruments").select("symbol");
      let ok = 0; const failed: string[] = [];
      for (const r of rows ?? []) { try { await save(await yahooPrice(r.symbol)); ok++; } catch (e) { failed.push(r.symbol); console.error(String(e)); } }
      return json({ updated: ok, failed });
    }
    // Lo demás requiere una sesión válida de la app.
    const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: who } = await db.auth.getUser(jwt);
    if (!who?.user) return json({ error: "Inicia sesión de nuevo" }, 401);
    const symbol = String(body.symbol ?? "").trim().toUpperCase().slice(0, 30);
    switch (body.action) {
      case "search": {
        const q = String(body.q ?? "").trim().slice(0, 40);
        return json({ results: q ? await yahooSearch(q) : [] });
      }
      case "add":
        if (!symbol) return json({ error: "Falta el instrumento" }, 400);
        return json({ instrument: await addWithFx(symbol) });
      case "price-at": {
        if (!symbol || !/^\d{4}-\d{2}-\d{2}$/.test(String(body.date))) return json({ error: "Datos incompletos" }, 400);
        const p = await yahooPrice(symbol, body.date);
        const fx = p.currency === "MXN" ? 1 : (await yahooPrice(fxSymbol(p.currency), body.date)).price;
        return json({ price: p.price, currency: p.currency, fx, priceMxn: p.price * fx, at: p.at });
      }
      default:
        return json({ error: "Acción no válida" }, 400);
    }
  } catch (e) {
    console.error(e);
    return json({ error: String((e as Error).message ?? e) }, 500);
  }
});
