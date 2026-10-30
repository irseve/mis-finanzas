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
