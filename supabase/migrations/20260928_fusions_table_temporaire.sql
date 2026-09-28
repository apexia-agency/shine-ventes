-- Appliqué le 28/09/2026.
-- finaliser_collecte appelle fusionner_clients_tva puis fusionner_clients_email dans la même transaction.
-- Les deux créaient la table temporaire t_fus : la 2e plantait (« relation t_fus already exists »),
-- ce qui arrêtait la collecte de nuit avant rafraichir_agregats (board figé depuis le 27/09 au soir).
-- Correction : chaque fonction supprime t_fus avant de la recréer. Rien d'autre ne change.
do $$
declare f text; d text;
begin
  foreach f in array array['public.fusionner_clients_tva(text)', 'public.fusionner_clients_email(text)'] loop
    d := pg_get_functiondef(f::regprocedure);
    if position('drop table if exists t_fus' in d) > 0 then continue; end if;
    if position('create temp table t_fus on commit drop as' in d) = 0 then raise exception '% : texte attendu introuvable', f; end if;
    d := replace(d, 'create temp table t_fus on commit drop as', 'drop table if exists t_fus;' || chr(10) || '  create temp table t_fus on commit drop as');
    execute d;
  end loop;
end $$;

-- Contrôle (dans une transaction annulée) :
-- begin; select fusionner_clients_tva(), fusionner_clients_email(); rollback;
