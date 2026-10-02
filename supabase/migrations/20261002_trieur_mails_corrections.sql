-- Trieur de mails de Jérémy : apprendre de ses corrections (02/10/2026).
-- Jérémy pose dans Gmail le libellé « TRI/Toujours inutile » ou « TRI/Toujours garder » sur un mail ;
-- le flux n8n « Boîte Jérémy · apprendre des corrections » appelle mail_regle_apprendre, qui en fait une règle.
--   « toujours inutile » : règle par adresse exacte (expéditeur commercial).
--   « toujours garder »  : règle par EMPREINTE de l'adresse (portée 'empreinte'), pour ne pas garder l'adresse
--                          d'une personne ; la note garde seulement le domaine, pour s'y retrouver.
-- La règle contraire du même expéditeur est désactivée (actif = false), jamais supprimée.
-- Un collègue SHINE n'est jamais mis en « inutile ».
--
-- Retour arrière : drop function mail_regle_apprendre(text, text);
--   alter table mails_regles drop constraint mails_regles_portee_check;
--   alter table mails_regles add constraint mails_regles_portee_check check (portee in ('adresse', 'domaine'));
--   (après avoir désactivé les règles de portée 'empreinte')

alter table public.mails_regles drop constraint if exists mails_regles_portee_check;
alter table public.mails_regles add constraint mails_regles_portee_check check (portee in ('adresse', 'domaine', 'empreinte'));

create or replace function public.mail_regle_apprendre(p_de text, p_decision text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_adresse text := lower(substring(p_de from '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'));
  v_domaine text;
  v_empreinte text;
  v_id bigint;
begin
  if v_adresse is null then return jsonb_build_object('appris', false, 'motif', 'expéditeur illisible'); end if;
  if p_decision not in ('garder', 'inutile') then raise exception 'décision inconnue : %', p_decision; end if;
  v_domaine := split_part(v_adresse, '@', 2);
  v_empreinte := encode(sha256(convert_to(v_adresse, 'UTF8')), 'hex');
  if p_decision = 'inutile' and v_domaine in ('shine-group.fr', 'shine-pro.fr') then
    return jsonb_build_object('appris', false, 'motif', 'collègue SHINE : jamais inutile');
  end if;

  -- La règle contraire du même expéditeur ne s'applique plus
  update mails_regles set actif = false
  where actif and decision <> p_decision
    and ((portee = 'adresse' and cle = v_adresse) or (portee = 'empreinte' and cle = v_empreinte));

  if p_decision = 'inutile' then
    insert into mails_regles (portee, cle, decision, note, origine)
    values ('adresse', v_adresse, 'inutile', 'libellé « TRI/Toujours inutile » posé par Jérémy', 'jeremy')
    on conflict (portee, cle) do update set decision = 'inutile', actif = true, origine = 'jeremy', note = excluded.note
    returning id into v_id;
  else
    insert into mails_regles (portee, cle, decision, note, origine)
    values ('empreinte', v_empreinte, 'garder', 'libellé « TRI/Toujours garder » posé par Jérémy, expéditeur @' || v_domaine, 'jeremy')
    on conflict (portee, cle) do update set decision = 'garder', actif = true, origine = 'jeremy', note = excluded.note
    returning id into v_id;
  end if;
  return jsonb_build_object('appris', true, 'regle_id', v_id, 'decision', p_decision, 'domaine', v_domaine);
end
$$;
revoke all on function public.mail_regle_apprendre(text, text) from public, anon, authenticated;
grant execute on function public.mail_regle_apprendre(text, text) to service_role;
