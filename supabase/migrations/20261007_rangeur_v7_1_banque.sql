-- Rangeur de factures V7.1 (07/10/2026) : le rapprochement reçoit aussi les virements des 13 mois précédents.
-- Une ligne du grand livre déjà payée par un virement antérieur ne peut plus servir à justifier un paiement du mois
-- (cas des commandes répétées au même montant : trois virements 4B Distrib de 31 946,40 €, deux factures dans le livre).
-- Retour arrière : recréer factures_banque_donnees depuis 20261007_rangeur_v7_banque.sql.

create or replace function public.factures_banque_donnees(p_mois text)
returns jsonb language sql stable security definer set search_path = public as $$
  with m as (select to_date(p_mois || '-01', 'YYYY-MM-DD') as debut, (to_date(p_mois || '-01', 'YYYY-MM-DD') + interval '1 month')::date as fin)
  select jsonb_build_object(
    'operations', coalesce((select jsonb_agg(jsonb_build_object('banque', o.banque, 'date', o.date, 'libelle', o.libelle, 'debit', o.debit, 'credit', o.credit) order by o.date, o.id)
      from banque_operations o, m where o.date >= m.debut and o.date < m.fin), '[]'::jsonb),
    'anterieures', coalesce((select jsonb_agg(jsonb_build_object('banque', o.banque, 'date', o.date, 'libelle', o.libelle, 'debit', o.debit, 'credit', 0) order by o.date, o.id)
      from banque_operations o, m where o.debit > 0 and o.date >= m.debut - interval '13 months' and o.date < m.debut), '[]'::jsonb),
    'factures', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'fournisseur', coalesce(fo.nom, a.fournisseur), 'alias', coalesce(to_jsonb(fo.alias), '[]'::jsonb),
        'num_facture', a.num_facture, 'date_facture', a.date_facture, 'montant_ttc', a.montant_ttc, 'statut', a.statut))
      from factures_achats a left join factures_fournisseurs fo on fo.id = a.fournisseur_id, m
      where a.lecture is not null and a.statut <> 'ecartee' and a.date_facture >= m.debut - interval '6 months' and a.date_facture < m.fin), '[]'::jsonb),
    'livre', coalesce((select jsonb_agg(jsonb_build_object('date', g.date, 'libelle', g.libelle, 'debit', g.debit))
      from factures_grand_livre g, m where g.date >= m.debut - interval '13 months' and g.date < m.fin), '[]'::jsonb),
    'regles', coalesce((select jsonb_agg(jsonb_build_object('ordre', r.ordre, 'sens', r.sens, 'motif', r.motif, 'onglet', r.onglet, 'ligne', r.ligne)) from banque_regles r), '[]'::jsonb),
    'correspondances', coalesce((select jsonb_agg(jsonb_build_object('banque', c.banque, 'livre', c.livre)) from banque_correspondances c), '[]'::jsonb))
$$;
revoke execute on function public.factures_banque_donnees(text) from public, anon, authenticated;
grant execute on function public.factures_banque_donnees(text) to service_role;
