-- Ventes par produit et par mois (même calcul que agg_produits, packs éclatés compris), pour filtrer le board
-- Ventes sur une période à l'intérieur de l'exercice. Ajout pur : rien d'existant n'est modifié ni supprimé.
-- rafraichir_agregats() la remplit à chaque recalcul, à partir de la même table temporaire t_x que agg_produits.

create table if not exists agg_produits_mensuel (
  mois date not null,
  exercice text not null,
  canal text,
  segment text,
  sku text,
  libelle text,
  famille text,
  quantite numeric,
  ca_ht numeric
);
create index if not exists agg_produits_mensuel_ex_mois on agg_produits_mensuel (exercice, mois);

-- Même accès que agg_produits : lecture réservée aux associés
alter table agg_produits_mensuel enable row level security;
drop policy if exists lecture_associes on agg_produits_mensuel;
create policy lecture_associes on agg_produits_mensuel for select to authenticated using ((select est_associe()));

-- Ajout dans rafraichir_agregats() : on relit sa définition actuelle et on y insère seulement
-- le vidage et le remplissage de la nouvelle table (le reste de la fonction ne change pas).
do $$
declare d text;
begin
  d := pg_get_functiondef('public.rafraichir_agregats()'::regprocedure);
  if position('agg_produits_mensuel' in d) > 0 then return; end if; -- déjà fait
  d := replace(d,
    'truncate agg_ventes_mensuel, agg_commandes_mensuel, agg_produits, agg_clients, agg_jour;',
    'truncate agg_ventes_mensuel, agg_commandes_mensuel, agg_produits, agg_produits_mensuel, agg_clients, agg_jour;');
  d := replace(d,
    '  insert into agg_commandes_mensuel',
    E'  -- Ventes par produit et par mois (période choisie dans le board)\n' ||
    E'  insert into agg_produits_mensuel (mois, exercice, canal, segment, sku, libelle, famille, quantite, ca_ht)\n' ||
    E'  select mois, exercice, canal, segment, sku, max(libelle), max(famille), sum(quantite), sum(total_ligne_ht)\n' ||
    E'  from t_x where produit group by mois, exercice, canal, segment, sku;\n\n' ||
    E'  insert into agg_commandes_mensuel');
  -- 2 occurrences attendues : le vidage et le remplissage
  if (length(d) - length(replace(d, 'agg_produits_mensuel', ''))) / length('agg_produits_mensuel') <> 2 then
    raise exception 'rafraichir_agregats : texte attendu introuvable, fonction non modifiée';
  end if;
  execute d;
end $$;

-- Puis : select rafraichir_agregats();
