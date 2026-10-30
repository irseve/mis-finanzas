// Mis finanzas · función "admin-usuarios" (solo administradores)
// Acciones: list, invite {email}, create {email, password}, set-role {user_id, role}.
// Usa la llave de servicio, que solo existe en el servidor. El rol admin NO da acceso a las finanzas de otros.
import { createClient } from "npm:@supabase/supabase-js@2.117.3";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const APP_URL = "https://irseve.github.io/mis-finanzas/";
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { ...CORS, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    // Quién llama: se verifica la sesión y que su perfil sea admin (del lado del servidor).
    const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: who } = await db.auth.getUser(jwt);
    if (!who?.user) return json({ error: "Inicia sesión de nuevo" }, 401);
    const { data: me } = await db.from("profiles").select("role").eq("user_id", who.user.id).maybeSingle();
    if (me?.role !== "admin") return json({ error: "Solo para administradores" }, 403);

    const body = await req.json().catch(() => ({}));
    switch (body.action) {
      case "list": {
        const { data, error } = await db.auth.admin.listUsers({ perPage: 200 });
        if (error) throw error;
        const { data: profiles } = await db.from("profiles").select("*");
        return json({ users: data.users.map((u) => {
          const p = profiles?.find((x) => x.user_id === u.id);
          return { id: u.id, email: u.email, name: p?.display_name ?? "", role: p?.role ?? "user", created_at: u.created_at, last_sign_in_at: u.last_sign_in_at, confirmed: !!u.email_confirmed_at };
        }) });
      }
      case "invite": {
        const email = String(body.email ?? "").trim().toLowerCase();
        if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: "Escribe un correo válido" }, 400);
        const { error } = await db.auth.admin.inviteUserByEmail(email, { redirectTo: APP_URL });
        if (error) return json({ error: error.message }, 400);
        return json({ ok: true });
      }
      case "create": {
        const email = String(body.email ?? "").trim().toLowerCase(), password = String(body.password ?? "");
        if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: "Escribe un correo válido" }, 400);
        if (password.length < 6) return json({ error: "La contraseña debe tener al menos 6 caracteres" }, 400);
        const { error } = await db.auth.admin.createUser({ email, password, email_confirm: true });
        if (error) return json({ error: error.message }, 400);
        return json({ ok: true });
      }
      case "set-role": {
        const role = body.role === "admin" ? "admin" : "user";
        if (role === "user") {
          const { count } = await db.from("profiles").select("user_id", { count: "exact", head: true }).eq("role", "admin");
          const { data: target } = await db.from("profiles").select("role").eq("user_id", body.user_id).maybeSingle();
          if (target?.role === "admin" && (count ?? 0) <= 1) return json({ error: "Debe quedar al menos un administrador" }, 400);
        }
        const { error } = await db.from("profiles").upsert({ user_id: body.user_id, role }, { onConflict: "user_id" });
        if (error) throw error;
        return json({ ok: true });
      }
      default:
        return json({ error: "Acción no válida" }, 400);
    }
  } catch (e) {
    console.error(e);
    return json({ error: String((e as Error).message ?? e) }, 500);
  }
});
