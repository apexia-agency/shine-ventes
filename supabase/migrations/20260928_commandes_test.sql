-- Commandes de test écartées du CA (appliqué le 28/09/2026, validé par Robin).
-- Même principe que les doublons : rien n'est supprimé, la facture est marquée retenue = false.
-- La collecte ne remet jamais retenue à true : la marque tient d'une nuit à l'autre.
--   FA2024-107879  John Test     08/10/2024  196,93 € HT  (CA 2024-2025 : 4 122 607 € → 4 122 410 €)
--   FA2026-026726  Société Test  29/06/2026   27,96 € HT
-- Retour arrière : update ventes_pieces set retenue = true, doublon_de = null where doublon_de like 'test:%';
--                  select rafraichir_agregats();

update ventes_pieces set retenue = false, doublon_de = 'test:commande de test (validé par Robin le 28/09/2026)'
where source = 'prestashop_b2c' and num_facture in ('FA2024-107879', 'FA2026-026726')
  and client_nom in ('John Test', 'Société Test') and retenue;
