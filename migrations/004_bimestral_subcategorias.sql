-- Mis finanzas · Migración 004
-- Frecuencia bimestral para fijos y subcategorías (un solo nivel).
--
-- Cómo aplicarla: Supabase → SQL Editor → pega todo este archivo → Run.
-- Se puede correr más de una vez sin problema. No borra ni modifica tus movimientos.

-- ---------- Bimestral: cada 2 meses, el mismo día ----------
alter table public.recurrences drop constraint if exists recurrences_freq_check;
alter table public.recurrences add constraint recurrences_freq_check
  check (freq in ('diario','semanal','quincenal','mensual','bimestral','salario'));

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
  -- mensual (cada mes) o bimestral (cada 2 meses contando desde el mes de inicio)
  step := case p_freq when 'bimestral' then 2 else 1 end;
  if step = 2 then
    k := (extract(year from m)::int - extract(year from sm)::int) * 12 + extract(month from m)::int - extract(month from sm)::int;
    if k % 2 <> 0 then m := (m + interval '1 month')::date; end if;
  end if;
  for i in 0..1 loop
    last := (m + interval '1 month - 1 day')::date;
    c := m + least(coalesce(p_day, extract(day from p_start)::int), extract(day from last)::int) - 1;
    if c >= d then return c; end if;
    m := (m + make_interval(months => step))::date;
  end loop;
  return c;
end $$;

-- ---------- Subcategorías: una categoría puede tener una categoría "padre" (un solo nivel) ----------
alter table public.categories add column if not exists parent_id uuid references public.categories on delete set null;
create index if not exists categories_parent on public.categories (parent_id) where parent_id is not null;

-- Al eliminar una categoría: sus movimientos pasan a la destino y sus subcategorías también
-- (o quedan como categorías normales si la destino ya es una subcategoría).
create or replace function public.reassign_and_delete_category(p_old uuid, p_new uuid)
returns void language plpgsql security invoker set search_path = public as $$
declare dest_parent uuid;
begin
  if p_new is null or p_old = p_new then raise exception 'Elige otra categoría destino'; end if;
  select parent_id into dest_parent from public.categories where id = p_new;
  if not found then raise exception 'La categoría destino no existe'; end if;
  update public.categories set parent_id = case when dest_parent is null and id <> p_new then p_new else null end where parent_id = p_old;
  update public.transactions set category_id = p_new where category_id = p_old;
  update public.recurrences set category_id = p_new where category_id = p_old;
  update public.pending_entries set category_id = p_new where category_id = p_old;
  update public.fixed_expenses set category_id = p_new where category_id = p_old;
  delete from public.categories where id = p_old;
end $$;
revoke all on function public.reassign_and_delete_category(uuid, uuid) from public, anon;
grant execute on function public.reassign_and_delete_category(uuid, uuid) to authenticated;
