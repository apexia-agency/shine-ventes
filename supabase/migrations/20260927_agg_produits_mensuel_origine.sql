-- agg_produits_mensuel : origine de chaque unité, « seul » (vendu à l'unité) ou « pack » (issu de l'éclatement d'un pack),
-- pour isoler les packs dans le board Ventes. Les totaux ne changent pas : on ajoute une colonne de découpage.
-- Seules la table mensuelle et la table temporaire t_x de rafraichir_agregats() sont concernées ;
-- agg_produits, agg_ventes_mensuel et les autres agrégats sont calculés exactement comme avant.

alter table agg_produits_mensuel add column if not exists origine text;

do $$
declare d text; avant text;
begin
  d := pg_get_functiondef('public.rafraichir_agregats()'::regprocedure);
  if position('lg.origine' in d) > 0 then return; end if; -- déjà fait

  -- 1. t_x : origine « seul » pour les lignes vendues à l'unité…
  avant := d;
  d := replace(d, E'l.libelle_produit, l.total_ligne_ht, l.quantite\n', E'l.libelle_produit, l.total_ligne_ht, l.quantite, \'seul\'::text origine\n');
  if d = avant then raise exception 'étape 1 : texte introuvable'; end if;
  -- … et « pack » pour les produits issus de l'éclatement
  avant := d;
  d := replace(d, 'l.quantite * k.quantite', E'l.quantite * k.quantite, \'pack\'::text');
  if d = avant then raise exception 'étape 2 : texte introuvable'; end if;
  avant := d;
  d := replace(d, 'lg.total_ligne_ht, lg.quantite,', 'lg.total_ligne_ht, lg.quantite, lg.origine,');
  if d = avant then raise exception 'étape 3 : texte introuvable'; end if;

  -- 2. Table mensuelle : découpée aussi par origine
  avant := d;
  d := replace(d, 'insert into agg_produits_mensuel (mois, exercice, canal, segment, sku, libelle, famille, quantite, ca_ht)',
                  'insert into agg_produits_mensuel (mois, exercice, canal, segment, sku, libelle, famille, quantite, ca_ht, origine)');
  if d = avant then raise exception 'étape 4 : texte introuvable'; end if;
  avant := d;
  d := replace(d, E'sum(quantite), sum(total_ligne_ht)\n  from t_x where produit group by mois, exercice, canal, segment, sku;',
                  E'sum(quantite), sum(total_ligne_ht), origine\n  from t_x where produit group by mois, exercice, canal, segment, sku, origine;');
  if d = avant then raise exception 'étape 5 : texte introuvable'; end if;

  execute d;
end $$;

-- Puis : select rafraichir_agregats();
