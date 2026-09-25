-- Bascule du site pro (16 avril 2026) : l'historique des commandes pros a été recopié dans le nouveau site pro.
-- Chaque commande d'avant la bascule existait donc deux fois : facture d'origine (ancien site, canal prestashop_b2c,
-- numéro de la compta) et copie sur le nouveau site (canal prestashop_pro, même n° de commande, même date, même montant).
-- On garde la facture d'origine : la copie est marquée retenue = false, doublon_de = 'bascule:<n° d'origine>'.
-- Rien n'est supprimé. Appliqué le 25/09/2026 : 5 005 copies (325 012 € en 2024-2025, 155 112 € en 2025-2026).
-- Retour arrière : update ventes_pieces set retenue = true, doublon_de = null where doublon_de like 'bascule:%';
--                  select rafraichir_agregats();

create table if not exists bak_pieces_pro_20260925 as
  select id, retenue, doublon_de from ventes_pieces where canal = 'prestashop_pro';

create or replace function public.marquer_doublons_bascule(p_du date default null, p_au date default null)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare n integer;
begin
  with tot as (
    select p.id, p.canal, p.num_commande, p.date_facture, p.num_facture, p.retenue,
           (select sum(l.total_ligne_ht) from ventes_lignes l where l.piece_id = p.id) montant
    from ventes_pieces p
    where p.canal in ('prestashop_b2c', 'prestashop_pro') and p.num_commande is not null
      and (p_du is null or p.date_facture >= p_du) and (p_au is null or p.date_facture <= p_au)
  ), paires as (
    select distinct on (c.id) c.id, o.num_facture origine
    from tot c
    join tot o on o.canal = 'prestashop_b2c' and o.retenue
      and o.num_commande = c.num_commande and o.date_facture = c.date_facture
      and o.montant is not distinct from c.montant
    where c.canal = 'prestashop_pro'
    order by c.id, o.id
  )
  update ventes_pieces p set retenue = false, doublon_de = 'bascule:' || paires.origine
  from paires where p.id = paires.id and (p.retenue or p.doublon_de is distinct from 'bascule:' || paires.origine);
  get diagnostics n = row_count;
  return n;
end;
$$;

revoke all on function public.marquer_doublons_bascule(date, date) from public, anon, authenticated;

-- Relancée après chaque collecte, pour que les doublons ne reviennent pas quand la collecte réimporte le site pro.
create or replace function public.finaliser_collecte() returns jsonb
language plpgsql security definer set search_path to 'public' set statement_timeout to '15min' as $$
declare a int; b int; d int;
begin
  b := rattacher_skus();
  a := proposer_clients();
  d := marquer_doublons_bascule();
  perform rafraichir_agregats();
  return jsonb_build_object('skus_rattaches', b, 'clients_crees', a, 'doublons_bascule', d);
end $$;
