// Mis finanzas · función "passkeys": entrar con Face ID / Touch ID / huella (llaves de acceso).
//   {"action":"register-options"}            (con sesión)  → opciones para crear la llave en este teléfono
//   {"action":"register-verify","response"}  (con sesión)  → guarda la llave pública
//   {"action":"login-options"}               (sin sesión)  → reto para entrar
//   {"action":"login-verify","challengeId","response"}     → si la llave es válida, regresa un código de un solo uso
//                                                            con el que la app abre la sesión (verifyOtp)
// La llave privada nunca sale del teléfono; aquí solo se guarda la pública.
import { createClient } from "npm:@supabase/supabase-js@2.117.3";
import {
  generateAuthenticationOptions, generateRegistrationOptions, verifyAuthenticationResponse, verifyRegistrationResponse,
} from "npm:@simplewebauthn/server@13.3.3";
import { isoBase64URL, isoUint8Array } from "npm:@simplewebauthn/server@13.3.3/helpers";

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
const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { ...CORS, "Content-Type": "application/json" } });

// <core> (lógica sin Supabase, para poder probarla aparte)
// Sitios desde donde se permite usar las llaves: origen → dominio.
export const ORIGINS: Record<string, string> = { "https://irseve.github.io": "irseve.github.io" };
export type Store = {
  user(jwt: string): Promise<{ id: string; email: string } | null>;
  saveChallenge(userId: string | null, challenge: string, kind: "registro" | "acceso"): Promise<string>;
  takeChallenge(id: string, kind: string, userId?: string): Promise<string | null>; // lo borra al usarlo
  creds(userId: string): Promise<{ id: string; transports: string[] }[]>;
  cred(id: string): Promise<{ id: string; user_id: string; public_key: string; counter: number; transports: string[] } | null>;
  saveCred(row: { id: string; user_id: string; public_key: string; counter: number; transports: string[]; device: string }): Promise<void>;
  touchCred(id: string, counter: number): Promise<void>;
  loginToken(userId: string): Promise<string>;
};
export async function handle(body: any, jwt: string, origin: string, s: Store) {
  const rpID = ORIGINS[origin];
  if (!rpID) return { status: 403, data: { error: "Origen no permitido" } };
  switch (body.action) {
    case "register-options": {
      const u = await s.user(jwt); if (!u) return { status: 401, data: { error: "Inicia sesión de nuevo" } };
      const options = await generateRegistrationOptions({
        rpName: "Mis finanzas", rpID, userName: u.email, userDisplayName: u.email, userID: isoUint8Array.fromUTF8String(u.id),
        attestationType: "none",
        excludeCredentials: (await s.creds(u.id)).map((c) => ({ id: c.id, transports: c.transports as any })),
        authenticatorSelection: { residentKey: "required", userVerification: "required", authenticatorAttachment: "platform" },
      });
      const challengeId = await s.saveChallenge(u.id, options.challenge, "registro");
      return { status: 200, data: { options, challengeId } };
    }
    case "register-verify": {
      const u = await s.user(jwt); if (!u) return { status: 401, data: { error: "Inicia sesión de nuevo" } };
      const expectedChallenge = await s.takeChallenge(String(body.challengeId), "registro", u.id);
      if (!expectedChallenge) return { status: 400, data: { error: "El registro expiró; inténtalo de nuevo" } };
      const v = await verifyRegistrationResponse({ response: body.response, expectedChallenge, expectedOrigin: origin, expectedRPID: rpID, requireUserVerification: true });
      if (!v.verified || !v.registrationInfo) return { status: 400, data: { error: "No se pudo verificar la llave" } };
      const c = v.registrationInfo.credential;
      await s.saveCred({ id: c.id, user_id: u.id, public_key: isoBase64URL.fromBuffer(c.publicKey), counter: c.counter, transports: (c.transports ?? []) as string[], device: String(body.device ?? "").slice(0, 40) });
      return { status: 200, data: { ok: true } };
    }
    case "login-options": {
      const options = await generateAuthenticationOptions({ rpID, userVerification: "required", allowCredentials: [] });
      const challengeId = await s.saveChallenge(null, options.challenge, "acceso");
      return { status: 200, data: { options, challengeId } };
    }
    case "login-verify": {
      const expectedChallenge = await s.takeChallenge(String(body.challengeId), "acceso");
      if (!expectedChallenge) return { status: 400, data: { error: "El intento expiró; inténtalo de nuevo" } };
      const c = await s.cred(String(body.response?.id ?? ""));
      if (!c) return { status: 404, data: { error: "Este teléfono ya no está registrado. Entra con tu contraseña y vuelve a activar Face ID." } };
      const v = await verifyAuthenticationResponse({
        response: body.response, expectedChallenge, expectedOrigin: origin, expectedRPID: rpID, requireUserVerification: true,
        credential: { id: c.id, publicKey: isoBase64URL.toBuffer(c.public_key), counter: Number(c.counter), transports: c.transports as any },
      });
      if (!v.verified) return { status: 401, data: { error: "No se pudo verificar tu identidad" } };
      await s.touchCred(c.id, v.authenticationInfo.newCounter);
      return { status: 200, data: { token_hash: await s.loginToken(c.user_id) } };
    }
    default:
      return { status: 400, data: { error: "Acción no válida" } };
  }
}
// </core>

const store: Store = {
  async user(jwt) { if (!jwt) return null; const { data } = await db.auth.getUser(jwt); return data?.user ? { id: data.user.id, email: data.user.email ?? "" } : null; },
  async saveChallenge(user_id, challenge, kind) { const { data, error } = await db.from("webauthn_challenges").insert({ user_id, challenge, kind }).select("id").single(); if (error) throw error; return data.id; },
  async takeChallenge(id, kind, userId) {
    const { data } = await db.from("webauthn_challenges").delete().eq("id", id).eq("kind", kind).gte("created_at", new Date(Date.now() - 5 * 60e3).toISOString()).select("challenge,user_id").maybeSingle();
    if (!data || (userId && data.user_id !== userId)) return null;
    return data.challenge;
  },
  async creds(userId) { const { data } = await db.from("webauthn_credentials").select("id,transports").eq("user_id", userId); return data ?? []; },
  async cred(id) { const { data } = await db.from("webauthn_credentials").select("*").eq("id", id).maybeSingle(); return data; },
  async saveCred(row) { const { error } = await db.from("webauthn_credentials").upsert(row); if (error) throw error; },
  async touchCred(id, counter) { await db.from("webauthn_credentials").update({ counter, last_used_at: new Date().toISOString() }).eq("id", id); },
  async loginToken(userId) {
    // Código de un solo uso para abrir la sesión de ese usuario (no se envía ningún correo).
    const { data: u } = await db.auth.admin.getUserById(userId);
    const { data, error } = await db.auth.admin.generateLink({ type: "magiclink", email: u.user!.email! });
    if (error) throw error;
    return data.properties.hashed_token;
  },
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const body = await req.json().catch(() => ({}));
    const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const r = await handle(body, jwt, req.headers.get("Origin") ?? "", store);
    return json(r.data, r.status);
  } catch (e) {
    console.error(e);
    return json({ error: String((e as Error).message ?? e) }, 500);
  }
});
