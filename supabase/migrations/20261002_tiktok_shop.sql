-- Ventes TikTok Shop SHINE dans le board (demandé par Jérémy le 02/10/2026).
-- Le canal tiktok_b2c existait dans la table canaux mais n'avait aucune vente : la collecte ne ramène pas TikTok.
-- En attendant les codes API (collecte de Robin), les exports « Toutes les commandes » du Seller Center sont chargés
-- par la fonction charger_tiktok ci-dessous, qui s'appuie sur charger_pieces (même circuit que la collecte).
-- Les fichiers sont préparés par outils/tiktok/tiktok_vers_base.js ; aucune donnée n'est dans le dépôt.
--
-- Règles (les mêmes que dans l'export comptable envoyé au cabinet) :
--   - commandes annulées, pas encore expédiées ou remboursées en entier : écartées ;
--   - date de la vente = date d'expédition ; HT = TTC / 1,2 ;
--   - prix avant remise TikTok (reversée par TikTok), moins la remise du vendeur ; remboursement partiel déduit.
-- Une commande rechargée remplace la précédente (clé : source 'tiktok' + numéro de commande).
--
-- Retour arrière : delete from ventes_pieces where source = 'tiktok';  (les lignes suivent)
--                  delete from clients_sources where source = 'tiktok'; delete from clients where canal_origine = 'tiktok';
--                  delete from groupes_segments where source = 'tiktok'; drop function charger_tiktok(text);
--                  select rafraichir_agregats();

insert into groupes_segments (source, groupe_client, segment_propose, note, sous_segment_propose)
values ('tiktok', 'TikTok Shop', 'B2C', 'Acheteurs TikTok Shop SHINE (02/10/2026)', 'TikTok Shop')
on conflict do nothing;

-- p_lignes : une ligne par article de commande, champs séparés par « | » :
--   id_commande | date d'expédition AAAA-MM-JJ | acheteur | code postal | port HT | n° de ligne | SKU | quantité | PU HT | remise HT | total HT | libellé (si SKU vide)
create or replace function public.charger_tiktok(p_lignes text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  with l as (
    select string_to_array(x, '|') a from regexp_split_to_table(p_lignes, E'\n') x where btrim(x) <> ''
  ), p as (
    select a[1] id, a[2] d, a[3] acheteur, a[4] cp, a[5]::numeric port,
      jsonb_agg(jsonb_build_object(
        'source_ligne_id', a[1] || '-' || a[6],
        'ref_source', nullif(a[7], ''),
        'libelle_produit', coalesce((select pr.libelle from produits pr where pr.sku = a[7]), nullif(a[12], ''), nullif(a[7], ''), 'Article TikTok sans référence'),
        'quantite', a[8]::numeric, 'pu_ht', a[9]::numeric, 'remise_ht', a[10]::numeric, 'total_ligne_ht', a[11]::numeric
      ) order by a[6]::int) lignes
    from l group by 1, 2, 3, 4, 5
  )
  select jsonb_agg(jsonb_build_object(
    'source', 'tiktok', 'source_piece_id', id, 'canal', 'tiktok_b2c',
    'num_facture', 'TIKTOK-' || id, 'num_commande', id, 'date_facture', d, 'avoir', false,
    'source_client_id', acheteur, 'client_nom', 'TikTok ' || acheteur, 'groupe_client', 'TikTok Shop',
    'pays_livraison', 'FR', 'cp_livraison', cp, 'frais_port_facture_ht', port, 'port_offert', port = 0,
    'lignes', lignes)) into v
  from p;
  return charger_pieces(coalesce(v, '[]'::jsonb));
end $$;
revoke all on function public.charger_tiktok(text) from public, anon, authenticated;

-- Après chargement : select finaliser_collecte();  (crée les fiches clients, rattache les références, recalcule les agrégats)
