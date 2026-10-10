-- Appliquée dans Supabase le 25/09/2026 (version 20260925142147), exportée dans le dépôt le 10/10/2026.

create extension if not exists pg_net;
create extension if not exists pg_cron;

-- Jeton interne généré dans le coffre : jamais affiché, jamais saisi à la main
do $$ begin
  if not exists (select 1 from vault.secrets where name = 'dc_jeton_ingestion') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32),'hex'), 'dc_jeton_ingestion', 'Jeton de déclenchement de l''Edge Function dc-ingestion');
  end if;
end $$;

create or replace function public.dc_verifier_jeton(p_jeton text)
returns boolean language sql stable security definer set search_path = public, vault as $$
  select exists (select 1 from vault.decrypted_secrets where name = 'dc_jeton_ingestion' and decrypted_secret = p_jeton)
$$;
revoke all on function public.dc_verifier_jeton(text) from public, anon, authenticated;
grant execute on function public.dc_verifier_jeton(text) to service_role;

-- Lance l'ingestion (appelé par pg_cron ou à la main par un admin en SQL)
create or replace function marketing.lancer_ingestion(p_corps jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path = public, vault, extensions as $$
declare v_jeton text; v_id bigint;
begin
  select decrypted_secret into v_jeton from vault.decrypted_secrets where name = 'dc_jeton_ingestion';
  select net.http_post(
    url := 'https://dfolpanugctzebwpfhze.supabase.co/functions/v1/dc-ingestion',
    headers := jsonb_build_object('Content-Type','application/json','x-dc-jeton', v_jeton),
    body := p_corps,
    timeout_milliseconds := 400000) into v_id;
  return v_id;
end $$;
revoke all on function marketing.lancer_ingestion(jsonb) from public, anon, authenticated;
