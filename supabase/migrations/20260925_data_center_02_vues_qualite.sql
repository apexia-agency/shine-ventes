-- Appliquée dans Supabase le 25/09/2026 (version 20260925112855), exportée dans le dépôt le 10/10/2026.

create or replace function marketing.est_provisoire(d date)
returns boolean language sql immutable as $$ select d > (now() at time zone 'Europe/Paris')::date - 3 $$;

-- ---------- COMMERCE : ce que PrestaShop ENCAISSE (particuliers uniquement) ----------
create or replace view marketing.v_commerce_jour with (security_invoker = true) as
with pieces as (
  select p.id, p.date_facture as jour, p.avoir, p.frais_port_facture_ht, p.source_client_id
  from public.ventes_pieces p
  join public.groupes_segments g
    on g.source = 'prestashop_b2c' and g.groupe_client = p.groupe_client and g.segment_propose = 'B2C'
  where p.canal = 'prestashop_b2c' and p.retenue and p.doublon_de is null
), lignes as (
  select l.piece_id, sum(l.total_ligne_ht) ca_ht from public.ventes_lignes l
  where l.piece_id in (select id from pieces) group by 1
)
select pc.jour,
       count(*) filter (where not pc.avoir)                     as commandes,
       count(*) filter (where pc.avoir)                         as avoirs,
       coalesce(sum(li.ca_ht),0)::numeric(12,2)                 as ca_ht,
       coalesce(sum(pc.frais_port_facture_ht),0)::numeric(12,2) as port_ht,
       count(distinct pc.source_client_id)                      as clients
from pieces pc left join lignes li on li.piece_id = pc.id
group by pc.jour;

-- ---------- RÉGIES ----------
create or replace view marketing.v_regie_jour with (security_invoker = true) as
select jour, plateforme,
       sum(depense)::numeric(12,2) depense, sum(impressions) impressions, sum(clics) clics,
       sum(conversions_revendiquees) conversions_revendiquees,
       sum(valeur_revendiquee)::numeric(12,2) valeur_revendiquee
from marketing.fait_regie_jour group by 1,2;

-- ---------- ANALYTICS par canal ----------
create or replace view marketing.v_analytics_canal_jour with (security_invoker = true) as
select jour, coalesce(canal,'Unassigned') canal,
       sum(sessions) sessions, sum(sessions_engagees) sessions_engagees,
       sum(transactions) transactions, sum(ca_mesure)::numeric(12,2) ca_mesure
from marketing.fait_analytics_jour group by 1,2;

-- ---------- MER : le chiffre qui ne ment pas ----------
create or replace view marketing.v_mer_jour with (security_invoker = true) as
with dep as (select jour, sum(depense) depense_totale from marketing.fait_regie_jour group by 1),
     ga as (select jour, transactions, ca_mesure, sessions from marketing.fait_analytics_total_jour)
select coalesce(c.jour, d.jour, g.jour) jour,
       d.depense_totale::numeric(12,2) depense_totale,
       c.commandes, c.ca_ht ca_encaisse_ht, c.port_ht,
       g.sessions, g.transactions transactions_ga4, g.ca_mesure ca_mesure_ga4,
       case when d.depense_totale > 0 then round(c.ca_ht / d.depense_totale, 2) end mer,
       marketing.est_provisoire(coalesce(c.jour, d.jour, g.jour)) provisoire
from marketing.v_commerce_jour c
full join dep d on d.jour = c.jour
full join ga g on g.jour = coalesce(c.jour, d.jour);

-- ---------- PERF campagne : régie vs GA4, jointure par identifiant puis par nom historisé ----------
create or replace view marketing.v_perf_campagne_jour with (security_invoker = true) as
with r as (
  select jour, plateforme, campagne_id, max(campagne_nom) campagne_nom,
         sum(depense) depense, sum(clics) clics, sum(impressions) impressions,
         sum(conversions_revendiquees) conv_rev, sum(valeur_revendiquee) valeur_rev
  from marketing.fait_regie_jour group by 1,2,3
), a_id as (
  select jour, campagne_id, sum(sessions) sessions, sum(sessions_engagees) engagees,
         sum(transactions) transactions, sum(ca_mesure) ca_mesure
  from marketing.fait_analytics_jour where campagne_id <> '' group by 1,2
), a_nom as (
  select a.jour, n.plateforme, n.campagne_id, sum(a.sessions) sessions, sum(a.sessions_engagees) engagees,
         sum(a.transactions) transactions, sum(a.ca_mesure) ca_mesure
  from marketing.fait_analytics_jour a
  join marketing.dim_campagne_nom n on n.nom = a.campagne_brut and a.jour between n.vu_du - 30 and n.vu_au + 30
  where a.campagne_id = '' group by 1,2,3
)
select r.jour, r.plateforme, r.campagne_id, coalesce(dc.nom_actuel, r.campagne_nom) campagne,
       r.depense::numeric(12,2), r.clics, r.impressions, r.conv_rev, r.valeur_rev::numeric(12,2),
       coalesce(ai.sessions,0)+coalesce(an.sessions,0) sessions,
       coalesce(ai.engagees,0)+coalesce(an.engagees,0) sessions_engagees,
       coalesce(ai.transactions,0)+coalesce(an.transactions,0) transactions,
       (coalesce(ai.ca_mesure,0)+coalesce(an.ca_mesure,0))::numeric(12,2) ca_mesure,
       case when coalesce(ai.ca_mesure,0)+coalesce(an.ca_mesure,0) > 0
            then round(r.valeur_rev / (coalesce(ai.ca_mesure,0)+coalesce(an.ca_mesure,0)), 2) end facteur_gonflement,
       case when r.depense > 0 then round((coalesce(ai.ca_mesure,0)+coalesce(an.ca_mesure,0)) / r.depense, 2) end roas_mesure,
       marketing.est_provisoire(r.jour) provisoire
from r
left join marketing.dim_campagne dc on dc.plateforme = r.plateforme and dc.campagne_id = r.campagne_id
left join a_id ai on ai.jour = r.jour and ai.campagne_id = r.campagne_id
left join a_nom an on an.jour = r.jour and an.plateforme = r.plateforme and an.campagne_id = r.campagne_id;

-- ---------- FIABILITÉ : pire état connu par jour × plateforme × métrique ----------
create or replace function marketing.fiabilite(p_jour date, p_plateforme text, p_metrique text)
returns text language sql stable as $$
  select coalesce((
    select e.fiabilite from marketing.evenement_qualite e
    where p_jour between e.du and coalesce(e.au, 'infinity'::date)
      and (e.plateforme is null or e.plateforme = p_plateforme)
      and (e.metrique = p_metrique or e.metrique = 'tout')
    order by array_position(array['non_fiable','anomalie','a_verifier','partiel','fiable'], e.fiabilite)
    limit 1), 'fiable')
$$;

-- ---------- Journal de fiabilité initial (issu des passations du 25/09) ----------
insert into marketing.evenement_qualite (du, au, plateforme, perimetre, metrique, fiabilite, raison, source) values
 ('2024-10-01','2026-08-20', null,        'tout','sessions',   'non_fiable','Avant pose des UTM acq_* : trafic Meta et TikTok fuyant vers direct/referral','journal'),
 ('2026-08-21', null,        null,        'tout','sessions',   'fiable',    'UTM acq_* posés sur Meta et TikTok le 21/08','journal'),
 ('2024-10-01','2026-08-26', 'google_ads','tout','conversions','non_fiable','Avant consentement avancé (posé par Adam le 27/08)','journal'),
 ('2026-08-27', null,        'google_ads','tout','conversions','partiel',   'Consentement avancé posé ; modélisation en cours','journal'),
 ('2024-10-01', null,        'meta',      'tout','conversions','partiel',   'Attribution 7j clic / 1j vue : gonflement mesuré x4 à x5,8','journal'),
 ('2024-10-01', null,        'tiktok_ads','tout','conversions','non_fiable','Post-affichage dominant : gonflement x62','journal'),
 ('2024-10-01', null,        'google_ads','tout','valeur',     'non_fiable','Variable GTM « Domaine valeur de transaction » : repli à 1 € — non corrigée au 25/09','journal'),
 ('2026-08-26','2026-09-03', 'google_ads','21502271948','tout','anomalie',  'ROAS cible 600 % — bascule de l''inventaire PMax vers Discover','journal'),
 ('2026-08-21','2026-08-21', 'meta',      'tout','attribution','anomalie',  'Renommage des campagnes Meta : historique réécrit sous les nouveaux noms','journal'),
 ('2026-09-24','2026-09-24', 'ga4',       'tout','sessions',   'a_verifier','12 291 sessions dont 4 121 sans page d''entrée, engagement 29 % ; sessions engagées stables (3 285 vs 2 977) ; achats cohérents avec PrestaShop','controle_auto');

grant execute on all functions in schema marketing to service_role;
