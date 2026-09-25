-- Assistant ventes : exécution d'une requête SELECT en lecture seule.
--
-- Appelée par la fonction serveur « assistant » avec le jeton de la personne connectée :
-- elle tourne avec ses droits (rôle authenticated + règles RLS « lecture_associes »),
-- donc l'assistant ne voit que ce que la personne voit déjà sur le board.
--
-- Garde-fous :
--   - la requête est placée dans une sous-requête : une seule requête SELECT / WITH / VALUES possible,
--     pas de suite d'instructions, pas de WITH qui modifie des données (refusé par Postgres en sous-requête) ;
--   - la transaction passe en lecture seule avant l'exécution : toute écriture échoue,
--     y compris via une fonction appelée dans le SELECT ;
--   - nombre de lignes plafonné (p_max, 5 000 au plus) ;
--   - le délai maximal est celui du rôle authenticated (8 s sur Supabase).

create or replace function public.assistant_sql(p_sql text, p_max integer default 200)
returns json
language plpgsql
security invoker
set search_path = public
as $$
declare
  q text := btrim(p_sql);
  n integer := least(greatest(coalesce(p_max, 200), 1), 5000);
  res json;
begin
  perform set_config('transaction_read_only', 'on', true);
  q := regexp_replace(q, ';\s*$', '');
  if q = '' then
    raise exception 'Requête vide';
  end if;
  if position(';' in q) > 0 then
    raise exception 'Une seule requête à la fois (pas de point-virgule)';
  end if;
  if q !~* '^\s*(select|with|values|table)\s' then
    raise exception 'Seules les requêtes de lecture (SELECT) sont acceptées';
  end if;
  execute format(
    'select json_build_object(''lignes'', coalesce(json_agg(t), ''[]''::json), ''tronque'', count(*) > %s)
       from (select * from (%s) q limit %s) t',
    n, q, n + 1)
  into res;
  -- on retire la ligne de contrôle (n + 1) si la limite est dépassée
  if (res->>'tronque')::boolean then
    select json_build_object('lignes', json_agg(e), 'tronque', true)
      into res
      from (select e from json_array_elements(res->'lignes') with ordinality x(e, i) where i <= n) s;
  end if;
  return res;
end;
$$;

revoke all on function public.assistant_sql(text, integer) from public, anon;
grant execute on function public.assistant_sql(text, integer) to authenticated;

comment on function public.assistant_sql(text, integer) is
  'Assistant ventes : exécute une requête SELECT en lecture seule avec les droits de la personne connectée. Plafond 5 000 lignes.';
