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
