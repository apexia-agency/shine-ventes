-- Commandes PrestaShop facturées deux fois (même canal, même n° de commande, même client, même date, même montant) :
-- on garde la première facture, les suivantes sont marquées retenue = false, doublon_de = 'double:<n° gardé>'.
-- Une commande à plusieurs factures de montants différents (livraison en plusieurs fois) n'est pas touchée.
-- Appliqué le 25/09/2026 : 16 factures, 557 € en 2024-2025 et 797 € en 2025-2026.
-- Retour arrière : update ventes_pieces set retenue = true, doublon_de = null where doublon_de like 'double:%';
--                  select rafraichir_agregats();

create or replace function public.marquer_doublons_factures()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare n integer;
begin
  with t as (
    select p.id, p.canal, p.num_commande, p.date_facture, p.num_facture, lower(p.client_nom) nom, p.avoir,
           (select sum(l.total_ligne_ht) from ventes_lignes l where l.piece_id = p.id) montant
    from ventes_pieces p
    where p.canal like 'prestashop%' and coalesce(p.num_commande, '') <> ''
      and (p.retenue or p.doublon_de like 'double:%')
  ), rang as (
    select id, first_value(num_facture) over w garde, row_number() over w rn
    from t window w as (partition by canal, num_commande, avoir, nom, date_facture, montant order by id)
  )
  update ventes_pieces p set retenue = false, doublon_de = 'double:' || rang.garde
  from rang where p.id = rang.id and rang.rn > 1 and (p.retenue or p.doublon_de is distinct from 'double:' || rang.garde);
  get diagnostics n = row_count;
  return n;
end;
$$;

revoke all on function public.marquer_doublons_factures() from public, anon, authenticated;

-- Les deux règles de doublons tournent après chaque collecte, avant le recalcul du board.
create or replace function public.finaliser_collecte() returns jsonb
language plpgsql security definer set search_path to 'public' set statement_timeout to '15min' as $$
declare a int; b int; d int; f int;
begin
  b := rattacher_skus();
  a := proposer_clients();
  d := marquer_doublons_bascule();
  f := marquer_doublons_factures();
  perform rafraichir_agregats();
  return jsonb_build_object('skus_rattaches', b, 'clients_crees', a, 'doublons_bascule', d, 'doublons_factures', f);
end $$;
