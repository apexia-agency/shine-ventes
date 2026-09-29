-- Rangeur de factures V5 : la file « Factures à vérifier » dans l'onglet À valider du board (29/09/2026).
-- Robin vide la file chaque semaine. Chaque décision est journalisée (valide_par, valide_le) et annulable.
-- « Retenir pour ce fournisseur » transforme la correction en règle : le nom lu devient un alias, le n° de TVA
-- est gardé, et un fournisseur sans compte reçoit le compte choisi. La facture suivante passe alors toute seule.
-- Retour arrière : drop des trois fonctions et de la colonne range_drive.

-- Une facture validée dans le board doit encore quitter « 3 - A VERIFIER » sur le Drive (flux n8n)
alter table factures_achats add column if not exists range_drive boolean not null default false;
alter table factures_achats add column if not exists regle_apprise text;

create or replace function public.factures_a_verifier_liste()
returns table (id bigint, fichier text, fournisseur text, fournisseur_id int, fournisseur_lu text, fournisseur_tva text, num_facture text,
  date_facture date, montant_ht numeric, montant_tva numeric, montant_ttc numeric, devise text, statut text, motif text, controles jsonb,
  ventilation jsonb, suggestion text, drive_url text, source text, traite_le timestamptz, valide_par text, valide_le timestamptz, regle_apprise text)
language sql stable security definer set search_path = public as $$
  select f.id, f.fichier, f.fournisseur, f.fournisseur_id, f.lecture->>'fournisseur_nom', f.fournisseur_tva, f.num_facture,
    f.date_facture, f.montant_ht, f.montant_tva, f.montant_ttc, f.devise, f.statut, f.motif, f.controles,
    f.ventilation, f.categorie, f.drive_url, f.source, f.traite_le, f.valide_par, f.valide_le, f.regle_apprise
  from factures_achats f
  where (select est_associe()) and f.lecture is not null
    and (f.statut = 'a_verifier' or (f.statut in ('validee', 'ecartee') and f.valide_le > now() - interval '60 days'))
  order by (f.statut = 'a_verifier') desc, f.date_facture desc nulls last, f.id desc
$$;

-- Fournisseurs connus, pour choisir le bon dans la file
create or replace function public.factures_fournisseurs_liste()
returns table (id int, nom text, compte text, mode text, statut text, territoire text)
language sql stable security definer set search_path = public as $$
  select id, nom, compte, mode, statut, territoire from factures_fournisseurs where (select est_associe()) order by nom
$$;

-- p_action : 'valider' (avec p_compte, ou la ventilation déjà calculée), 'ecarter' (pas une facture à comptabiliser), 'annuler'
-- p_fournisseur_id : fournisseur choisi ; p_nouveau : nom d'un fournisseur à créer ; p_retenir : la correction devient une règle
create or replace function public.traiter_facture(p_id bigint, p_action text, p_fournisseur_id int default null, p_compte text default null,
  p_retenir boolean default false, p_nouveau text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r text; qui text := (select auth.jwt()->>'email'); fa factures_achats; fo factures_fournisseurs; lu text; regle text := null; vent jsonb;
begin
  select role into r from acces_board where lower(email) = lower(qui);
  if r is null or r not in ('valideur', 'admin') then raise exception 'Accès refusé'; end if;
  select * into fa from factures_achats where id = p_id for update;
  if not found then raise exception 'Facture inconnue'; end if;

  if p_action = 'annuler' then
    update factures_achats set statut = 'a_verifier', a_verifier = true, valide_par = null, valide_le = null, range_drive = false where id = p_id;
    return jsonb_build_object('ok', true);
  end if;
  if p_action = 'ecarter' then
    update factures_achats set statut = 'ecartee', a_verifier = false, valide_par = qui, valide_le = now(), range_drive = false where id = p_id;
    return jsonb_build_object('ok', true);
  end if;
  if p_action <> 'valider' then raise exception 'Action inconnue : %', p_action; end if;

  -- Fournisseur : choisi, créé, ou celui trouvé par le moteur
  if nullif(trim(p_nouveau), '') is not null then
    insert into factures_fournisseurs (nom, alias, compte, regime_tva, territoire, tva_deductible, statut, origine, modifie_par, note)
    values (trim(p_nouveau), array[upper(trim(p_nouveau))], nullif(trim(p_compte), ''), 'FR', 'FR', 'OUI',
      case when nullif(trim(p_compte), '') is not null then 'ok' else 'a_valider' end, 'board (file à vérifier)', qui,
      'Créé depuis la facture ' || coalesce(fa.num_facture, fa.fichier))
    on conflict (nom) do nothing;
    select * into fo from factures_fournisseurs where nom = trim(p_nouveau);
    regle := 'nouveau fournisseur ' || fo.nom;
  elsif p_fournisseur_id is not null then
    select * into fo from factures_fournisseurs where id = p_fournisseur_id;
  elsif fa.fournisseur_id is not null then
    select * into fo from factures_fournisseurs where id = fa.fournisseur_id;
  end if;

  -- Imputation : un compte saisi remplace la ventilation ; sinon on garde celle du moteur
  if nullif(trim(p_compte), '') is not null then
    if trim(p_compte) !~ '^\d{6,8}$' then raise exception 'Compte invalide : % (6 à 8 chiffres)', p_compte; end if;
    vent := jsonb_build_array(jsonb_build_object('compte', trim(p_compte), 'libelle', coalesce(fo.nom, fa.fournisseur), 'montant_ht', fa.montant_ht, 'lignes', '[]'::jsonb));
  elsif coalesce(jsonb_array_length(fa.ventilation), 0) > 0 then
    vent := fa.ventilation;
  else
    raise exception 'Choisis un compte : le moteur n''en a pas trouvé';
  end if;

  -- La correction devient une règle (le nom lu et le n° de TVA feront reconnaître le fournisseur la prochaine fois)
  if p_retenir and fo.id is not null then
    lu := upper(nullif(trim(fa.lecture->>'fournisseur_nom'), ''));
    update factures_fournisseurs set
      alias = case when lu is not null and not (lu = any(alias)) then alias || lu else alias end,
      tva_intracom = case when nullif(fa.fournisseur_tva, '') is not null and not (upper(replace(fa.fournisseur_tva, ' ', '')) = any(tva_intracom))
        then tva_intracom || upper(replace(fa.fournisseur_tva, ' ', '')) else tva_intracom end,
      compte = case when mode = 'mono' and nullif(trim(p_compte), '') is not null then trim(p_compte) else compte end,
      statut = case when statut = 'a_valider' and mode = 'mono' and coalesce(nullif(trim(p_compte), ''), compte) is not null then 'ok' else statut end,
      motifs = case when statut = 'a_valider' and mode = 'mono' and coalesce(nullif(trim(p_compte), ''), compte) is not null then '{}' else motifs end,
      modifie_par = qui, modifie_le = now()
    where id = fo.id;
    regle := coalesce(regle || ' ; ', '') || 'règle retenue pour ' || fo.nom || coalesce(' (compte ' || nullif(trim(p_compte), '') || ')', '');
  end if;

  update factures_achats set statut = 'validee', a_verifier = false, fournisseur_id = coalesce(fo.id, fournisseur_id), fournisseur = coalesce(fo.nom, fournisseur),
    ventilation = vent, compte = case when jsonb_array_length(vent) = 1 then vent->0->>'compte' else null end,
    valide_par = qui, valide_le = now(), range_drive = false, regle_apprise = regle
  where id = p_id;
  return jsonb_build_object('ok', true, 'regle', regle);
end $$;

revoke execute on function public.factures_a_verifier_liste() from public, anon;
revoke execute on function public.factures_fournisseurs_liste() from public, anon;
revoke execute on function public.traiter_facture(bigint, text, int, text, boolean, text) from public, anon;
grant execute on function public.factures_a_verifier_liste() to authenticated;
grant execute on function public.factures_fournisseurs_liste() to authenticated;
grant execute on function public.traiter_facture(bigint, text, int, text, boolean, text) to authenticated;

-- Le moteur V5 distingue aussi les proformas, devis et factures d'acompte (contrôles 5 et 6) : la table doit les accepter
alter table factures_achats drop constraint if exists factures_achats_type_doc_check;
alter table factures_achats add constraint factures_achats_type_doc_check check (type_doc in ('facture', 'avoir', 'proforma', 'devis', 'acompte', 'autre'));
