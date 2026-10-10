-- Appliquée dans Supabase le 25/09/2026 (version 20260925142421), exportée dans le dépôt le 10/10/2026.

-- tolérance réaliste : GA4 estime les sessions (HyperLogLog), l'écart détail/total est de 1 à 2 % en temps normal
create or replace function public.dc_controler(p_du date, p_au date)
returns jsonb language plpgsql security definer set search_path = marketing, public, pg_catalog as $$
declare r record; nb int := 0;
begin
  delete from controle_ingestion where jour between p_du and p_au;
  for r in select t.jour, t.sessions attendu, coalesce(sum(a.sessions),0) obtenu, t.transactions t_att, coalesce(sum(a.transactions),0) t_obt
           from fait_analytics_total_jour t left join fait_analytics_jour a on a.jour = t.jour
           where t.jour between p_du and p_au group by t.jour, t.sessions, t.transactions loop
    insert into controle_ingestion(jour, source, controle, attendu, obtenu, ecart_pct, ok)
    values (r.jour, 'ga4', 'sessions_detail_vs_total', r.attendu, r.obtenu,
            round(100.0*(r.obtenu - r.attendu)/nullif(r.attendu,0),2), abs(r.obtenu - r.attendu) <= greatest(0.03*r.attendu, 10)),
           (r.jour, 'ga4', 'transactions_detail_vs_total', r.t_att, r.t_obt,
            round(100.0*(r.t_obt - r.t_att)/nullif(r.t_att,0),2), abs(r.t_obt - r.t_att) <= 1);
    nb := nb + 2;
  end loop;
  for r in select c.jour, c.commandes attendu, t.transactions obtenu from v_commerce_jour c
           join fait_analytics_total_jour t on t.jour = c.jour where c.jour between p_du and p_au loop
    insert into controle_ingestion(jour, source, controle, attendu, obtenu, ecart_pct, ok)
    values (r.jour, 'ga4', 'captation_vs_prestashop', r.attendu, r.obtenu, round(100.0*r.obtenu/nullif(r.attendu,0),1),
            r.obtenu between 0.8*r.attendu and 1.1*r.attendu);
    nb := nb + 1;
  end loop;
  for r in select jour, sessions attendu, sessions_sans_page_entree obtenu from fait_analytics_total_jour
           where jour between p_du and p_au and sessions_sans_page_entree is not null loop
    insert into controle_ingestion(jour, source, controle, attendu, obtenu, ecart_pct, ok)
    values (r.jour, 'ga4', 'sessions_sans_page_entree', r.attendu, r.obtenu, round(100.0*r.obtenu/nullif(r.attendu,0),1),
            r.obtenu <= 0.10*r.attendu);
    nb := nb + 1;
  end loop;
  return jsonb_build_object('controles', nb);
end $$;
revoke all on function public.dc_controler(date, date) from public, anon, authenticated;
grant execute on function public.dc_controler(date, date) to service_role;

-- File de rattrapage de l'historique (un mois par passage, toutes les 5 minutes)
create table if not exists marketing.file_rattrapage (
  du date primary key, au date not null,
  statut text not null default 'a_faire' check (statut in ('a_faire','lance')),
  lance_le timestamptz, requete_id bigint
);
alter table marketing.file_rattrapage enable row level security;
insert into marketing.file_rattrapage(du, au)
select m::date, least((m + interval '1 month - 1 day')::date, date '2026-09-17')
from generate_series(date '2025-03-01', date '2026-09-01', interval '1 month') m
on conflict do nothing;

create or replace function marketing.traiter_rattrapage()
returns void language plpgsql security definer set search_path = marketing, public as $$
declare r record;
begin
  select * into r from marketing.file_rattrapage where statut = 'a_faire' order by du desc limit 1;
  if not found then return; end if;
  update marketing.file_rattrapage set statut = 'lance', lance_le = now(),
    requete_id = marketing.lancer_ingestion(jsonb_build_object('du', r.du, 'au', r.au))
  where du = r.du;
end $$;

select cron.schedule('dc-rattrapage', '*/5 * * * *', 'select marketing.traiter_rattrapage()');
-- Nuit : 30 derniers jours à 04:30 heure de Paris (02:30 UTC en été), après l'import PrestaShop de 03:30
select cron.schedule('dc-ingestion-nuit', '30 2 * * *', 'select marketing.lancer_ingestion()');
