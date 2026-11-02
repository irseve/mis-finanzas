-- Mis finanzas · Migración 006
-- Avisos a pedido (por ejemplo, los que manda Claude desde el chat cuando el usuario lo pide).
--
-- Cómo aplicarla: Supabase → SQL Editor → pega todo este archivo → Run.
-- Se puede correr más de una vez sin problema. No borra ni modifica tus datos.

alter table public.scheduled_notifications drop constraint if exists scheduled_notifications_kind_check;
alter table public.scheduled_notifications add constraint scheduled_notifications_kind_check
  check (kind in ('pendientes','recurrente','ingreso','recordatorio','meta','prueba','resumen','mensaje'));
