-- Noms de clients remplacés par le nom du point relais (appliqué le 28/09/2026, signalé par Robin).
-- Cause : la collecte PrestaShop prenait, à défaut de société sur le compte, la société de l'adresse de LIVRAISON.
-- En point relais (DPD Pickup, Colissimo points de retrait…), c'est le nom du relais (« BUREAU DE POSTE … »,
-- « CONSIGNE PICKUP … », « CARREFOUR CONTACT (FR54429) »…) : ~60 000 factures du site particuliers concernées.
-- L'identité du client (source_client_id = n° de compte) était juste : CA, segments et doublons n'étaient pas faussés.
--
-- 1. Collectes n8n (particuliers et pro) : nouvelle étape « Corriger noms » après « Construire pieces » :
--    société du compte, puis société des adresses SAUF en point relais (seulement l'adresse de facturation si distincte),
--    puis prénom nom du compte. Les livraisons en magasin (« Envoi à Leclerc Auto », « Envoi a Norauto ») gardent
--    la société de l'adresse : ce sont des comptes de magasins.
-- 2. Historique : noms des comptes clients rechargés depuis PrestaShop (workflow « REPRISE - Noms des comptes clients »)
--    puis corriger_noms_relais() : 53 229 factures et 36 757 fiches clients renommées.
--    Gardés tels quels : 7 120 factures dont le nom n'appartient qu'à un client et n'a pas de marque de relais
--    (le plus souvent la vraie société du client : « Eko Nettoyage », « TRASSY FRERES »…).
-- Retour arrière : select restaurer_noms_relais();

create table if not exists noms_comptes_prestashop (
  source text not null,
  source_client_id text not null,
  societe text,
  prenom text,
  nom text,
  maj_le timestamptz not null default now(),
  primary key (source, source_client_id)
);
alter table noms_comptes_prestashop enable row level security;

create or replace function public.charger_noms_comptes(p_source text, p jsonb)
returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if p_source not in ('prestashop_b2c', 'prestashop_pro') then raise exception 'Source inconnue'; end if;
  insert into noms_comptes_prestashop (source, source_client_id, societe, prenom, nom)
  select p_source, e->>'id', nullif(trim(e->>'company'), ''), nullif(trim(e->>'firstname'), ''), nullif(trim(e->>'lastname'), '')
  from jsonb_array_elements(p) e where coalesce(e->>'id', '') <> ''
  on conflict (source, source_client_id) do update set societe = excluded.societe, prenom = excluded.prenom, nom = excluded.nom, maj_le = now();
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.charger_noms_comptes(text, jsonb) from public, anon, authenticated;

create table if not exists bak_noms_relais_20260928 (
  quoi text not null, id text not null, ancien text, nouveau text, primary key (quoi, id)
);
alter table bak_noms_relais_20260928 enable row level security;

create or replace function public.corriger_noms_relais(p_source_client_id text default null)
returns jsonb language plpgsql security definer set search_path = public set statement_timeout = '10min' as $$
declare np int; nc int;
begin
  create temp table t_nr on commit drop as
  with relais_cmd as (
    select distinct source, num_commande from ventes_pieces
    where source like 'prestashop%' and transporteur ~* '(relais|pickup|retrait|consigne)'),
  partage as (
    select source, client_nom, count(distinct source_client_id) nb from ventes_pieces where source like 'prestashop%' group by 1, 2)
  select p.id, p.source, p.source_client_id, p.client_nom ancien,
         nullif(trim(coalesce(n.societe, concat_ws(' ', n.prenom, n.nom))), '') nouveau
  from ventes_pieces p
  join relais_cmd r on r.source = p.source and r.num_commande = p.num_commande
  join noms_comptes_prestashop n on n.source = p.source and n.source_client_id = p.source_client_id
  join partage pa on pa.source = p.source and pa.client_nom = p.client_nom
  where (p_source_client_id is null or p.source_client_id = p_source_client_id)
    and (pa.nb >= 2 or p.client_nom ~* '(\((FR|P)[0-9A-Z]{3,6}\)\s*$|bureau de poste|la poste|consigne|pickup|relais|tabac|presse|carrefour|super u|hyper u|u express|intermarch|leclerc|casino|spar\M|vival|proxi|coccimarket|monoprix|franprix|pressing|laverie|lavomatic|total access|esso|avia|boulangerie|librairie|pharmacie)');
  delete from t_nr where nouveau is null or nouveau = ancien;

  insert into bak_noms_relais_20260928 (quoi, id, ancien, nouveau)
  select 'piece', id::text, ancien, nouveau from t_nr on conflict do nothing;
  update ventes_pieces p set client_nom = t.nouveau from t_nr t where p.id = t.id;
  get diagnostics np = row_count;

  insert into bak_noms_relais_20260928 (quoi, id, ancien, nouveau)
  select distinct on (c.client_id) 'client', c.client_id, c.client_nom, t.nouveau
  from clients c join t_nr t on c.client_id = t.source || ':' || t.source_client_id and c.client_nom = t.ancien
  on conflict do nothing;
  update clients c set client_nom = b.nouveau
  from bak_noms_relais_20260928 b where b.quoi = 'client' and b.id = c.client_id and c.client_nom = b.ancien;
  get diagnostics nc = row_count;
  return jsonb_build_object('factures', np, 'fiches', nc);
end $$;

create or replace function public.restaurer_noms_relais()
returns jsonb language plpgsql security definer set search_path = public as $$
declare np int; nc int;
begin
  update ventes_pieces p set client_nom = b.ancien from bak_noms_relais_20260928 b where b.quoi = 'piece' and p.id = b.id::bigint and p.client_nom = b.nouveau;
  get diagnostics np = row_count;
  update clients c set client_nom = b.ancien from bak_noms_relais_20260928 b where b.quoi = 'client' and c.client_id = b.id and c.client_nom = b.nouveau;
  get diagnostics nc = row_count;
  return jsonb_build_object('factures', np, 'fiches', nc);
end $$;
revoke execute on function public.corriger_noms_relais(text) from public, anon, authenticated;
revoke execute on function public.restaurer_noms_relais() from public, anon, authenticated;

-- Essai sur un client : select corriger_noms_relais('148435');  -- Jérôme Floraud (« BUREAU DE POSTE LA ROCHE SUR YON… »)
-- Puis tout l'historique : select corriger_noms_relais();      -- 53 229 factures, 36 757 fiches
