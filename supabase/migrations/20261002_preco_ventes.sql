-- APPLIQUÉ dans Supabase le 02/10/2026.
-- Préconisation de vente (board Achats, onglet « Préco de vente ») — demandé par Jérémy le 02/10/2026.
-- Environnement à part : tables preco_*, agrégat agg_preco_chimie, fonction rafraichir_preco() lancée chaque nuit par sa
-- propre tâche. Rien n'est modifié dans la collecte ni dans rafraichir_agregats ; la préco ne fait que lire agg_produits_mensuel,
-- agg_ventes_mensuel, ventes_lignes et packs_composition.
--
-- Méthode chimie : pour chaque produit et chaque mois de l'exercice à venir,
--   prévision = (unités vendues le même mois de l'exercice précédent, packs éclatés
--                − opérations exceptionnelles qui ne se referont pas (preco_exclusions)
--                + correction des ruptures probables chez les particuliers)
--               × taux d'évolution de la famille de clients (objectif de CA ÷ CA réalisé, preco_objectifs).
-- Rupture probable : un mois où les particuliers achètent moins de 40 % de la moyenne du mois d'avant et du mois d'après
-- (moyenne d'au moins 40 unités). Le mois est ramené à cette moyenne ; l'ajout est plafonné à 30 % des ventes de l'année.
--
-- Retour arrière : select cron.unschedule('preco-nuit'); drop function rafraichir_preco();
--                  drop table agg_preco_chimie, preco_laurent, preco_exclusions, preco_objectifs;

create table if not exists preco_objectifs (
  groupe text primary key,              -- PARTICULIERS, REVENDEURS, PROS
  libelle text not null,
  perimetre text not null,              -- ce que couvre le CA réalisé, en clair
  objectif_ca numeric not null,         -- objectif de CA HT produits pour l'exercice à venir
  realise_ca numeric,                   -- CA HT produits de l'exercice précédent (recalculé chaque nuit)
  exercice_ref text,
  maj_le timestamptz default now()
);
insert into preco_objectifs (groupe, libelle, perimetre, objectif_ca) values
  ('PARTICULIERS', 'Particuliers', 'Site particuliers (shine-group.fr), clients particuliers', 3000000),
  ('REVENDEURS', 'Revendeurs', 'Revendeurs (EBP et site) et Jokeriders', 1550000),
  ('PROS', 'Pros', 'Clients pros (site pro, site particuliers, EBP)', 350000)
on conflict (groupe) do nothing;

create table if not exists preco_exclusions (
  id bigint generated always as identity primary key,
  source text not null,                 -- source de la vente (ebp, prestashop_b2c…)
  source_client_id text not null,       -- client concerné
  mois date not null,                   -- mois de la vente à retirer (1er du mois)
  sku_motif text not null default '%',  -- référence de la ligne vendue (motif SQL), pack ou produit
  libelle text not null,
  actif boolean not null default true,
  cree_le timestamptz default now()
);
insert into preco_exclusions (source, source_client_id, mois, sku_motif, libelle)
select 'ebp', 'CL00691', '2025-10-01', 'COL%-IMPLANT', 'Implantation Norauto d''octobre 2025 (colis d''implantation) : ne se refera pas'
where not exists (select 1 from preco_exclusions where source_client_id = 'CL00691' and mois = '2025-10-01');

-- Flux et stock lus dans le tableau de Laurent (copie datée ; la lecture de nuit viendra dans une étape suivante)
create table if not exists preco_laurent (
  sku text not null,
  lu_le date not null,
  flux_mensuel numeric,                 -- unités par mois
  stock numeric,                        -- unités (bidons)
  primary key (sku, lu_le)
);

create table if not exists agg_preco_chimie (
  sku text not null,
  mois date not null,                   -- mois prévu (exercice à venir)
  libelle text,
  contenance_l numeric,
  marque text,
  q_n1 numeric not null default 0,      -- vendu le même mois de l'exercice précédent
  q_retire numeric not null default 0,  -- opérations exceptionnelles retirées
  q_rupture numeric not null default 0, -- ajout pour rupture probable
  q_part numeric not null default 0,    -- prévision par famille de clients
  q_pro numeric not null default 0,
  q_rev numeric not null default 0,
  q_autres numeric not null default 0,
  q_prevu numeric not null default 0,
  note text,
  calcule_le timestamptz default now(),
  primary key (sku, mois)
);

alter table preco_objectifs enable row level security;
alter table preco_exclusions enable row level security;
alter table preco_laurent enable row level security;
alter table agg_preco_chimie enable row level security;
do $$ declare t text; begin
  foreach t in array array['preco_objectifs', 'preco_exclusions', 'preco_laurent', 'agg_preco_chimie'] loop
    execute format('drop policy if exists lecture_associes on %I', t);
    execute format('create policy lecture_associes on %I for select to authenticated using ((select est_associe()))', t);
    execute format('revoke all on %I from anon', t);
    execute format('revoke insert, update, delete, truncate on %I from authenticated', t);
  end loop;
end $$;

create or replace function public.rafraichir_preco()
returns jsonb language plpgsql security definer set search_path = public set statement_timeout = '5min' as $$
declare
  v_du date; v_au date; v_ex text; n int;
begin
  -- Exercice de référence : le dernier exercice terminé (1er octobre → 30 septembre)
  v_au := (make_date(extract(year from current_date)::int - case when extract(month from current_date) >= 10 then 0 else 1 end, 9, 1));
  v_du := (v_au - interval '11 months')::date;
  v_ex := extract(year from v_du)::int || '-' || extract(year from v_au)::int;

  -- CA réalisé par famille sur l'exercice de référence (produits seulement, canaux du CA SHINE)
  update preco_objectifs o set exercice_ref = v_ex, maj_le = now(), realise_ca = (
    select round(coalesce(sum(a.ca_ht), 0)) from agg_ventes_mensuel a
    where a.exercice = v_ex and a.produit and a.dans_ca_shine and case o.groupe
      when 'PARTICULIERS' then a.segment = 'B2C' and a.canal = 'prestashop_b2c'
      when 'REVENDEURS' then a.segment in ('B2B_REVENDEUR', 'MARKETPLACE')
      when 'PROS' then a.segment = 'B2B_PRO' end);

  create temp table t_v on commit drop as
  select a.sku, a.mois,
         case when a.canal = 'myclear' then 'AUTRES' when a.segment = 'B2C' then 'PARTICULIERS' when a.segment = 'B2B_PRO' then 'PROS'
              when a.segment in ('B2B_REVENDEUR', 'MARKETPLACE') then 'REVENDEURS' else 'AUTRES' end g,
         sum(a.quantite) q
  from agg_produits_mensuel a join produits p on p.sku = a.sku
  where a.mois between (v_du - interval '1 month')::date and v_au and p.famille in ('CHIMIE_CONDITIONNEE', 'CHIMIE_PF')
  group by 1, 2, 3;

  -- Opérations exceptionnelles : unités retirées, packs éclatés sur un niveau comme dans les agrégats
  create temp table t_x on commit drop as
  select coalesce(pc.sku_composant, l.sku) sku, date_trunc('month', p.date_facture)::date mois,
         case when c.segment = 'B2C' then 'PARTICULIERS' when c.segment = 'B2B_PRO' then 'PROS'
              when c.segment in ('B2B_REVENDEUR', 'MARKETPLACE') then 'REVENDEURS' else 'AUTRES' end g,
         sum(l.quantite * coalesce(pc.quantite, 1)) q, string_agg(distinct e.libelle, ' ; ') motif
  from preco_exclusions e
  join ventes_pieces p on p.source = e.source and p.source_client_id = e.source_client_id and p.retenue
       and date_trunc('month', p.date_facture)::date = e.mois
  join ventes_lignes l on l.piece_id = p.id and l.sku like e.sku_motif
  left join packs_composition pc on pc.sku_pack = l.sku
  left join clients_sources cs on cs.source = p.source and cs.source_client_id = p.source_client_id
  left join clients c on c.client_id = cs.client_id
  where e.actif and e.mois between v_du and v_au
  group by 1, 2, 3;

  -- Ruptures probables chez les particuliers
  create temp table t_rupt on commit drop as
  with s as (
    select sku, mois, q, lag(q) over w q_avant, lead(q) over w q_apres,
           sum(q) filter (where mois >= v_du) over (partition by sku) q_an
    from (select d.sku, m.mois::date mois, coalesce(v.q, 0) q
          from (select distinct sku from t_v where g = 'PARTICULIERS') d
          cross join generate_series((v_du - interval '1 month')::date, v_au, interval '1 month') m(mois)
          left join t_v v on v.sku = d.sku and v.mois = m.mois::date and v.g = 'PARTICULIERS') z
    window w as (partition by sku order by mois)
  ), c as (
    select sku, mois, q_an, (q_avant + q_apres) / 2 - q ajout
    from s where mois >= v_du and q_avant is not null and q_apres is not null
      and (q_avant + q_apres) / 2 >= 40 and q < 0.4 * (q_avant + q_apres) / 2
  )
  select sku, mois, round(ajout * least(1, 0.3 * q_an / nullif(sum(ajout) over (partition by sku), 0))) ajout from c;

  delete from agg_preco_chimie where true;
  insert into agg_preco_chimie (sku, mois, libelle, contenance_l, marque, q_n1, q_retire, q_rupture, q_part, q_pro, q_rev, q_autres, q_prevu, note)
  select b.sku, (b.mois + interval '1 year')::date, p.libelle, p.contenance_l, p.marque,
         round(sum(b.q)), round(sum(b.x)), round(sum(b.r)),
         coalesce(round(sum(b.prevu) filter (where b.g = 'PARTICULIERS')), 0), coalesce(round(sum(b.prevu) filter (where b.g = 'PROS')), 0),
         coalesce(round(sum(b.prevu) filter (where b.g = 'REVENDEURS')), 0), coalesce(round(sum(b.prevu) filter (where b.g = 'AUTRES')), 0),
         round(sum(b.prevu)),
         nullif(concat_ws(' ; ', max(b.motif), case when sum(b.r) > 0 then 'Rupture probable chez les particuliers : mois ramené à la moyenne des mois voisins' end), '')
  from (
    select k.sku, k.mois, k.g, coalesce(v.q, 0) q, coalesce(x.q, 0) x, coalesce(r.ajout, 0) r, x.motif,
           greatest(0, coalesce(v.q, 0) - coalesce(x.q, 0) + coalesce(r.ajout, 0)) * coalesce(o.objectif_ca / nullif(o.realise_ca, 0), 1) prevu
    from (select sku, mois, g from t_v where mois >= v_du union select sku, mois, g from t_x) k
    left join t_v v on v.sku = k.sku and v.mois = k.mois and v.g = k.g
    left join t_x x on x.sku = k.sku and x.mois = k.mois and x.g = k.g
    left join t_rupt r on r.sku = k.sku and r.mois = k.mois and k.g = 'PARTICULIERS'
    left join preco_objectifs o on o.groupe = k.g
  ) b join produits p on p.sku = b.sku
  where p.famille in ('CHIMIE_CONDITIONNEE', 'CHIMIE_PF')
  group by b.sku, b.mois, p.libelle, p.contenance_l, p.marque;
  get diagnostics n = row_count;
  return jsonb_build_object('exercice_reference', v_ex, 'lignes', n,
    'ruptures', (select count(*) from t_rupt where ajout > 0), 'unites_retirees', (select coalesce(round(sum(q)), 0) from t_x));
end $$;
revoke all on function public.rafraichir_preco() from public, anon, authenticated;

-- Chaque nuit à 5 h 40 (heure UTC), après la collecte et le recalcul des agrégats
select cron.schedule('preco-nuit', '40 5 * * *', 'select public.rafraichir_preco()');
select rafraichir_preco();
