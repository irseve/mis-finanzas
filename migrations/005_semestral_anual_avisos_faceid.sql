-- Mis finanzas · Migración 005
-- Frecuencias semestral y anual, corrección de avisos de pendientes (+ resumen diario opcional),
-- nombre para la bienvenida y llaves de Face ID / huella (passkeys).
--
-- Cómo aplicarla: Supabase → SQL Editor → pega todo este archivo → Run.
-- Se puede correr más de una vez sin problema. No borra ni modifica tus movimientos.

-- ---------- Semestral y anual ----------
alter table public.recurrences drop constraint if exists recurrences_freq_check;
alter table public.recurrences add constraint recurrences_freq_check
  check (freq in ('diario','semanal','quincenal','mensual','bimestral','semestral','anual','salario'));

create or replace function public.recurrence_on_or_after(p_freq text, p_start date, p_day int, p_from date)
returns date language plpgsql immutable as $$
declare
  d date := greatest(p_from, p_start);
  m date := date_trunc('month', d)::date;
  sm date := date_trunc('month', p_start)::date;
  last date;
  c date;
  step int;
  k int;
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
  -- mensual (1), bimestral (2), semestral (6) o anual (12 meses), contando desde el mes de la primera fecha
  step := case p_freq when 'bimestral' then 2 when 'semestral' then 6 when 'anual' then 12 else 1 end;
  k := (extract(year from m)::int - extract(year from sm)::int) * 12 + extract(month from m)::int - extract(month from sm)::int;
  if k % step <> 0 then m := (m + make_interval(months => step - (k % step)))::date; end if;
  for i in 0..1 loop
    last := (m + interval '1 month - 1 day')::date;
    c := m + least(coalesce(p_day, extract(day from p_start)::int), extract(day from last)::int) - 1;
    if c >= d then return c; end if;
    m := (m + make_interval(months => step))::date;
  end loop;
  return c;
end $$;

-- ---------- Avisos: ligados a su pendiente y resumen diario ----------
alter table public.scheduled_notifications add column if not exists pending_id uuid references public.pending_entries on delete cascade;
alter table public.scheduled_notifications drop constraint if exists scheduled_notifications_kind_check;
alter table public.scheduled_notifications add constraint scheduled_notifications_kind_check
  check (kind in ('pendientes','recurrente','ingreso','recordatorio','meta','prueba','resumen'));

-- Igual que antes, pero: el aviso se programa también cuando el pendiente lo crea la app al abrirse,
-- queda ligado al pendiente (si se confirma o descarta antes, no se envía) y ya no se borra al abrir la app.
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
  pid uuid;
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
        pid := null;
        insert into public.pending_entries (user_id, source, type, amount, category_id, payment_method_id, date, note, recurrence_id, external_id)
        values (r.user_id, 'recurrente', r.type, r.amount, r.category_id, r.payment_method_id, d, r.name, r.id, 'rec:' || r.id || ':' || d)
        on conflict (user_id, external_id) do nothing
        returning id into pid;
        if pid is not null then
          n := n + 1;
          amt := to_char(r.amount, 'FM$999,999,990.00');
          insert into public.scheduled_notifications (user_id, kind, title, body, url, send_at, dedupe, pending_id)
          values (r.user_id,
            case when r.type = 'ingreso' then 'ingreso' else 'recurrente' end,
            case when r.type = 'ingreso' then '¿Cuánto te llegó de ' || r.name || '?' else 'Confirma tu pago: ' || r.name end,
            case when r.type = 'ingreso' then 'Toca para escribir la cantidad que recibiste (último: ' || amt || ').'
                 else amt || ' · toca para confirmarlo o cambiar el monto.' end,
            './?tab=pend', public.mx_morning(d), 'pend:rec:' || r.id || ':' || d, pid)
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
  return n;
end $$;
revoke all on function public.generate_pending_entries() from public, anon;
grant execute on function public.generate_pending_entries() to authenticated;

-- Resumen diario a las 9:00 (hora de México) de todo lo que siga por confirmar. Se puede apagar en Ajustes.
create or replace function public.queue_daily_summary() returns int
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in
    select user_id, count(*) total,
           string_agg(coalesce(nullif(note, ''), 'Movimiento') || ' ' || to_char(amount, 'FM$999,999,990.00'), ' · ' order by date) filter (where rn <= 3) lista
    from (select *, row_number() over (partition by user_id order by date) rn from public.pending_entries where status = 'pendiente') p
    group by user_id
  loop
    insert into public.scheduled_notifications (user_id, kind, title, body, url, dedupe)
    values (r.user_id, 'resumen',
      'Tienes ' || r.total || case when r.total = 1 then ' movimiento por confirmar' else ' movimientos por confirmar' end,
      r.lista || case when r.total > 3 then '…' else '' end,
      './?tab=pend', 'resumen:' || public.mx_today())
    on conflict (user_id, dedupe) do nothing;
    if found then n := n + 1; end if;
  end loop;
  return n;
end $$;
revoke all on function public.queue_daily_summary() from public, anon, authenticated;

-- ---------- Nombre para la bienvenida ("Hola Irving") ----------
alter table public.settings add column if not exists display_name text not null default '';

-- ---------- Face ID / huella: llaves de acceso (passkeys) ----------
create table if not exists public.webauthn_credentials (
  id text primary key,                       -- identificador de la llave (base64url)
  user_id uuid not null references auth.users on delete cascade,
  public_key text not null,                  -- llave pública (base64url); la privada nunca sale del teléfono
  counter bigint not null default 0,
  transports text[] not null default '{}',
  device text not null default '',
  created_at timestamptz not null default now(),
  last_used_at timestamptz
);
alter table public.webauthn_credentials enable row level security;
drop policy if exists "ver propias" on public.webauthn_credentials;
create policy "ver propias" on public.webauthn_credentials for select to authenticated using (user_id = auth.uid());
drop policy if exists "borrar propias" on public.webauthn_credentials;
create policy "borrar propias" on public.webauthn_credentials for delete to authenticated using (user_id = auth.uid());

-- Retos de un solo uso para registrar o usar una llave (solo el servidor los lee).
create table if not exists public.webauthn_challenges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users on delete cascade,
  challenge text not null,
  kind text not null check (kind in ('registro','acceso')),
  created_at timestamptz not null default now()
);
alter table public.webauthn_challenges enable row level security; -- sin políticas: nadie con sesión puede leerla
revoke all on public.webauthn_challenges from anon, authenticated;

-- ---------- Tareas automáticas ----------
do $$
begin
  perform cron.schedule('resumen-pendientes', '2 15 * * *', 'select public.queue_daily_summary()'); -- 9:02 hora de México
  perform cron.schedule('limpiar-retos', '17 4 * * *', $q$delete from public.webauthn_challenges where created_at < now() - interval '1 day'$q$);
exception when others then
  raise notice 'pg_cron no disponible (%).', sqlerrm;
end $$;
