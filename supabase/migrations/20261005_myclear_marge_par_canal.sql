-- MyClear : marge détaillée TikTok Shop / boutique en ligne / autres canaux.
-- myclear_marge lit désormais les factures MyClear (ventes_pieces / ventes_lignes, retenue = true) au lieu des agrégats :
-- le groupe de la commande (« TikTok Shop », « Boutique en ligne », autres) n'existe que là, et toutes les lignes comptent
-- (les agrégats laissent de côté les références classées famille AUTRE, ex. MCA-43, MCA-5, et l'ajustement d'avoir : ≤ 20 € par mois).
-- Frais TikTok et pub GMV Max : imputés au canal TikTok. Transport : commandes du canal × coût moyen d'un colis Colissimo.
-- Chaque mois porte un objet « canaux » : { tiktok | boutique | autres : ca_ht, port_client_ht, colis, cout_produits, ca_sans_cout,
-- transport_ht, frais_tiktok, pub, marge_ht, marge_apres_pub_ht }.
-- Retour arrière : réappliquer la fonction de 20261005_myclear_marge.sql puis 20261005_myclear_frais_complets.sql.
create or replace function myclear_marge(p_du date, p_au date)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare res jsonb;
begin
  if not est_associe() then raise exception 'Accès refusé'; end if;
  with pieces as (
    select p.id, p.avoir, p.frais_port_facture_ht, date_trunc('month', p.date_facture)::date mois,
           case p.groupe_client when 'TikTok Shop' then 'tiktok' when 'Boutique en ligne' then 'boutique' else 'autres' end canal
      from ventes_pieces p
     where p.canal = 'myclear' and p.retenue and p.date_facture between p_du and p_au
  ), ventes as (
    select pc.mois, pc.canal, coalesce(al.sku, l.sku) sku, max(coalesce(pr.libelle, l.libelle_produit)) libelle,
           sum(l.quantite) qte, sum(l.total_ligne_ht) ca
      from pieces pc join ventes_lignes l on l.piece_id = pc.id
      left join myclear_alias_sku al on al.sku_source = l.sku
      left join produits pr on pr.sku = coalesce(al.sku, l.sku)
     group by 1, 2, 3
  ), ventes_cout as (
    select v.*, c.cout_ht, v.qte * c.cout_ht cout_produits from ventes v left join myclear_couts c on c.sku = v.sku
  ), cmd as (
    select mois, canal, count(*) filter (where not avoir) colis, sum(coalesce(frais_port_facture_ht, 0)) port from pieces group by 1, 2
  ), canal_mois as (
    select coalesce(v.mois, c.mois) mois, coalesce(v.canal, c.canal) canal,
           coalesce(v.ca, 0) ca_ht, v.cout_produits, v.ca_sans_cout, coalesce(c.colis, 0) colis, coalesce(c.port, 0) port_client_ht
      from (select mois, canal, round(sum(ca), 2) ca, round(sum(cout_produits), 2) cout_produits,
                   round(sum(ca) filter (where cout_ht is null and sku <> 'AJUSTEMENT_AVOIR'), 2) ca_sans_cout
              from ventes_cout group by 1, 2) v
      full join cmd c on c.mois = v.mois and c.canal = v.canal
  ), frais as (
    select mois, poste, sum(montant) montant from myclear_frais_tiktok where mois between p_du and p_au group by 1, 2
  ), imp as (
    select min(releves_du) du, max(releves_au) au from myclear_imports_tiktok
  ), canal_calc as (
    select cm.*, myclear_cout_colis(cm.mois) cout_colis_ht,
           round(cm.colis * myclear_cout_colis(cm.mois), 2) transport_ht,
           case when cm.canal = 'tiktok' then coalesce((select sum(montant) from frais f where f.mois = cm.mois and poste <> 'pub_gmv_max'), 0) else 0 end frais_tiktok,
           case when cm.canal = 'tiktok' then coalesce((select sum(montant) from frais f where f.mois = cm.mois and poste = 'pub_gmv_max'), 0) else 0 end pub
      from canal_mois cm
  ), canal_marge as (
    select cc.*, round(ca_ht + port_client_ht + frais_tiktok - coalesce(cout_produits, 0) - transport_ht, 2) marge_ht,
           round(ca_ht + port_client_ht + frais_tiktok + pub - coalesce(cout_produits, 0) - transport_ht, 2) marge_apres_pub_ht
      from canal_calc cc
  ), mois as (
    select m.mois,
      round(sum(ca_ht), 2) ca_ht, round(sum(cout_produits), 2) cout_produits, round(sum(ca_sans_cout), 2) ca_sans_cout,
      sum(colis) colis, round(sum(port_client_ht), 2) port_client_ht, max(cout_colis_ht) cout_colis_ht,
      round(sum(transport_ht), 2) transport_ht, sum(frais_tiktok) frais_tiktok, sum(pub) pub,
      sum(marge_ht) marge_ht, sum(marge_apres_pub_ht) marge_apres_pub_ht,
      coalesce((select jsonb_object_agg(poste, montant) from frais f where f.mois = m.mois), '{}'::jsonb) frais,
      myclear_frais_complets(m.mois) frais_complets,
      jsonb_object_agg(m.canal, jsonb_build_object('ca_ht', ca_ht, 'port_client_ht', round(port_client_ht, 2), 'colis', colis,
        'cout_produits', cout_produits, 'ca_sans_cout', ca_sans_cout, 'transport_ht', transport_ht, 'frais_tiktok', frais_tiktok,
        'pub', pub, 'marge_ht', marge_ht, 'marge_apres_pub_ht', marge_apres_pub_ht)) canaux
    from canal_marge m
    group by m.mois
  )
  select jsonb_build_object(
    'mois', coalesce((select jsonb_agg(to_jsonb(x) order by x.mois) from mois x), '[]'::jsonb),
    'produits', coalesce((select jsonb_agg(p order by p.ca desc) from (
        select sku, max(libelle) libelle, sum(qte) qte, round(sum(ca), 2) ca, max(cout_ht) cout_ht, round(sum(cout_produits), 2) cout_produits,
               sum(qte) filter (where canal = 'tiktok') qte_tiktok, round(sum(ca) filter (where canal = 'tiktok'), 2) ca_tiktok
          from ventes_cout where sku <> 'AJUSTEMENT_AVOIR' group by sku) p), '[]'::jsonb),
    'couts', coalesce((select jsonb_agg(jsonb_build_object('sku', sku, 'cout_ht', cout_ht, 'maj_le', maj_le, 'maj_par', maj_par)) from myclear_couts), '[]'::jsonb),
    'frais_tiktok_du', (select du from imp), 'frais_tiktok_au', (select au from imp)
  ) into res;
  return res;
end $$;
revoke execute on function myclear_marge(date, date) from public, anon;
grant execute on function myclear_marge(date, date) to authenticated;
