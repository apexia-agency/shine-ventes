-- APPLIQUÉ dans Supabase le 02/10/2026 ; vérifié : objectif Pros 350 000 → 400 000 fait passer la prévision pros de 30 140 à 34 637 unités sur 12 mois (remis à 350 000).
-- Préco de vente : modifier un objectif depuis le board renvoyait une erreur (« UPDATE requires a WHERE clause »).
-- Les appels venant du board passent par une protection qui refuse toute mise à jour sans condition ; la ligne de
-- rafraichir_preco qui recalcule le CA réalisé des objectifs n'en avait pas. On part de la définition actuelle de la
-- fonction et on ajoute seulement « where true » à cette ligne.
do $$
declare d text; d2 text;
begin
  select pg_get_functiondef('public.rafraichir_preco()'::regprocedure) into d;
  d2 := replace(d, 'when ''PROS'' then a.segment = ''B2B_PRO'' end);', 'when ''PROS'' then a.segment = ''B2B_PRO'' end) where true;');
  if d2 = d then raise exception 'rafraichir_preco : ligne des objectifs introuvable (déjà corrigée ?)'; end if;
  execute d2;
end $$;
