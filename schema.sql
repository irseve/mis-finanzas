-- Mis finanzas: tablas y seguridad. Pega todo esto en Supabase → SQL Editor → Run.

create table if not exists public.settings (
  user_id uuid primary key default auth.uid() references auth.users on delete cascade,
  currency text not null default 'MXN'
);

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  name text not null,
  kind text not null check (kind in ('gasto','ingreso')),
  color text not null default '#5E6E67',
  budget numeric(12,2) not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.fixed_expenses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  name text not null,
  amount numeric(12,2) not null check (amount >= 0),
  category_id uuid references public.categories on delete set null,
  day int not null default 1 check (day between 1 and 31),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  type text not null check (type in ('gasto','ingreso')),
  amount numeric(12,2) not null check (amount >= 0),
  category_id uuid references public.categories on delete set null,
  date date not null,
  note text not null default '',
  fixed_id uuid references public.fixed_expenses on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists transactions_user_date on public.transactions (user_id, date);

-- Cada quien solo ve y edita sus propios datos
alter table public.settings enable row level security;
alter table public.categories enable row level security;
alter table public.fixed_expenses enable row level security;
alter table public.transactions enable row level security;

create policy "propios" on public.settings for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "propios" on public.categories for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "propios" on public.fixed_expenses for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "propios" on public.transactions for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Actualización en tiempo real entre dispositivos
alter publication supabase_realtime add table public.transactions, public.fixed_expenses, public.categories, public.settings;
