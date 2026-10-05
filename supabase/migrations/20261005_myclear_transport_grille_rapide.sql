-- MyClear : même calcul que 20261005_myclear_transport_grille.sql, mais la surtaxe gasoil est lue une fois par mois et par canal
-- (et non pour chaque commande : dépassement du temps limite). Commande : tarif de la grille selon son poids ;
-- mois : somme des tarifs × (1 + surtaxe gasoil) + nombre de colis × taxe.
do $$
declare d text := pg_get_functiondef('public.myclear_marge(date,date)'::regprocedure);
  r text[][] := array[
    array['sum(case when pc.avoir then 0 else myclear_prix_colis(w.poids, pc.mois) end) transport',
          'sum(case when pc.avoir then 0 else (select tarif_ht from myclear_grille_transport where poids_max >= coalesce(w.poids, 0) order by poids_max limit 1) end) transport'],
    array['round(cm.transport_cmd / nullif(cm.colis, 0), 2) cout_colis_ht,
           round(cm.transport_cmd, 2) transport_ht,',
          'round((cm.transport_cmd * (1 + g.taux) + cm.colis * g.taxe) / nullif(cm.colis, 0), 2) cout_colis_ht,
           round(cm.transport_cmd * (1 + g.taux) + cm.colis * g.taxe, 2) transport_ht,'],
    array['      from canal_mois cm
  ), canal_marge', '      from canal_mois cm, lateral myclear_gasoil(cm.mois) g
  ), canal_marge']];
  i int;
begin
  for i in 1 .. array_length(r, 1) loop
    if position(r[i][1] in d) = 0 then raise exception 'Expression % introuvable dans myclear_marge', i; end if;
    d := replace(d, r[i][1], r[i][2]);
  end loop;
  execute d;
end $$;
