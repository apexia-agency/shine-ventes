-- MyClear : un mois n'a ses frais TikTok complets que si les relevés importés couvrent chaque jour
-- du 1er du mois au 5 du mois suivant (avant : seulement le premier et le dernier jour importés, un trou passait inaperçu).
-- Retour arrière : remettre l'expression précédente
--   (select mo.mois >= date_trunc('month', du) + interval '1 month' and mo.mois + interval '1 month 5 days' <= au from imp)
create or replace function myclear_frais_complets(p_mois date)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select not exists (
    select 1 from generate_series(p_mois, (p_mois + interval '1 month 5 days')::date, interval '1 day') g
     where not exists (select 1 from myclear_imports_tiktok i where g::date between i.releves_du and i.releves_au));
$$;
revoke execute on function myclear_frais_complets(date) from public, anon;
grant execute on function myclear_frais_complets(date) to authenticated;
-- Dans myclear_marge, l'expression « frais_complets » appelle désormais myclear_frais_complets(mo.mois)
-- (fonction modifiée à partir de sa définition en base, seule cette expression change).
do $$
declare d text := pg_get_functiondef('public.myclear_marge(date,date)'::regprocedure);
begin
  d := replace(d, '(select mo.mois >= date_trunc(''month'', du) + interval ''1 month'' and mo.mois + interval ''1 month 5 days'' <= au from imp) frais_complets',
                  'myclear_frais_complets(mo.mois) frais_complets');
  if position('myclear_frais_complets(mo.mois)' in d) = 0 then raise exception 'Expression introuvable dans myclear_marge'; end if;
  execute d;
end $$;
