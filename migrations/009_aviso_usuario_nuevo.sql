-- Mis finanzas · Migración 009
-- Aviso a los administradores cada vez que alguien crea una cuenta ("Nuevo usuario: …").
-- Solo se avisa el nombre o el correo; nunca nada de sus finanzas.
--
-- Cómo aplicarla: Supabase → SQL Editor → pega todo este archivo → Run.
-- Se puede correr más de una vez sin problema. No borra ni modifica tus datos.

alter table public.scheduled_notifications drop constraint if exists scheduled_notifications_kind_check;
alter table public.scheduled_notifications add constraint scheduled_notifications_kind_check
  check (kind in ('pendientes','recurrente','ingreso','recordatorio','meta','prueba','resumen','mensaje','tope','usuario')) not valid;

-- Al crearse una cuenta: su perfil (como antes) y un aviso para cada administrador.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare who text := coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), new.email, 'Sin correo');
begin
  insert into public.profiles (user_id, display_name) values (new.id, split_part(coalesce(new.email, ''), '@', 1))
  on conflict (user_id) do nothing;
  insert into public.scheduled_notifications (user_id, kind, title, body, url, dedupe)
  select p.user_id, 'usuario', 'Nuevo usuario: ' || who,
    coalesce(new.email, '') || ' · se registró el ' || to_char(now() at time zone 'America/Mexico_City', 'DD/MM "a las" HH24:MI') || '. Toca para ver la lista.',
    './?tab=usuarios', 'usuario:' || new.id
  from public.profiles p where p.role = 'admin' and p.user_id <> new.id
  on conflict (user_id, dedupe) do nothing;
  return new;
end $$;
revoke all on function public.handle_new_user() from public, anon, authenticated;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();
