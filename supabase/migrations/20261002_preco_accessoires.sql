-- Préco de vente : accessoires (demandé par Jérémy le 02/10/2026), en deux sections : import (Chine) et intra (France, Europe).
--   1. la prévision (agg_preco_chimie, nom gardé) couvre aussi la famille ACCESSOIRE_PF ; colonne famille ajoutée ;
--   2. preco_accessoires : copie de l'onglet « Accessoires » du tableau de Laurent (stock, en commande, flux, fournisseur,
--      délai, conditionnement d'appro) et de sa préco conteneur (première commande) pour comparer ;
--   3. preco_fournisseurs : origine de chaque fournisseur (IMPORT = Chine, INTRA = le reste).
-- Les copies du tableau de Laurent sont chargées hors du dépôt.
-- Retour arrière : drop table preco_accessoires, preco_fournisseurs; alter table agg_preco_chimie drop column famille;
--                  puis réappliquer rafraichir_preco (20261002_preco_ventes.sql + _v2.sql).

alter table agg_preco_chimie add column if not exists famille text;

create table if not exists preco_fournisseurs (
  fournisseur text primary key,
  origine text not null check (origine in ('IMPORT', 'INTRA')),
  note text
);
insert into preco_fournisseurs (fournisseur, origine, note) values
  ('TONYIN', 'IMPORT', 'Chine'), ('DEYUAN TEXTILE', 'IMPORT', 'Chine'),
  ('JIANGSU DONGYAN ABRASIVE TOOLS Co Ltd', 'IMPORT', 'Chine'), ('SHENZHEN KASI TENG TECHNOLOGY CO. LTD', 'IMPORT', 'Chine'),
  ('AMiO Sp. z o.o.', 'INTRA', 'Pologne'), ('AROMA', 'INTRA', null), ('DEWITTE', 'INTRA', null), ('4B DISTRIBUTION', 'INTRA', null),
  ('PLASTIC BILLAT', 'INTRA', null), ('SCHOLL CONCEPTS SARL', 'INTRA', null), ('SEKO France', 'INTRA', null), ('FIDEL FILLAUD', 'INTRA', null)
on conflict (fournisseur) do nothing;

create table if not exists preco_accessoires (
  sku text not null,
  lu_le date not null,
  designation text,
  stock numeric,
  en_commande numeric,
  flux_mensuel numeric,        -- flux du tableau de Laurent
  fournisseur text,
  delai_sem numeric,           -- délai moyen du fournisseur, en semaines
  cond_appro numeric,          -- quantité par carton ou palette de commande
  pru numeric,
  preco_laurent numeric,       -- première commande de sa préco conteneur
  preco_laurent_date text,
  primary key (sku, lu_le)
);
do $$ declare t text; begin
  foreach t in array array['preco_fournisseurs', 'preco_accessoires'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists lecture_associes on %I', t);
    execute format('create policy lecture_associes on %I for select to authenticated using ((select est_associe()))', t);
    execute format('revoke all on %I from anon', t);
    execute format('revoke insert, update, delete, truncate on %I from authenticated', t);
  end loop;
end $$;

-- rafraichir_preco : on part de la définition actuelle, on ajoute la famille des accessoires et la colonne famille
do $$
declare d text; d2 text;
begin
  select pg_get_functiondef('public.rafraichir_preco()'::regprocedure) into d;
  d2 := replace(d, 'p.famille in (''CHIMIE_CONDITIONNEE'', ''CHIMIE_PF'')', 'p.famille in (''CHIMIE_CONDITIONNEE'', ''CHIMIE_PF'', ''ACCESSOIRE_PF'')');
  d2 := replace(d2, 'get diagnostics n = row_count;', 'get diagnostics n = row_count;
  update agg_preco_chimie a set famille = p.famille from produits p where p.sku = a.sku;');
  if d2 = d or position('ACCESSOIRE_PF' in d) > 0 then raise exception 'rafraichir_preco : déjà modifiée ou lignes introuvables'; end if;
  execute d2;
end $$;
select rafraichir_preco();
