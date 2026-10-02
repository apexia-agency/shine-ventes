-- APPLIQUÉ dans Supabase le 02/10/2026 (étapes 1 à 5) : 119 pièces, 281 928,01 € HT, 115 pièces détaillées, aucun écart.
-- EBP : septembre 2026 rechargé en entier (demandé par Jérémy le 02/10/2026). La base s'arrêtait au 24/09 (chargement du 25/09) :
-- il manquait les factures et avoirs du 25 au 30/09 (36 550 € HT hors Nexus) et la facture Nexus FA00004605 (190 508,51 € HT, intragroupe).
-- Les données viennent des exports EBP du 02/10 (factures, avoirs, lignes), préparées par outils/ebp/ebp_mois_vers_base.js.
-- Aucune donnée client dans ce fichier : les montants et le détail sont passés aux fonctions existantes de Robin, dans cet ordre :
--   1. fiches des 4 nouveaux clients (ci-dessous) ;
--   2. select importer_montants_ebp('<montants>'::jsonb);            -- une pièce par client pour le mois, total HT net
--   3. mise à jour de la sauvegarde du 25/09 (ci-dessous) : appliquer_ebp_detail repart de cette sauvegarde, il faut donc
--      qu'elle porte les nouveaux totaux, sinon l'ancien total de septembre revient s'ajouter au nouveau ;
--   4. select charger_ebp_detail('<détail>'::jsonb);                  -- lignes par client et par article (remplace celles du mois)
--   5. select appliquer_ebp_detail('2026-09-01', '2026-09-01'); select rafraichir_agregats();
-- Retour arrière : relancer les étapes 2 à 5 avec les montants et le détail arrêtés au 24/09 ; les 30 pièces nouvelles
-- se neutralisent avec update ventes_pieces set retenue = false, doublon_de = 'motif:retour_arriere_fin_septembre'
-- where source = 'ebp' and date_facture = '2026-09-01' and importe_le >= '2026-10-02' and id not in (<pièces d'avant>).

-- 1. Nouveaux clients EBP de fin septembre (segments proposés, sauf Nexus déjà validé par Jérémy)
insert into ebp_clients_import (code, nom, famille, segment, sous_segment, nature, valide) values
  ('CL00803', 'NEXUS', 'Intragroupe', 'INTRAGROUPE', null, 'HORS_PRODUIT', true),
  ('CL00712', 'BOURBON BIKES', 'MDD', 'MDD', 'Bourbon Bikes', 'PRODUIT', false),
  ('CL00805', 'EURL DAM''S GARAGE', 'Revendeurs', 'B2B_REVENDEUR', 'Indépendants', 'PRODUIT', false),
  ('CL00807', 'ALTI''CARS', 'Revendeurs', 'B2B_REVENDEUR', 'Indépendants', 'PRODUIT', false)
on conflict (code) do nothing;
insert into clients (client_id, client_nom, canal_origine, segment, segment_valide, sous_segment, groupe_client)
select 'ebp:' || code, nom, 'ebp', segment, valide, sous_segment, famille from ebp_clients_import
where code in ('CL00803', 'CL00712', 'CL00805', 'CL00807')
on conflict (client_id) do nothing;
insert into clients_sources (source, source_client_id, client_id)
select 'ebp', code, 'ebp:' || code from ebp_clients_import where code in ('CL00803', 'CL00712', 'CL00805', 'CL00807')
on conflict do nothing;

-- 3. Sauvegarde du 25/09 alignée sur les pièces rechargées de septembre (à lancer juste après importer_montants_ebp)
update bak_ebp_lignes_20260925 b
set id = l.id, source_ligne_id = l.source_ligne_id, ref_source = l.ref_source, sku = l.sku, libelle_produit = l.libelle_produit,
    quantite = l.quantite, pu_ht = l.pu_ht, remise_ht = l.remise_ht, total_ligne_ht = l.total_ligne_ht
from ventes_lignes l join ventes_pieces p on p.id = l.piece_id
where b.piece_id = l.piece_id and p.source = 'ebp' and p.date_facture = '2026-09-01';
insert into bak_ebp_lignes_20260925
select l.* from ventes_lignes l join ventes_pieces p on p.id = l.piece_id
where p.source = 'ebp' and p.date_facture = '2026-09-01' and not exists (select 1 from bak_ebp_lignes_20260925 b where b.piece_id = l.piece_id);
insert into bak_ebp_pieces_20260925 (id, frais_port_facture_ht, port_offert)
select p.id, 0, null from ventes_pieces p
where p.source = 'ebp' and p.date_facture = '2026-09-01' and not exists (select 1 from bak_ebp_pieces_20260925 b where b.id = p.id);
