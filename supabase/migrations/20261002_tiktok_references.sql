-- TikTok Shop : articles vendus sans référence vendeur dans l'export (34 unités), rattachés à leur produit d'après le libellé.
-- Reste à trancher par Jérémy : « Microfibre de séchage ONE PASS XXL » (37 unités, 552 € HT) — ACS23, ACS8 ou ACS77 ?
-- Le script outils/tiktok/tiktok_vers_base.js fait le même rattachement pour les prochains chargements.
-- Retour arrière : update ventes_lignes set sku = null, ref_source = null where ref_source like 'TIKTOK:%'; select rafraichir_agregats();

update ventes_lignes l
set sku = m.sku, ref_source = 'TIKTOK:' || m.sku,
    contenance_unitaire = coalesce(l.contenance_unitaire, (select pr.contenance_l from produits pr where pr.sku = m.sku))
from ventes_pieces p,
     (values ('SHINE - Cire Express - Quick Detailer - 450ml', 'AS49-450'),
             ('SHINE - Gant Yéti', 'ACS21'),
             ('SHINE - Nettoyant Vitre - 450mL', 'AS21-450'),
             ('SHINE - Sac de transport detailing - Rangement produits auto', 'ACS82')) m(libelle, sku)
where p.id = l.piece_id and p.source = 'tiktok' and l.sku is null and l.libelle_produit = m.libelle;

select rafraichir_agregats();
