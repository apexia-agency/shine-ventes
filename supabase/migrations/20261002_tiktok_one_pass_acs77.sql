-- TikTok Shop : la « Microfibre de séchage ONE PASS XXL » est l'ACS77 (confirmé par Jérémy le 02/10/2026 ; produit désactivé pour rupture de stock).
-- Retour arrière : update ventes_lignes set sku = null, ref_source = null where ref_source = 'TIKTOK:ACS77'; select rafraichir_agregats();

update ventes_lignes l
set sku = 'ACS77', ref_source = 'TIKTOK:ACS77'
from ventes_pieces p
where p.id = l.piece_id and p.source = 'tiktok' and l.sku is null and l.libelle_produit = 'SHINE - Microfibre de séchage ONE PASS XXL';

select rafraichir_agregats();
