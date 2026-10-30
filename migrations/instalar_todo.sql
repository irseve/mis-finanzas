-- Mis finanzas · TODO EN UNO: activa pg_cron y pg_net y aplica las migraciones 001, 002 y 003.
-- Pega este archivo completo en Supabase → SQL Editor → New query → Run.
-- Se puede correr más de una vez. No borra tus datos.
-- (Generado uniendo los archivos de migrations/; si cambian, se vuelve a generar.)

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Mis finanzas · Migración 001
-- Métodos de pago, retiros, fijos con frecuencias (incluye salario 15 y fin de mes),
-- bandeja de pendientes, reasignar categorías al eliminarlas y metas de ahorro.
--
-- Cómo aplicarla: Supabase → SQL Editor → pega todo este archivo → Run.
-- Se puede correr más de una vez sin problema. No borra ni modifica tus datos:
-- la tabla fixed_expenses se conserva tal cual y sus registros se copian a "recurrences".

-- ---------- Métodos de pago ----------
create table if not exists public.payment_methods (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  name text not null,
  kind text not null default 'otro' check (kind in ('credito','debito','transferencia','spay','efectivo','otro')),
  color text not null default '#5E6E67',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------- Metas de ahorro ----------
create table if not exists public.goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  name text not null,
  target_amount numeric(12,2) not null default 0 check (target_amount >= 0),
  target_date date,
  color text not null default '#2F5D9E',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------- Fijos (gastos e ingresos que se repiten) ----------
-- freq: diario | semanal | quincenal (cada 15 días desde start_date) | mensual (día "day" de cada mes)
--       | salario (día 15 y último día de cada mes)
-- mode: confirmar (genera un pendiente por confirmar) | recordatorio (pago manual, solo avisa)
create table if not exists public.recurrences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  name text not null,
  type text not null default 'gasto' check (type in ('gasto','ingreso')),
  amount numeric(12,2) not null check (amount >= 0),
  original_amount numeric(12,2) not null default 0 check (original_amount >= 0),
  category_id uuid references public.categories on delete set null,
  payment_method_id uuid references public.payment_methods on delete set null,
  freq text not null default 'mensual' check (freq in ('diario','semanal','quincenal','mensual','salario')),
  start_date date not null default current_date,
  day int check (day between 1 and 31),
  mode text not null default 'confirmar' check (mode in ('confirmar','recordatorio')),
  next_date date,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------- Pendientes por confirmar ----------
create table if not exists public.pending_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  source text not null check (source in ('recurrente','siri','gmail')),
  type text not null default 'gasto' check (type in ('gasto','ingreso','retiro')),
  amount numeric(12,2) not null default 0 check (amount >= 0),
  category_id uuid references public.categories on delete set null,
  payment_method_id uuid references public.payment_methods on delete set null,
  date date not null default current_date,
  note text not null default '',
  raw jsonb,
  recurrence_id uuid references public.recurrences on delete set null,
  external_id text,
  status text not null default 'pendiente' check (status in ('pendiente','aceptado','descartado')),
  created_at timestamptz not null default now(),
  unique (user_id, external_id)
);
create index if not exists pending_entries_user_status on public.pending_entries (user_id, status);

-- ---------- Movimientos: columnas nuevas ----------
alter table public.transactions add column if not exists payment_method_id uuid references public.payment_methods on delete set null;
alter table public.transactions add column if not exists recurrence_id uuid references public.recurrences on delete set null;
alter table public.transactions add column if not exists due_date date; -- fecha programada del fijo que paga este movimiento
alter table public.transactions add column if not exists goal_id uuid references public.goals on delete set null;
-- Tipos: gasto, ingreso, retiro (de una cuenta a efectivo, no es gasto) y ahorro (aportación a una meta)
alter table public.transactions drop constraint if exists transactions_type_check;
alter table public.transactions add constraint transactions_type_check check (type in ('gasto','ingreso','retiro','ahorro'));
create index if not exists transactions_recurrence on public.transactions (recurrence_id, due_date);

-- ---------- Copiar los gastos fijos actuales a "recurrences" (mismo id) ----------
insert into public.recurrences (id, user_id, name, type, amount, original_amount, category_id, freq, start_date, day, mode, active, created_at)
select fe.id, fe.user_id, fe.name, 'gasto', fe.amount, fe.amount, fe.category_id, 'mensual',
       date_trunc('month', fe.created_at)::date, fe.day, 'recordatorio', fe.active, fe.created_at
from public.fixed_expenses fe
on conflict (id) do nothing;

update public.transactions t
set recurrence_id = t.fixed_id,
    due_date = make_date(extract(year from t.date)::int, extract(month from t.date)::int,
                         least(r.day, extract(day from (date_trunc('month', t.date) + interval '1 month - 1 day'))::int))
from public.recurrences r
where r.id = t.fixed_id and t.recurrence_id is null;

-- ---------- Seguridad: cada quien solo ve y edita lo suyo ----------
alter table public.payment_methods enable row level security;
alter table public.goals enable row level security;
alter table public.recurrences enable row level security;
alter table public.pending_entries enable row level security;
drop policy if exists "propios" on public.payment_methods;
create policy "propios" on public.payment_methods for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "propios" on public.goals;
create policy "propios" on public.goals for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "propios" on public.recurrences;
create policy "propios" on public.recurrences for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "propios" on public.pending_entries;
create policy "propios" on public.pending_entries for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------- Calendario de los fijos ----------
-- Primera fecha programada en o después de p_from (nunca antes de p_start).
create or replace function public.recurrence_on_or_after(p_freq text, p_start date, p_day int, p_from date)
returns date language plpgsql immutable as $$
declare
  d date := greatest(p_from, p_start);
  m date := date_trunc('month', d)::date;
  last date;
  c date;
  step int;
begin
  if p_freq = 'diario' then return d; end if;
  if p_freq in ('semanal','quincenal') then
    step := case p_freq when 'semanal' then 7 else 15 end;
    return p_start + step * ceil((d - p_start)::numeric / step)::int;
  end if;
  if p_freq = 'salario' then
    if d <= m + 14 then return m + 14; end if;
    last := (m + interval '1 month - 1 day')::date;
    if d <= last then return last; end if;
    return (m + interval '1 month')::date + 14;
  end if;
  -- mensual
  for i in 0..1 loop
    last := (m + interval '1 month - 1 day')::date;
    c := m + least(coalesce(p_day, extract(day from p_start)::int), extract(day from last)::int) - 1;
    if c >= d then return c; end if;
    m := (m + interval '1 month')::date;
  end loop;
  return c;
end $$;

-- Crea los pendientes de los fijos "confirmar" cuya fecha ya llegó.
-- Desde la app (usuario con sesión) solo procesa sus propios fijos; desde pg_cron procesa todos.
create or replace function public.generate_pending_entries()
returns int language plpgsql security definer set search_path = public as $$
declare
  r record;
  d date;
  n int := 0;
  guard int;
  me uuid := auth.uid();
  today date := (now() at time zone 'America/Mexico_City')::date;
begin
  if me is null and current_user not in ('postgres', 'supabase_admin', 'service_role') then
    raise exception 'No autorizado';
  end if;
  for r in select * from public.recurrences
           where active and mode = 'confirmar' and (me is null or user_id = me)
           for update loop
    d := coalesce(r.next_date, public.recurrence_on_or_after(r.freq, r.start_date, r.day, r.start_date));
    guard := 0;
    while d <= today and guard < 400 loop
      if not exists (select 1 from public.transactions where recurrence_id = r.id and due_date = d) then
        insert into public.pending_entries (user_id, source, type, amount, category_id, payment_method_id, date, note, recurrence_id, external_id)
        values (r.user_id, 'recurrente', r.type, r.amount, r.category_id, r.payment_method_id, d, r.name, r.id, 'rec:' || r.id || ':' || d)
        on conflict (user_id, external_id) do nothing;
        if found then n := n + 1; end if;
      end if;
      d := public.recurrence_on_or_after(r.freq, r.start_date, r.day, d + 1);
      guard := guard + 1;
    end loop;
    if r.next_date is distinct from d then
      update public.recurrences set next_date = d where id = r.id;
    end if;
  end loop;
  return n;
end $$;
revoke all on function public.generate_pending_entries() from public, anon;
grant execute on function public.generate_pending_entries() to authenticated;

-- Mueve todo lo de una categoría a otra y luego la elimina (todo o nada).
create or replace function public.reassign_and_delete_category(p_old uuid, p_new uuid)
returns void language plpgsql security invoker set search_path = public as $$
begin
  if p_new is null or p_old = p_new then raise exception 'Elige otra categoría destino'; end if;
  if not exists (select 1 from public.categories where id = p_new) then raise exception 'La categoría destino no existe'; end if;
  update public.transactions set category_id = p_new where category_id = p_old;
  update public.recurrences set category_id = p_new where category_id = p_old;
  update public.pending_entries set category_id = p_new where category_id = p_old;
  update public.fixed_expenses set category_id = p_new where category_id = p_old;
  delete from public.categories where id = p_old;
end $$;
revoke all on function public.reassign_and_delete_category(uuid, uuid) from public, anon;
grant execute on function public.reassign_and_delete_category(uuid, uuid) to authenticated;

-- ---------- Tiempo real ----------
do $$
declare t text;
begin
  foreach t in array array['payment_methods','goals','recurrences','pending_entries'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- ---------- Revisión diaria automática (00:05 hora de México) ----------
-- La app también la ejecuta al abrirse, así que funciona aunque pg_cron no esté disponible.
do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule('generar-pendientes', '5 6 * * *', 'select public.generate_pending_entries()');
exception when others then
  raise notice 'pg_cron no disponible (%); los pendientes se generarán al abrir la app.', sqlerrm;
end $$;


-- Mis finanzas · Migración 002
-- Notificaciones push, usuarios y administradores, tokens personales (Siri y Gmail) y tareas automáticas.
--
-- Cómo aplicarla: primero la 001. Luego Supabase → SQL Editor → pega todo este archivo → Run.
-- Se puede correr más de una vez sin problema. No borra ni modifica tus movimientos.

-- ---------- Secretos internos (solo los lee el servidor, nunca la app) ----------
create table if not exists public.app_secrets (
  name text primary key,
  value text not null,
  created_at timestamptz not null default now()
);
alter table public.app_secrets enable row level security; -- sin políticas: nadie con sesión puede leerla
revoke all on public.app_secrets from anon, authenticated;
insert into public.app_secrets (name, value)
values ('cron_secret', replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''))
on conflict (name) do nothing;
insert into public.app_secrets (name, value)
values ('functions_url', 'https://luruzajftjpqrzhgmtwj.supabase.co/functions/v1')
on conflict (name) do nothing;

-- ---------- Perfiles y roles ----------
create table if not exists public.profiles (
  user_id uuid primary key references auth.users on delete cascade,
  display_name text not null default '',
  role text not null default 'user' check (role in ('admin','user')),
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
drop policy if exists "propio" on public.profiles;
create policy "propio" on public.profiles for select to authenticated using (user_id = auth.uid());
-- Los cambios de rol solo se hacen desde la función admin-usuarios (servidor).

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where user_id = auth.uid() and role = 'admin')
$$;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (user_id, display_name) values (new.id, split_part(coalesce(new.email, ''), '@', 1))
  on conflict (user_id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- Perfiles de los usuarios que ya existen; el más antiguo (el dueño) es administrador.
insert into public.profiles (user_id, display_name)
select id, split_part(coalesce(email, ''), '@', 1) from auth.users
on conflict (user_id) do nothing;
update public.profiles set role = 'admin'
where user_id = (select id from auth.users order by created_at limit 1)
  and not exists (select 1 from public.profiles where role = 'admin');

-- ---------- Preferencias de notificación ----------
alter table public.settings add column if not exists notify jsonb not null default '{}'::jsonb;

-- ---------- Dispositivos con notificaciones activadas ----------
create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  device text not null default '',
  created_at timestamptz not null default now()
);
alter table public.push_subscriptions enable row level security;
drop policy if exists "propios" on public.push_subscriptions;
create policy "propios" on public.push_subscriptions for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------- Notificaciones programadas ----------
create table if not exists public.scheduled_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  kind text not null check (kind in ('pendientes','recurrente','ingreso','recordatorio','meta','prueba')),
  title text not null,
  body text not null default '',
  url text not null default './',
  send_at timestamptz not null default now(),
  sent_at timestamptz,
  dedupe text,
  created_at timestamptz not null default now(),
  unique (user_id, dedupe)
);
create index if not exists scheduled_notifications_due on public.scheduled_notifications (send_at) where sent_at is null;
alter table public.scheduled_notifications enable row level security;
drop policy if exists "propias" on public.scheduled_notifications;
create policy "propias" on public.scheduled_notifications for select to authenticated using (user_id = auth.uid());

-- ---------- Tokens personales para Siri y Gmail (se guardan hasheados) ----------
create table if not exists public.api_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  name text not null,
  token_hash text not null unique,
  last_used_at timestamptz,
  revoked boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.api_tokens enable row level security;
drop policy if exists "ver propios" on public.api_tokens;
create policy "ver propios" on public.api_tokens for select to authenticated using (user_id = auth.uid());
drop policy if exists "revocar propios" on public.api_tokens;
create policy "revocar propios" on public.api_tokens for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "borrar propios" on public.api_tokens;
create policy "borrar propios" on public.api_tokens for delete to authenticated using (user_id = auth.uid());

-- Crea un token y lo regresa una sola vez; en la base solo queda su huella (sha256).
create or replace function public.create_api_token(p_name text) returns text
language plpgsql security definer set search_path = public as $$
declare tok text;
begin
  if auth.uid() is null then raise exception 'Inicia sesión primero'; end if;
  tok := 'mf_' || replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  insert into public.api_tokens (user_id, name, token_hash)
  values (auth.uid(), coalesce(nullif(trim(p_name), ''), 'Token'), encode(sha256(convert_to(tok, 'UTF8')), 'hex'));
  return tok;
end $$;
revoke all on function public.create_api_token(text) from public, anon;
grant execute on function public.create_api_token(text) to authenticated;

-- ---------- Hora de aviso: 9:00 de la mañana, hora de México ----------
create or replace function public.mx_today() returns date language sql stable as $$
  select (now() at time zone 'America/Mexico_City')::date
$$;
create or replace function public.mx_morning(d date) returns timestamptz language sql stable as $$
  select greatest(now(), (d + time '09:00') at time zone 'America/Mexico_City')
$$;

-- ---------- Pendientes de fijos + su aviso ----------
-- Igual que en la 001, y además, cuando la corre la tarea diaria, programa el aviso de cada pendiente nuevo.
create or replace function public.generate_pending_entries()
returns int language plpgsql security definer set search_path = public as $$
declare
  r record;
  d date;
  n int := 0;
  guard int;
  me uuid := auth.uid();
  today date := public.mx_today();
  amt text;
begin
  if me is null and current_user not in ('postgres', 'supabase_admin', 'service_role') then
    raise exception 'No autorizado';
  end if;
  for r in select * from public.recurrences
           where active and mode = 'confirmar' and (me is null or user_id = me)
           for update loop
    d := coalesce(r.next_date, public.recurrence_on_or_after(r.freq, r.start_date, r.day, r.start_date));
    guard := 0;
    while d <= today and guard < 400 loop
      if not exists (select 1 from public.transactions where recurrence_id = r.id and due_date = d) then
        insert into public.pending_entries (user_id, source, type, amount, category_id, payment_method_id, date, note, recurrence_id, external_id)
        values (r.user_id, 'recurrente', r.type, r.amount, r.category_id, r.payment_method_id, d, r.name, r.id, 'rec:' || r.id || ':' || d)
        on conflict (user_id, external_id) do nothing;
        if found then
          n := n + 1;
          amt := to_char(r.amount, 'FM$999,999,990.00');
          insert into public.scheduled_notifications (user_id, kind, title, body, url, send_at, dedupe)
          values (r.user_id,
            case when r.type = 'ingreso' then 'ingreso' else 'recurrente' end,
            case when r.type = 'ingreso' then '¿Cuánto te llegó de ' || r.name || '?' else 'Confirma tu pago: ' || r.name end,
            case when r.type = 'ingreso' then 'Toca para escribir la cantidad que recibiste (último: ' || amt || ').'
                 else amt || ' · toca para confirmarlo o cambiar el monto.' end,
            './?tab=pend', public.mx_morning(d), 'pend:rec:' || r.id || ':' || d)
          on conflict (user_id, dedupe) do nothing;
        end if;
      end if;
      d := public.recurrence_on_or_after(r.freq, r.start_date, r.day, d + 1);
      guard := guard + 1;
    end loop;
    if r.next_date is distinct from d then
      update public.recurrences set next_date = d where id = r.id;
    end if;
  end loop;
  -- Si la app la corrió al abrirse, el usuario ya está viendo sus pendientes: no hace falta avisarle.
  if me is not null then
    delete from public.scheduled_notifications where user_id = me and sent_at is null and dedupe like 'pend:rec:%';
  end if;
  return n;
end $$;
revoke all on function public.generate_pending_entries() from public, anon;
grant execute on function public.generate_pending_entries() to authenticated;

-- Recordatorios de pagos manuales (fijos en modo "recordatorio") que tocan hoy y no se han registrado.
create or replace function public.queue_reminders() returns int
language plpgsql security definer set search_path = public as $$
declare r record; today date := public.mx_today(); n int := 0;
begin
  for r in select * from public.recurrences where active and mode = 'recordatorio' loop
    if public.recurrence_on_or_after(r.freq, r.start_date, r.day, today) = today
       and not exists (select 1 from public.transactions where recurrence_id = r.id and due_date = today) then
      insert into public.scheduled_notifications (user_id, kind, title, body, url, send_at, dedupe)
      values (r.user_id, 'recordatorio',
        case when r.type = 'ingreso' then 'Hoy te toca recibir: ' || r.name else 'Recuerda pagar: ' || r.name end,
        to_char(r.amount, 'FM$999,999,990.00') || ' · toca para marcarlo cuando esté listo.',
        './?tab=fijos', public.mx_morning(today), 'rem:' || r.id || ':' || today)
      on conflict (user_id, dedupe) do nothing;
      if found then n := n + 1; end if;
    end if;
  end loop;
  return n;
end $$;

-- Pendientes de Siri o del correo que llevan más de 3 horas sin confirmar (un aviso al día como máximo).
create or replace function public.queue_pending_reminders() returns int
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in
    select user_id, count(*) total,
           count(*) filter (where source = 'siri') siri,
           count(*) filter (where source = 'gmail') gmail
    from public.pending_entries
    where status = 'pendiente' and source in ('siri','gmail') and created_at < now() - interval '3 hours'
    group by user_id
  loop
    insert into public.scheduled_notifications (user_id, kind, title, body, url, dedupe)
    values (r.user_id, 'pendientes',
      'Tienes ' || r.total || case when r.total = 1 then ' movimiento pendiente' else ' movimientos pendientes' end || ' por confirmar',
      concat_ws(' · ', case when r.siri > 0 then r.siri || ' de Siri' end, case when r.gmail > 0 then r.gmail || ' del correo' end),
      './?tab=pend', 'ext:' || public.mx_today())
    on conflict (user_id, dedupe) do nothing;
    if found then n := n + 1; end if;
  end loop;
  return n;
end $$;

-- Al registrar el salario, sugerir apartar para las metas.
create or replace function public.notify_salary() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.type = 'ingreso'
     and exists (select 1 from public.categories c where c.id = new.category_id and c.name ~* '(salario|sueldo|n[oó]mina)')
     and exists (select 1 from public.goals g where g.user_id = new.user_id and g.active) then
    insert into public.scheduled_notifications (user_id, kind, title, body, url, dedupe)
    values (new.user_id, 'meta', 'Ya llegó tu ingreso',
      'Abre la app para ver cuánto te sugiero apartar este mes para tus metas.', './?tab=resumen', 'meta:' || new.id)
    on conflict (user_id, dedupe) do nothing;
  end if;
  return new;
end $$;
drop trigger if exists on_salary_insert on public.transactions;
create trigger on_salary_insert after insert on public.transactions for each row execute function public.notify_salary();

-- Prueba de notificación (solo administradores): la programa para el propio usuario.
create or replace function public.schedule_test_notification(p_amount int, p_unit text, p_kind text) returns timestamptz
language plpgsql security definer set search_path = public as $$
declare at timestamptz; t text; b text; u text := './?tab=pend';
begin
  if not public.is_admin() then raise exception 'Solo para administradores'; end if;
  if p_amount < 0 or p_amount > 100000 then raise exception 'Cantidad no válida'; end if;
  at := now() + make_interval(
    secs  => case when p_unit = 'segundos' then p_amount else 0 end,
    mins  => case when p_unit = 'minutos'  then p_amount else 0 end,
    hours => case when p_unit = 'horas'    then p_amount else 0 end,
    days  => case when p_unit = 'dias'     then p_amount else 0 end);
  case p_kind
    when 'gmail' then t := 'Tienes 1 movimiento pendiente por confirmar'; b := '1 del correo · Retiro BBVA $2,000.00';
    when 'siri' then t := 'Tienes 1 movimiento pendiente por confirmar'; b := '1 de Siri · Gasolina $250.00';
    when 'recurrente' then t := 'Confirma tu pago: Colegiatura'; b := '$2,000.00 · toca para confirmarlo o cambiar el monto.';
    when 'recordatorio' then t := 'Recuerda pagar: Predial'; b := '$1,500.00 · toca para marcarlo cuando esté listo.'; u := './?tab=fijos';
    else raise exception 'Tipo no válido';
  end case;
  insert into public.scheduled_notifications (user_id, kind, title, body, url, send_at)
  values (auth.uid(), 'prueba', '[Prueba] ' || t, b, u, at);
  return at;
end $$;
revoke all on function public.schedule_test_notification(int, text, text) from public, anon;
grant execute on function public.schedule_test_notification(int, text, text) to authenticated;

-- Llama a la función "notificaciones" solo si hay avisos por enviar.
create or replace function public.dispatch_notifications() returns void
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.scheduled_notifications where sent_at is null and send_at <= now()) then
    perform net.http_post(
      url := (select value from public.app_secrets where name = 'functions_url') || '/notificaciones',
      headers := jsonb_build_object('Content-Type', 'application/json',
                                    'x-cron-secret', (select value from public.app_secrets where name = 'cron_secret')),
      body := '{"action":"send"}'::jsonb);
  end if;
end $$;
revoke all on function public.dispatch_notifications() from public, anon, authenticated;

create or replace function public.daily_jobs() returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.generate_pending_entries();
  perform public.queue_reminders();
end $$;
revoke all on function public.daily_jobs() from public, anon, authenticated;
revoke all on function public.queue_reminders() from public, anon, authenticated;
revoke all on function public.queue_pending_reminders() from public, anon, authenticated;

-- ---------- Tiempo real ----------
do $$
declare t text;
begin
  foreach t in array array['profiles','api_tokens'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- ---------- Tareas automáticas ----------
do $$
begin
  create extension if not exists pg_cron;
  create extension if not exists pg_net;
  perform cron.schedule('generar-pendientes', '5 6 * * *', 'select public.daily_jobs()');           -- 00:05 hora de México
  perform cron.schedule('recordar-pendientes', '20 * * * *', 'select public.queue_pending_reminders()'); -- cada hora
  perform cron.schedule('enviar-notificaciones', '* * * * *', 'select public.dispatch_notifications()'); -- cada minuto
exception when others then
  raise notice 'pg_cron o pg_net no disponibles (%). Actívalos en Database → Extensions y vuelve a correr este archivo.', sqlerrm;
end $$;


-- Mis finanzas · Migración 003
-- Apartados: lugares de ahorro e inversión (Nu, CETES, GBM…), sacar dinero, rendimientos
-- y precios de instrumentos (por ejemplo VOO) para estimar el valor de las inversiones.
--
-- Cómo aplicarla: Supabase → SQL Editor → pega todo este archivo → Run.
-- Se puede correr más de una vez sin problema. No borra ni modifica tus movimientos.

-- ---------- Lugares donde apartas dinero ----------
create table if not exists public.savings_places (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  name text not null,
  kind text not null default 'ahorro' check (kind in ('ahorro','inversion')),
  color text not null default '#2F5D9E',
  rate numeric(7,3) not null default 0 check (rate between -100 and 1000), -- rendimiento anual estimado, en %
  rate_updated_at date,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.savings_places enable row level security;
drop policy if exists "propios" on public.savings_places;
create policy "propios" on public.savings_places for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------- Instrumentos y su último precio (compartido; solo el servidor lo escribe) ----------
create table if not exists public.instruments (
  symbol text primary key,          -- clave de Yahoo Finanzas: VOO, NAFTRACISHRS.MX, MXN=X (dólar en pesos)…
  name text not null default '',
  currency text not null default 'USD',
  exchange text not null default '',
  price numeric(18,6),
  price_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.instruments enable row level security;
drop policy if exists "leer" on public.instruments;
create policy "leer" on public.instruments for select to authenticated using (true);

-- ---------- Movimientos: lugar, instrumento y títulos ----------
alter table public.transactions add column if not exists place_id uuid references public.savings_places on delete set null;
alter table public.transactions add column if not exists instrument text references public.instruments (symbol) on delete set null;
alter table public.transactions add column if not exists units numeric(18,6);
-- Tipos: gasto, ingreso, retiro (cajero), ahorro (apartar), sacar (de un apartado) y rendimiento (ajuste al saldo real; puede ser negativo)
alter table public.transactions drop constraint if exists transactions_type_check;
alter table public.transactions add constraint transactions_type_check check (type in ('gasto','ingreso','retiro','ahorro','sacar','rendimiento'));
alter table public.transactions drop constraint if exists transactions_amount_check;
alter table public.transactions add constraint transactions_amount_check check (amount >= 0 or type = 'rendimiento');
create index if not exists transactions_place on public.transactions (place_id) where place_id is not null;

-- ---------- Tiempo real ----------
do $$
declare t text;
begin
  foreach t in array array['savings_places','instruments'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- ---------- Precios: se actualizan solos de lunes a viernes al cierre del mercado ----------
create or replace function public.update_prices() returns void
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.instruments) then
    perform net.http_post(
      url := (select value from public.app_secrets where name = 'functions_url') || '/precios',
      headers := jsonb_build_object('Content-Type', 'application/json',
                                    'x-cron-secret', (select value from public.app_secrets where name = 'cron_secret')),
      body := '{"action":"update"}'::jsonb);
  end if;
end $$;
revoke all on function public.update_prices() from public, anon, authenticated;

do $$
begin
  perform cron.schedule('actualizar-precios', '15 21 * * 1-5', 'select public.update_prices()'); -- 15:15 hora de México
exception when others then
  raise notice 'pg_cron no disponible (%). Los precios se actualizarán al abrir Apartados.', sqlerrm;
end $$;


