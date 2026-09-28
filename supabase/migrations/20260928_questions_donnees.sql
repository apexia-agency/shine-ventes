-- File des questions sur les données (appliqué le 28/09/2026), tranchées dans l'onglet « À valider » du board.
-- Règle (Robin, 28/09) : dès qu'on hésite sur une donnée (doublon possible, test, segment, classement…),
-- on ne tranche pas seul : on pose la question ici. Rien n'est supprimé, chaque réponse est annulable.
-- Types gérés par repondre_question : commande_double et commande_test ('ecarter' → retenue = false,
-- doublon_de = 'question:<id>:<motif>' ; 'annuler' remet retenue = true). Ajouter un type = ajouter son effet ici.
-- Remplie le 28/09 : 36 commandes passées deux fois à l'identique (2 008 € HT), 7 commandes de test possibles (239 €).

create table if not exists questions_donnees (
  id serial primary key,
  type text not null,
  cle text not null unique,
  titre text not null,
  detail text,
  proposition text,
  choix jsonb not null,
  donnees jsonb not null default '{}',
  montant numeric,
  statut text not null default 'ouverte' check (statut in ('ouverte', 'repondue')),
  reponse text,
  decide_par text,
  decide_le timestamptz,
  cree_le timestamptz not null default now()
);
alter table questions_donnees enable row level security;

create or replace function public.questions_liste()
returns setof questions_donnees language sql stable security definer set search_path = public as $$
  select * from questions_donnees where (select est_associe()) order by (statut = 'ouverte') desc, montant desc nulls last, id
$$;

create or replace function public.repondre_question(p_id int, p_reponse text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r text; q questions_donnees; qui text := (select auth.jwt()->>'email'); motif text;
begin
  select role into r from acces_board where lower(email) = lower(qui);
  if r is null or r not in ('valideur', 'admin') then raise exception 'Accès refusé'; end if;
  select * into q from questions_donnees where id = p_id for update;
  if not found then raise exception 'Question inconnue'; end if;

  -- Annuler d'abord l'effet d'une réponse précédente
  if q.statut = 'repondue' and q.reponse = 'ecarter' and q.type in ('commande_double', 'commande_test') then
    update ventes_pieces set retenue = true, doublon_de = null
    where id in (select (jsonb_array_elements_text(q.donnees->'ecarter'))::bigint) and doublon_de like 'question:' || q.id || ':%';
  end if;

  if p_reponse = 'annuler' then
    update questions_donnees set statut = 'ouverte', reponse = null, decide_par = null, decide_le = null where id = p_id;
    return jsonb_build_object('ok', true);
  end if;
  if not exists (select 1 from jsonb_array_elements(q.choix) c where c->>'v' = p_reponse) then raise exception 'Réponse inconnue'; end if;

  if p_reponse = 'ecarter' and q.type in ('commande_double', 'commande_test') then
    motif := case q.type when 'commande_double' then 'doublon de commande' else 'commande de test' end;
    update ventes_pieces set retenue = false, doublon_de = 'question:' || q.id || ':' || motif || ' (validé par ' || qui || ')'
    where id in (select (jsonb_array_elements_text(q.donnees->'ecarter'))::bigint) and retenue;
  end if;
  update questions_donnees set statut = 'repondue', reponse = p_reponse, decide_par = qui, decide_le = now() where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

revoke execute on function public.repondre_question(int, text) from public, anon;
grant execute on function public.repondre_question(int, text) to authenticated;
grant execute on function public.questions_liste() to authenticated;
