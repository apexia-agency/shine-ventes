-- Appliquée dans Supabase le 25/09/2026 (version 20260925112820), exportée dans le dépôt le 10/10/2026.

-- =====================================================================
-- DATA CENTER (board particuliers) — schéma marketing
-- Règles : clé campagne = identifiant externe, jamais le nom ;
-- trois natures de chiffres (régie revendique / analytics mesure / commerce encaisse)
-- jamais dans la même colonne ; écritures idempotentes (upsert).
-- Schéma non exposé à l'API : le board passe par des fonctions public.dc_*
-- =====================================================================
create schema if not exists marketing;
revoke all on schema marketing from public, anon, authenticated;

-- ---------- Référentiels ----------
create table marketing.ref_plateforme (
  code text primary key,
  libelle text not null,
  nature text not null check (nature in ('regie','analytics','commerce','organique','email','seo')),
  connecteur text,              -- slug Windsor ou 'supabase'
  actif boolean not null default true
);
insert into marketing.ref_plateforme(code,libelle,nature,connecteur) values
 ('google_ads','Google Ads','regie','google_ads'),
 ('meta','Meta Ads','regie','facebook'),
 ('tiktok_ads','TikTok Ads','regie','tiktok'),
 ('ga4','Google Analytics 4','analytics','googleanalytics4'),
 ('prestashop','PrestaShop shine-group.fr (particuliers)','commerce','supabase'),
 ('instagram','Instagram','organique','instagram'),
 ('facebook_page','Facebook (page)','organique','facebook_organic'),
 ('tiktok_organique','TikTok (compte)','organique','tiktok_organic'),
 ('youtube','YouTube','organique','youtube'),
 ('pinterest','Pinterest','organique','pinterest_organic'),
 ('omnisend','Omnisend','email','omnisend'),
 ('search_console','Google Search Console','seo','searchconsole')
on conflict (code) do nothing;

create table marketing.ref_compte (
  plateforme text not null references marketing.ref_plateforme(code),
  compte_id text not null,
  libelle text,
  primary key (plateforme, compte_id)
);
insert into marketing.ref_compte values
 ('google_ads','544-938-9696','Auto Shine'),
 ('meta','168512238364027','Shine'),
 ('ga4','266731006','Shine'),
 ('search_console','sc-domain:shine-group.fr','shine-group.fr')
on conflict do nothing;

-- ---------- Campagnes : identité stable + historique des noms ----------
create table marketing.dim_campagne (
  plateforme text not null references marketing.ref_plateforme(code),
  campagne_id text not null,           -- = utm_id = {{campaign.id}}
  compte_id text,
  type_campagne text,                  -- PMAX, SEARCH, ASC+, ...
  nom_actuel text,
  premiere_vue date,
  derniere_vue date,
  primary key (plateforme, campagne_id)
);
create table marketing.dim_campagne_nom (
  plateforme text not null,
  campagne_id text not null,
  nom text not null,
  vu_du date not null,
  vu_au date not null,
  primary key (plateforme, campagne_id, nom),
  foreign key (plateforme, campagne_id) references marketing.dim_campagne(plateforme, campagne_id) on delete cascade
);
create index on marketing.dim_campagne_nom (nom);

-- ---------- Faits : ce que la régie REVENDIQUE ----------
create table marketing.fait_regie_jour (
  jour date not null,
  plateforme text not null references marketing.ref_plateforme(code),
  compte_id text not null,
  campagne_id text not null,
  reseau text not null default 'TOUS',  -- SEARCH / YOUTUBE / DISCOVER / CONTENT / MAPS / facebook / instagram / audience_network ...
  campagne_nom text,                    -- nom au moment du chargement (info, jamais clé)
  impressions bigint default 0,
  clics bigint default 0,
  clics_lien bigint,
  depense numeric(12,2) default 0,
  conversions_revendiquees numeric(12,2),
  valeur_revendiquee numeric(12,2),
  fenetre_attribution text,             -- ex. '7d_click,1d_view'
  charge_le timestamptz not null default now(),
  primary key (jour, plateforme, compte_id, campagne_id, reseau)
);
create index on marketing.fait_regie_jour (plateforme, campagne_id, jour);

-- niveau publicité (créas d'Anne)
create table marketing.fait_regie_pub_jour (
  jour date not null,
  plateforme text not null references marketing.ref_plateforme(code),
  campagne_id text not null,
  groupe_id text not null default '',
  pub_id text not null,
  pub_nom text,
  groupe_nom text,
  impressions bigint default 0,
  clics bigint default 0,
  clics_lien bigint,
  depense numeric(12,2) default 0,
  conversions_revendiquees numeric(12,2),
  valeur_revendiquee numeric(12,2),
  vues_video_3s bigint,
  charge_le timestamptz not null default now(),
  primary key (jour, plateforme, campagne_id, groupe_id, pub_id)
);

-- ---------- Faits : ce que GA4 MESURE (dimensions session_* uniquement) ----------
create table marketing.fait_analytics_jour (
  jour date not null,
  source text not null,
  medium text not null,
  campagne_brut text not null default '(not set)',  -- utm_campaign brut, non retouché
  campagne_id text not null default '',              -- utm_id si présent
  contenu_brut text not null default '',             -- utm_content (nom de pub)
  canal text,                                        -- groupe de canaux par défaut
  sessions integer default 0,
  sessions_engagees integer default 0,
  utilisateurs integer default 0,
  nouveaux_utilisateurs integer default 0,
  transactions integer default 0,
  ca_mesure numeric(12,2) default 0,                 -- purchase_revenue (TTC, port inclus)
  charge_le timestamptz not null default now(),
  primary key (jour, source, medium, campagne_brut, campagne_id, contenu_brut)
);
create index on marketing.fait_analytics_jour (jour);
create index on marketing.fait_analytics_jour (campagne_id) where campagne_id <> '';

-- totaux GA4 du jour sans dimension : sert au contrôle de cohérence
create table marketing.fait_analytics_total_jour (
  jour date primary key,
  sessions integer, sessions_engagees integer, utilisateurs integer,
  transactions integer, ca_mesure numeric(12,2),
  sessions_sans_page_entree integer,          -- sessions sans landing page (détecteur d'anomalie)
  charge_le timestamptz not null default now()
);

-- pages d'entrée (SEO / landing)
create table marketing.fait_analytics_page_jour (
  jour date not null,
  page_entree text not null,
  canal text not null default '',
  sessions integer default 0, sessions_engagees integer default 0,
  transactions integer default 0, ca_mesure numeric(12,2) default 0,
  primary key (jour, page_entree, canal)
);

-- ---------- Organique ----------
create table marketing.fait_organique_jour (
  jour date not null,
  plateforme text not null references marketing.ref_plateforme(code),
  compte_id text not null,
  abonnes bigint, abonnes_gagnes integer, abonnes_perdus integer,
  impressions bigint, portee bigint, vues bigint, vues_profil integer,
  engagements integer, clics_lien integer, publications integer,
  charge_le timestamptz not null default now(),
  primary key (jour, plateforme, compte_id)
);
create table marketing.fait_organique_post (
  plateforme text not null references marketing.ref_plateforme(code),
  compte_id text not null,
  post_id text not null,
  publie_le timestamptz,
  format text,                 -- reel, carrousel, image, video, short, story
  legende text,
  lien text,
  impressions bigint, portee bigint, vues bigint,
  likes integer, commentaires integer, partages integer, enregistrements integer,
  engagements integer, duree_visionnage_moy numeric,
  releve_le date not null default current_date,
  primary key (plateforme, compte_id, post_id)
);

-- ---------- E-mail ----------
create table marketing.fait_email_campagne (
  plateforme text not null default 'omnisend' references marketing.ref_plateforme(code),
  campagne_id text not null,
  nom text,
  type_envoi text,             -- campagne, automation, booster
  envoye_le timestamptz,
  destinataires integer, delivres integer, ouvertures_uniques integer,
  clics_uniques integer, desabonnements integer, plaintes integer,
  commandes_revendiquees integer, ca_revendique numeric(12,2),
  releve_le date not null default current_date,
  primary key (plateforme, campagne_id)
);

-- ---------- SEO ----------
create table marketing.fait_seo_jour (
  jour date not null,
  site text not null,
  requete text not null default '(total)',
  clics integer, impressions integer, ctr numeric, position numeric,
  primary key (jour, site, requete)
);

-- ---------- Qualité / fiabilité ----------
create table marketing.evenement_qualite (
  id bigserial primary key,
  du date not null,
  au date,                         -- null = en cours
  plateforme text,                 -- null = toutes
  perimetre text not null default 'tout',   -- 'tout' ou identifiant de campagne
  metrique text not null check (metrique in ('sessions','conversions','valeur','attribution','tout')),
  fiabilite text not null check (fiabilite in ('fiable','partiel','non_fiable','anomalie','a_verifier')),
  raison text not null,
  source text,                     -- journal, controle_auto, manuel
  cree_le timestamptz not null default now()
);

create table marketing.controle_ingestion (
  id bigserial primary key,
  execute_le timestamptz not null default now(),
  jour date not null,
  source text not null,
  controle text not null,
  attendu numeric, obtenu numeric, ecart_pct numeric,
  ok boolean not null,
  detail jsonb
);
create index on marketing.controle_ingestion (jour, source);

create table marketing.journal_ingestion (
  id bigserial primary key,
  source text not null,
  du date, au date,
  lignes integer,
  statut text not null check (statut in ('ok','erreur','partiel')),
  message text,
  debut timestamptz not null default now(),
  fin timestamptz
);

-- ---------- Opérations (raccourcis du sélecteur de dates) ----------
create table marketing.operation (
  id bigserial primary key,
  nom text not null,
  du date not null,
  au date not null,
  notes text,
  unique (nom, du)
);
insert into marketing.operation(nom,du,au,notes) values
 ('French Days 2026','2026-09-22','2026-09-28','Paliers -15 % dès 50 €, -20 % dès 75 €, -25 % dès 100 €')
on conflict do nothing;

-- ---------- Préconisations (outil actif) ----------
create table marketing.preconisation (
  id bigserial primary key,
  cree_le timestamptz not null default now(),
  origine text not null check (origine in ('regle','ia','manuel')),
  regle_code text,
  periode_du date, periode_au date,
  plateforme text, perimetre text,
  gravite text not null check (gravite in ('haute','moyenne','info')),
  titre text not null,
  constat text,
  preuve jsonb,
  action_proposee text,
  gain_estime text,
  fiabilite_donnee text,
  statut text not null default 'proposee' check (statut in ('proposee','acceptee','faite','refusee','expiree')),
  decide_par text, decide_le timestamptz,
  verifier_le date,
  effet_mesure text
);
create index on marketing.preconisation (statut, cree_le desc);

-- ---------- RLS : tout fermé, accès uniquement via fonctions definer ----------
do $$
declare t record;
begin
  for t in select tablename from pg_tables where schemaname='marketing' loop
    execute format('alter table marketing.%I enable row level security', t.tablename);
  end loop;
end $$;
grant usage on schema marketing to service_role;
grant all on all tables in schema marketing to service_role;
grant all on all sequences in schema marketing to service_role;
alter default privileges in schema marketing grant all on tables to service_role;
alter default privileges in schema marketing grant all on sequences to service_role;

-- ---------- Accès par board ----------
alter table public.acces_board add column if not exists boards jsonb not null default '{}'::jsonb;
comment on column public.acces_board.boards is 'Rôle par board : {"ventes":"admin","data_center":"lecteur"}';

create or replace function public.role_board(p_board text)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(a.boards->>p_board, case when a.role = 'admin' then 'admin' end)
  from acces_board a where lower(a.email) = lower((select auth.jwt()->>'email'))
$$;
revoke all on function public.role_board(text) from public, anon;
grant execute on function public.role_board(text) to authenticated;

create or replace function public.mon_acces()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((select jsonb_build_object('email', email, 'nom', nom, 'role', role, 'boards', boards)
                   from acces_board where lower(email) = lower((select auth.jwt()->>'email'))), '{}'::jsonb)
$$;
