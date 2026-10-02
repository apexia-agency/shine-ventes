-- Produits arrêtés : ACS67 (Cache roue) confirmé arrêté par Jérémy le 02/10/2026 (il ne reviendra pas).
-- Rappel de lecture de la liste : « Oui définitif » = arrêté ; « Non reviendra » = en rupture pour l'instant, reste à la gamme.
update preco_arrets set note = 'arrêt confirmé par Jérémy le 02/10/2026 (la ligne « Non reviendra » de la liste était une erreur)', maj_le = now() where sku = 'ACS67';
