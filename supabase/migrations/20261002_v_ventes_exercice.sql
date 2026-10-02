-- Exercice dans v_ventes (02/10/2026) : la vue calculait l'exercice avec une règle écrite en dur
-- (>= 2025-10-01 → '2025-2026', >= 2024-10-01 → '2024-2025'). Depuis le 01/10/2026, les ventes d'octobre y étaient
-- rangées dans 2025-2026 au lieu de 2026-2027. Les agrégats du board n'étaient pas touchés (ils utilisent exercice_de),
-- mais l'assistant ventes, l'export CSV (v_export_cdc) et les vues v_ca_mensuel / v_conso_composants lisent v_ventes.
-- Correction : même calcul que partout ailleurs, exercice_de(date_facture), valable pour tous les exercices.
-- On part de la définition actuelle de la vue et on ne remplace que l'expression de l'exercice.
do $$
declare d text;
  avant text := E'CASE\n            WHEN (p.date_facture >= ''2025-10-01''::date) THEN ''2025-2026''::text\n            WHEN (p.date_facture >= ''2024-10-01''::date) THEN ''2024-2025''::text\n            ELSE NULL::text\n        END AS exercice';
begin
  d := pg_get_viewdef('public.v_ventes'::regclass);
  if position('exercice_de(p.date_facture) AS exercice' in d) > 0 then return; end if;
  if position(avant in d) = 0 then raise exception 'expression de l''exercice introuvable dans v_ventes'; end if;
  execute 'create or replace view public.v_ventes as ' || replace(d, avant, 'exercice_de(p.date_facture) AS exercice');
end $$;
