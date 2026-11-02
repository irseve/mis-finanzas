-- Mis finanzas · Migración 007
-- El nombre de la bienvenida ("Hola Irving") se guarda en los datos de la cuenta (user_metadata.full_name).
--
-- Cómo aplicarla: Supabase → SQL Editor → pega todo este archivo → Run.
-- Se puede correr más de una vez sin problema. No borra ni modifica tus movimientos.

-- Cuenta del dueño (el administrador más antiguo): nombre "Irving", solo si aún no tiene uno.
update auth.users u
set raw_user_meta_data = coalesce(u.raw_user_meta_data, '{}'::jsonb) || '{"full_name":"Irving"}'::jsonb
where u.id = (select p.user_id from public.profiles p join auth.users a on a.id = p.user_id where p.role = 'admin' order by a.created_at limit 1)
  and coalesce(u.raw_user_meta_data ->> 'full_name', '') = '';

-- Los demás usuarios: si escribieron su nombre en la app (versión 2.1), se pasa a su cuenta.
update auth.users u
set raw_user_meta_data = coalesce(u.raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('full_name', s.display_name)
from public.settings s
where s.user_id = u.id and s.display_name <> '' and coalesce(u.raw_user_meta_data ->> 'full_name', '') = '';
