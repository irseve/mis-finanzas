-- Mis finanzas · Migración 008
-- Grupos de gastos propios (por ejemplo "Casa", "Médicos", "Innecesarios"), con tope mensual opcional
-- y aviso al llegar al 80% del tope y al rebasarlo (una vez por mes y grupo).
--
-- Cómo aplicarla: Supabase → SQL Editor → pega todo este archivo → Run.
-- Se puede correr más de una vez sin problema. No borra ni modifica tus movimientos.

-- ---------- Grupos ----------
create table if not exists public.expense_groups (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  name text not null,
  color text not null default '#5E6E67',
  cap numeric(12,2) not null default 0 check (cap >= 0), -- tope mensual; 0 = sin tope
  created_at timestamptz not null default now()
);
alter table public.expense_groups enable row level security;
drop policy if exists "propios" on public.expense_groups;
create policy "propios" on public.expense_groups for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Cada gasto puede estar en un solo grupo (o en ninguno). Al borrar un grupo, sus gastos quedan sin grupo.
alter table public.transactions add column if not exists group_id uuid references public.expense_groups on delete set null;
alter table public.recurrences add column if not exists group_id uuid references public.expense_groups on delete set null;
alter table public.pending_entries add column if not exists group_id uuid references public.expense_groups on delete set null;
create index if not exists transactions_group on public.transactions (group_id, date) where group_id is not null;

-- ---------- Aviso de tope ----------
alter table public.scheduled_notifications drop constraint if exists scheduled_notifications_kind_check;
alter table public.scheduled_notifications add constraint scheduled_notifications_kind_check
  check (kind in ('pendientes','recurrente','ingreso','recordatorio','meta','prueba','resumen','mensaje','tope'));

-- Al registrar o cambiar un gasto del mes en curso con grupo, revisa el tope de ese grupo.
-- Avisa una sola vez por mes y grupo al llegar al 80% y otra al rebasarlo (el aviso se puede apagar en Ajustes).
create or replace function public.check_group_cap() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  g record;
  total numeric;
  ym text := to_char(public.mx_today(), 'YYYY-MM');
  m0 date := date_trunc('month', public.mx_today())::date;
begin
  if new.group_id is null or new.type <> 'gasto' or to_char(new.date, 'YYYY-MM') <> ym then return new; end if;
  select id, name, cap into g from public.expense_groups where id = new.group_id;
  if g.id is null or g.cap <= 0 then return new; end if;
  select coalesce(sum(amount), 0) into total from public.transactions
    where group_id = g.id and type = 'gasto' and date >= m0 and date < (m0 + interval '1 month')::date;
  if total > g.cap then
    insert into public.scheduled_notifications (user_id, kind, title, body, url, dedupe)
    values (new.user_id, 'tope', 'Rebasaste el tope de ' || g.name,
      'Llevas ' || to_char(total, 'FM$999,999,990.00') || ' de ' || to_char(g.cap, 'FM$999,999,990.00')
        || ' este mes · te pasaste por ' || to_char(total - g.cap, 'FM$999,999,990.00') || '.',
      './', 'tope:' || g.id || ':' || ym || ':100')
    on conflict (user_id, dedupe) do nothing;
  elsif total >= g.cap * 0.8 then
    insert into public.scheduled_notifications (user_id, kind, title, body, url, dedupe)
    values (new.user_id, 'tope', 'Llevas el ' || floor(total / g.cap * 100) || '% del tope de ' || g.name,
      'Llevas ' || to_char(total, 'FM$999,999,990.00') || ' de ' || to_char(g.cap, 'FM$999,999,990.00')
        || ' · te quedan ' || to_char(g.cap - total, 'FM$999,999,990.00') || ' este mes.',
      './', 'tope:' || g.id || ':' || ym || ':80')
    on conflict (user_id, dedupe) do nothing;
  end if;
  return new;
end $$;
revoke all on function public.check_group_cap() from public, anon, authenticated;
drop trigger if exists transactions_group_cap on public.transactions;
create trigger transactions_group_cap after insert or update of amount, group_id, date, type on public.transactions
  for each row execute function public.check_group_cap();

-- ---------- Tiempo real ----------
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'expense_groups') then
    alter publication supabase_realtime add table public.expense_groups;
  end if;
end $$;
