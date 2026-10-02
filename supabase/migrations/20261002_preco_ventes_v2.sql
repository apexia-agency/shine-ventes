-- Préco de vente, suite (demandé par Jérémy le 02/10/2026) :
--   1. stock des cuves (litres) lu dans le tableau de Laurent, onglet « Vrac Production », colonne D ; bidons en commande (colonne E) ;
--   2. objectifs modifiables depuis le board (stylo sur chaque objectif) ;
--   3. prévision glissante : les 12 mois à venir à partir du mois en cours (référence = les 12 derniers mois terminés),
--      pour toujours afficher les trois prochains mois ; les taux restent calculés sur le dernier exercice terminé.
-- Les copies du tableau de Laurent (preco_laurent, preco_cuves) sont chargées hors du dépôt.
-- Retour arrière : drop function preco_definir_objectif(text, numeric); drop table preco_cuves;
--                  alter table preco_laurent drop column en_commande; puis réappliquer rafraichir_preco de 20261002_preco_ventes.sql.

alter table preco_laurent add column if not exists en_commande numeric;   -- unités déjà en commande ou en reliquat

create table if not exists preco_cuves (
  code text not null,                   -- code article du vrac (AS10-C…)
  lu_le date not null,
  designation text,
  litres numeric,                       -- stock vivant, en LITRES
  en_commande numeric,                  -- litres en commande ou en reliquat
  primary key (code, lu_le)
);
alter table preco_cuves enable row level security;
drop policy if exists lecture_associes on preco_cuves;
create policy lecture_associes on preco_cuves for select to authenticated using ((select est_associe()));
revoke all on preco_cuves from anon;
revoke insert, update, delete, truncate on preco_cuves from authenticated;

-- Modifier un objectif depuis le board (valideurs et administrateurs), puis recalculer la préco
create or replace function public.preco_definir_objectif(p_groupe text, p_objectif numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r text;
begin
  select role into r from acces_board where lower(email) = lower((select auth.jwt()->>'email'));
  if r is null or r not in ('valideur', 'admin') then raise exception 'Accès refusé'; end if;
  if p_objectif is null or p_objectif <= 0 then raise exception 'Objectif invalide'; end if;
  update preco_objectifs set objectif_ca = round(p_objectif), maj_le = now() where groupe = p_groupe;
  if not found then raise exception 'Famille inconnue'; end if;
  return rafraichir_preco();
end $$;
revoke all on function public.preco_definir_objectif(text, numeric) from public, anon;
grant execute on function public.preco_definir_objectif(text, numeric) to authenticated;

-- Prévision glissante : on part de la définition actuelle de rafraichir_preco et on ne change que le calcul des dates
do $$
declare d text; d2 text;
begin
  select pg_get_functiondef('public.rafraichir_preco()'::regprocedure) into d;
  d2 := replace(d, 'v_du := (v_au - interval ''11 months'')::date;',
                   'v_ex := (extract(year from v_au)::int - 1) || ''-'' || extract(year from v_au)::int;');
  d2 := replace(d2, 'v_ex := extract(year from v_du)::int || ''-'' || extract(year from v_au)::int;',
                    'v_du := (date_trunc(''month'', current_date) - interval ''12 months'')::date; v_au := (v_du + interval ''11 months'')::date;');
  if d2 = d then raise exception 'rafraichir_preco : lignes de dates introuvables (fonction déjà modifiée ?)'; end if;
  execute d2;
end $$;
select rafraichir_preco();
