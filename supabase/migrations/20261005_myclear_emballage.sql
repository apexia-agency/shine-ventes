-- MyClear : emballage déduit de la marge, 0,20 € HT en moyenne par commande expédiée (enveloppe ou carton, choix de Robin le 05/10/2026).
-- Réglage : myclear_parametres « emballage_ht_commande ». Nouveau champ emballage_ht par mois et par canal.
-- Retour arrière : update myclear_parametres set valeur = 0 where cle = 'emballage_ht_commande'.
insert into myclear_parametres (cle, valeur, note) values
  ('emballage_ht_commande', 0.20, 'Emballage HT moyen par commande expédiée (enveloppe ou carton)')
on conflict (cle) do update set valeur = excluded.valeur, note = excluded.note;

do $$
declare d text := pg_get_functiondef('public.myclear_marge(date,date)'::regprocedure);
  r text[][] := array[
    array['round(cm.transport_cmd * (1 + g.taux) + cm.colis * g.taxe, 2) transport_ht,',
          'round(cm.transport_cmd * (1 + g.taux) + cm.colis * g.taxe, 2) transport_ht,
           round(cm.colis * coalesce((select valeur from myclear_parametres where cle = ''emballage_ht_commande''), 0), 2) emballage_ht,'],
    array['- coalesce(cout_produits, 0) - transport_ht, 2) marge_ht', '- coalesce(cout_produits, 0) - transport_ht - emballage_ht, 2) marge_ht'],
    array['- coalesce(cout_produits, 0) - transport_ht, 2) marge_apres_pub_ht', '- coalesce(cout_produits, 0) - transport_ht - emballage_ht, 2) marge_apres_pub_ht'],
    array['round(sum(transport_ht), 2) transport_ht,', 'round(sum(transport_ht), 2) transport_ht, round(sum(emballage_ht), 2) emballage_ht,'],
    array['''transport_ht'', transport_ht,', '''transport_ht'', transport_ht, ''emballage_ht'', emballage_ht,']];
  i int;
begin
  for i in 1 .. array_length(r, 1) loop
    if position(r[i][1] in d) = 0 then raise exception 'Expression % introuvable dans myclear_marge', i; end if;
    d := replace(d, r[i][1], r[i][2]);
  end loop;
  execute d;
end $$;
