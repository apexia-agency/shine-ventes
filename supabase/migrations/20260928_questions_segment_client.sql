-- Questions de classement des clients (appliqué le 28/09/2026). Règles de Robin (28/09) :
--  • une commande en double qui n'est ni annulée ni remboursée = le client a vraiment commandé deux fois :
--    on ne pose plus la question (les 36 questions commande_double ont été fermées en « garder ») ;
--  • l'onglet « À valider » sert aux commandes bizarres côté groupe client et segmentation.
-- Type segment_client : réponse = B2C / B2B_PRO / B2B_REVENDEUR → la fiche est reclassée et validée (toutes ses ventes
-- suivent) ; 'annuler' remet le segment d'avant (donnees.segment_avant, sous_segment_avant, valide_avant).
-- Remplie le 28/09 : 149 clients classés particuliers (groupe Client ou Invité) qui ressemblent à des pros
-- (société sur le compte, n° de TVA, plus de la moitié de l'achat en bidons de 5 L et plus) ; seuil 300 € HT si
-- deux signes (conseil : Pro), 500 € si un seul. + 1 client qui a changé de groupe sur le même site.
-- (Les fiches pros fusionnées après la bascule du site pro changent de groupe par construction : pas de question.)

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
  if q.statut = 'repondue' and q.type = 'segment_client' then
    update clients set segment = q.donnees->>'segment_avant', sous_segment = q.donnees->>'sous_segment_avant',
      segment_valide = coalesce((q.donnees->>'valide_avant')::boolean, false)
    where client_id = q.donnees->>'client_id';
    update agg_clients set segment = q.donnees->>'segment_avant', segment_valide = coalesce((q.donnees->>'valide_avant')::boolean, false)
    where client_id = q.donnees->>'client_id';
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
  if q.type = 'segment_client' then
    if p_reponse not in ('B2C', 'B2B_PRO', 'B2B_REVENDEUR') then raise exception 'Segment inconnu'; end if;
    update clients set segment = p_reponse, segment_valide = true, maj_le = now(),
      sous_segment = case when p_reponse = q.donnees->>'segment_avant' then sous_segment else null end,
      note = trim(coalesce(note, '') || ' — segment ' || p_reponse || ' validé par ' || qui || ' (question ' || q.id || ')')
    where client_id = q.donnees->>'client_id';
    update agg_clients set segment = p_reponse, segment_valide = true where client_id = q.donnees->>'client_id';
  end if;
  update questions_donnees set statut = 'repondue', reponse = p_reponse, decide_par = qui, decide_le = now() where id = p_id;
  return jsonb_build_object('ok', true);
end $$;
