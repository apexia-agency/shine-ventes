-- Board Transport : les envois DPD multi-colis sont rangés dans la tranche de poids d'un colis (poids de l'envoi ÷ nombre de colis),
-- et non plus du poids total de l'envoi. Même règle que transport-lecteurs.js pour les prochains dépôts.
-- Retour arrière : même requête avec poids_kg au lieu de poids_kg / colis.
update public.transport_colis set tranche = case
    when poids_kg / colis < 1 then '0-1' when poids_kg / colis < 2 then '1-2' when poids_kg / colis < 5 then '2-5'
    when poids_kg / colis < 10 then '5-10' when poids_kg / colis < 30 then '10-30' else '30+' end
where transporteur = 'DPD' and colis > 1 and poids_kg > 0;
