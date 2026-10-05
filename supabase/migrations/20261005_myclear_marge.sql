-- MyClear : vraie marge de la marque (onglet MyClear du board).
-- Marge = CA HT + port payé par le client + aide de TikTok sur le port
--       − coût des produits (saisi par Robin sur le board)
--       − transport Colissimo (coût moyen d'un colis à domicile, lu dans les factures Colissimo)
--       − frais TikTok Shop (commission, affiliés, promotions, éco-participation, retours), puis la pub GMV Max à part.
-- Les ventes viennent des agrégats déjà en place (agg_produits_mensuel, agg_commandes_mensuel, canal myclear).
-- Retour arrière : drop function myclear_marge, myclear_definir_cout, myclear_charger_frais_tiktok, myclear_cout_colis ;
--                  drop table myclear_couts, myclear_alias_sku, myclear_frais_tiktok, myclear_imports_tiktok, myclear_parametres.

-- 1. Coût de revient HT par référence (produit ou pack), saisi sur le board
create table if not exists myclear_couts (
  sku text primary key,
  cout_ht numeric(10,2) not null check (cout_ht >= 0),
  maj_le timestamptz not null default now(),
  maj_par text
);

-- 2. Références sans code venues de Shopify, rattachées au bon pack
create table if not exists myclear_alias_sku (
  sku_source text primary key,
  sku text not null
);
insert into myclear_alias_sku (sku_source, sku) values
  ('MYCLEAR:Pack jantes parfaites', 'MCP01-TT'),
  ('MYCLEAR:Pack transformation complète', 'MCP02-TT'),
  ('MYCLEAR:Pack lavage intérieur', 'MCP03-TT'),
  ('MYCLEAR:Pack lavage extérieur', 'MCP04-TT')
on conflict (sku_source) do nothing;

-- 3. Frais TikTok Shop par mois de commande, venus de l'export Finance → Relevés (outils/myclear/frais_tiktok.mjs)
--    montant signé : négatif = payé par MyClear, positif = versé par TikTok (aide sur le port)
create table if not exists myclear_frais_tiktok (
  mois_releve date not null,
  mois date not null,
  poste text not null,
  montant numeric(12,2) not null,
  importe_le timestamptz not null default now(),
  primary key (mois_releve, mois, poste)
);
create table if not exists myclear_imports_tiktok (
  id serial primary key,
  releves_du date not null,
  releves_au date not null,
  importe_le timestamptz not null default now(),
  importe_par text
);

-- 4. Réglages (coût d'un colis imposé à la main, sinon lu dans les factures Colissimo)
create table if not exists myclear_parametres (
  cle text primary key,
  valeur numeric,
  note text
);
insert into myclear_parametres (cle, valeur, note) values
  ('cout_colis_ht_force', null, 'Coût HT d''un colis imposé à la main ; vide = moyenne des factures Colissimo du mois'),
  ('cout_colis_ht_defaut', 7.20, 'Coût HT d''un colis si aucune facture Colissimo n''est chargée')
on conflict (cle) do nothing;

-- Sécurité : lecture pour les associés du board, écriture uniquement par les fonctions ci-dessous
alter table myclear_couts enable row level security;
alter table myclear_alias_sku enable row level security;
alter table myclear_frais_tiktok enable row level security;
alter table myclear_imports_tiktok enable row level security;
alter table myclear_parametres enable row level security;
revoke all on myclear_couts, myclear_alias_sku, myclear_frais_tiktok, myclear_imports_tiktok, myclear_parametres from anon, authenticated;
revoke all on sequence myclear_imports_tiktok_id_seq from anon, authenticated;

-- Coût moyen HT d'un colis Colissimo à domicile (jusqu'à 2 kg) pour un mois :
-- le mois lui-même s'il a au moins 200 colis facturés, sinon le dernier mois connu avant, sinon la valeur par défaut.
create or replace function myclear_cout_colis(p_mois date)
returns numeric language sql stable security definer set search_path to 'public' as $$
  select coalesce(
    (select valeur from myclear_parametres where cle = 'cout_colis_ht_force'),
    (select round(avg(transport + coalesce(gasoil, 0) + coalesce(taxes, 0) + coalesce(annexes, 0)), 2)
       from transport_colis
      where transporteur = 'Colissimo' and mode = 'coli_dom' and poids_kg <= 2
        and date_trunc('month', date_envoi) = (
          select max(m) from (
            select date_trunc('month', date_envoi) m from transport_colis
             where transporteur = 'Colissimo' and mode = 'coli_dom' and poids_kg <= 2
               and date_envoi < (p_mois + interval '1 month')
             group by 1 having count(*) >= 200) x)),
    (select valeur from myclear_parametres where cle = 'cout_colis_ht_defaut'));
$$;

-- Saisie d'un coût produit depuis le board (admin ou valideur). Coût vide = on retire le coût.
create or replace function myclear_definir_cout(p_sku text, p_cout numeric)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r text; qui text := (select auth.jwt()->>'email');
begin
  select role into r from acces_board where lower(email) = lower(qui);
  if r is null or r not in ('valideur', 'admin') then raise exception 'Accès refusé'; end if;
  if p_sku is null or trim(p_sku) = '' then raise exception 'Référence vide'; end if;
  if p_cout is null then
    delete from myclear_couts where sku = p_sku;
  else
    if p_cout < 0 or p_cout > 1000 then raise exception 'Coût hors limites'; end if;
    insert into myclear_couts (sku, cout_ht, maj_le, maj_par) values (p_sku, round(p_cout, 2), now(), qui)
    on conflict (sku) do update set cout_ht = excluded.cout_ht, maj_le = now(), maj_par = excluded.maj_par;
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- Chargement des frais TikTok (lancé par Claude ou dans l'éditeur SQL) : chaque mois de relevé présent remplace l'ancien.
create or replace function myclear_charger_frais_tiktok(p_du date, p_au date, p_lignes jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare n int; qui text := coalesce((select auth.jwt()->>'email'), current_user);
begin
  if (select auth.jwt()->>'email') is not null
     and coalesce((select role from acces_board where lower(email) = lower(qui)), '') <> 'admin' then
    raise exception 'Accès refusé';
  end if;
  delete from myclear_frais_tiktok
   where mois_releve in (select distinct (l->>'mois_releve')::date from jsonb_array_elements(p_lignes) l);
  insert into myclear_frais_tiktok (mois_releve, mois, poste, montant)
  select (l->>'mois_releve')::date, (l->>'mois')::date, l->>'poste', (l->>'montant')::numeric
    from jsonb_array_elements(p_lignes) l;
  get diagnostics n = row_count;
  insert into myclear_imports_tiktok (releves_du, releves_au, importe_par) values (p_du, p_au, qui);
  return jsonb_build_object('ok', true, 'lignes', n);
end $$;
revoke execute on function myclear_charger_frais_tiktok(date, date, jsonb) from public, anon, authenticated;
revoke execute on function myclear_cout_colis(date) from public, anon;
revoke execute on function myclear_definir_cout(text, numeric) from public, anon;

-- Marge MyClear sur une période : par mois, par produit, et la liste des coûts à saisir.
create or replace function myclear_marge(p_du date, p_au date)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare res jsonb;
begin
  if not est_associe() then raise exception 'Accès refusé'; end if;
  with ventes as (
    select a.mois, coalesce(al.sku, a.sku) sku, max(a.libelle) libelle, sum(a.quantite) qte, sum(a.ca_ht) ca
      from agg_produits_mensuel a left join myclear_alias_sku al on al.sku_source = a.sku
     where a.canal = 'myclear' and a.mois between p_du and p_au
     group by 1, 2
  ), ventes_cout as (
    select v.*, c.cout_ht, v.qte * c.cout_ht cout_produits from ventes v left join myclear_couts c on c.sku = v.sku
  ), cmd as (
    select mois, sum(nb_factures) colis, sum(port_ht) port from agg_commandes_mensuel
     where canal = 'myclear' and mois between p_du and p_au group by 1
  ), frais as (
    select mois, poste, sum(montant) montant from myclear_frais_tiktok where mois between p_du and p_au group by 1, 2
  ), imp as (
    select min(releves_du) du, max(releves_au) au from myclear_imports_tiktok
  ), mois as (
    select m.mois,
      round(sum(v.ca), 2) ca_ht,
      round(sum(v.cout_produits), 2) cout_produits,
      round(sum(v.ca) filter (where v.cout_ht is null and v.sku <> 'AJUSTEMENT_AVOIR'), 2) ca_sans_cout,
      coalesce(max(c.colis), 0) colis, round(coalesce(max(c.port), 0), 2) port_client_ht,
      myclear_cout_colis(m.mois) cout_colis_ht
    from (select distinct mois from ventes) m
    join ventes_cout v on v.mois = m.mois
    left join cmd c on c.mois = m.mois
    group by m.mois
  ), mois_frais as (
    select mo.*,
      round(mo.colis * mo.cout_colis_ht, 2) transport_ht,
      coalesce((select jsonb_object_agg(poste, montant) from frais f where f.mois = mo.mois), '{}'::jsonb) frais,
      coalesce((select sum(montant) from frais f where f.mois = mo.mois and poste not in ('pub_gmv_max')), 0) frais_tiktok,
      coalesce((select sum(montant) from frais f where f.mois = mo.mois and poste = 'pub_gmv_max'), 0) pub,
      (select mo.mois >= date_trunc('month', du) + interval '1 month' and mo.mois + interval '1 month 5 days' <= au from imp) frais_complets
    from mois mo
  )
  select jsonb_build_object(
    'mois', coalesce((select jsonb_agg(to_jsonb(x) || jsonb_build_object(
        'marge_ht', round(x.ca_ht + x.port_client_ht + x.frais_tiktok - coalesce(x.cout_produits, 0) - x.transport_ht, 2),
        'marge_apres_pub_ht', round(x.ca_ht + x.port_client_ht + x.frais_tiktok + x.pub - coalesce(x.cout_produits, 0) - x.transport_ht, 2))
        order by x.mois) from mois_frais x), '[]'::jsonb),
    'produits', coalesce((select jsonb_agg(p order by p.ca desc) from (
        select sku, max(libelle) libelle, sum(qte) qte, round(sum(ca), 2) ca, max(cout_ht) cout_ht, round(sum(cout_produits), 2) cout_produits
          from ventes_cout where sku <> 'AJUSTEMENT_AVOIR' group by sku) p), '[]'::jsonb),
    'couts', coalesce((select jsonb_agg(jsonb_build_object('sku', sku, 'cout_ht', cout_ht, 'maj_le', maj_le, 'maj_par', maj_par)) from myclear_couts), '[]'::jsonb),
    'frais_tiktok_du', (select du from imp), 'frais_tiktok_au', (select au from imp)
  ) into res;
  return res;
end $$;
revoke execute on function myclear_marge(date, date) from public, anon;
grant execute on function myclear_marge(date, date) to authenticated;
grant execute on function myclear_definir_cout(text, numeric) to authenticated;
grant execute on function myclear_cout_colis(date) to authenticated;
