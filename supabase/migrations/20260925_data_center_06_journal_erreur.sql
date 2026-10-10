-- Appliquée dans Supabase le 25/09/2026 (version 20260925142155), exportée dans le dépôt le 10/10/2026.

create or replace function public.dc_journaliser(p_source text, p_du date, p_au date, p_statut text, p_message text)
returns void language sql security definer set search_path = marketing as $$
  insert into marketing.journal_ingestion(source, du, au, statut, message, fin) values (p_source, p_du, p_au, p_statut, left(p_message, 2000), now())
$$;
revoke all on function public.dc_journaliser(text,date,date,text,text) from public, anon, authenticated;
grant execute on function public.dc_journaliser(text,date,date,text,text) to service_role;
