-- Rangeur de factures V6.1 (07/10/2026, demandes de Jérémy) :
-- 1. Mois comptable : une facture d'un mois déjà envoyé au cabinet (dernier mois chargé dans factures_grand_livre) et absente de son
--    grand livre passe dans le premier mois ouvert ; l'export, le livre du mois et le rangement Drive suivent ce mois.
-- 2. Livre des achats du mois en Excel (fonction lire les données : factures_livre_donnees ; fichier fabriqué par la fonction Edge livre-achats).
-- 3. Gan : l'échéancier RC Pro part « à vérifier » (document annuel) au lieu d'être écarté.
-- Le moteur (lire-facture) ajoute : documents annuels à vérifier, doublons signalés (fichier DOUBLON_), nom complet du fichier rangé.
-- Retour arrière : drop de la colonne mois_comptable et de factures_livre_donnees ; fonctions de 20261007_rangeur_v6.sql.

alter table factures_achats add column if not exists mois_comptable date;

create or replace function public.factures_chemin_rangement(p_id bigint)
returns jsonb language sql stable security definer set search_path = public as $$
  with f as (
    select id, coalesce(mois_comptable, date_facture) as date_facture, coalesce((select v->>'compte' from jsonb_array_elements(ventilation) v order by abs((v->>'montant_ht')::numeric) desc limit 1), compte) as compte,
      (select v->>'sous_rubrique' from jsonb_array_elements(ventilation) v order by abs((v->>'montant_ht')::numeric) desc limit 1) as sous_rubrique
    from factures_achats where id = p_id
  )
  select jsonb_build_object(
    'id', f.id,
    'exercice', case when extract(month from f.date_facture) >= 10 then extract(year from f.date_facture)::int || '-' || (extract(year from f.date_facture)::int + 1)
                     else (extract(year from f.date_facture)::int - 1) || '-' || extract(year from f.date_facture)::int end,
    'mois', to_char(f.date_facture, 'YYYY-MM') || '_' || (array['janvier','février','mars','avril','mai','juin','juillet','août','septembre','octobre','novembre','décembre'])[extract(month from f.date_facture)::int],
    'compte', f.compte,
    'sous_rubrique', f.sous_rubrique,
    -- V6 : une sous-rubrique « Créer nouveau compte » a son propre dossier, ex. 60110000_MP-CHIMIE-POUR-NEXUS
    'dossier_compte', case when f.compte is null then 'SANS-COMPTE' when f.sous_rubrique is not null then f.compte || '_' || trim(both '-' from regexp_replace(upper(translate(f.sous_rubrique,
      'àâäéèêëîïôöùûüçÀÂÄÉÈÊËÎÏÔÖÙÛÜÇ', 'aaaeeeeiioouuucAAAEEEEIIOOUUUC')), '[^A-Z0-9]+', '-', 'g')) else dossier_compte(f.compte) end)
  from f where f.date_facture is not null
$$;

create or replace function public.factures_export_mois(p_mois text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  debut date := to_date(p_mois || '-01', 'YYYY-MM-DD');
  fin date := (to_date(p_mois || '-01', 'YYYY-MM-DD') + interval '1 month')::date;
  exo text := case when extract(month from to_date(p_mois || '-01', 'YYYY-MM-DD')) >= 10
    then extract(year from to_date(p_mois || '-01', 'YYYY-MM-DD'))::int || '-' || (extract(year from to_date(p_mois || '-01', 'YYYY-MM-DD'))::int + 1)
    else (extract(year from to_date(p_mois || '-01', 'YYYY-MM-DD'))::int - 1) || '-' || extract(year from to_date(p_mois || '-01', 'YYYY-MM-DD'))::int end;
  f record; v jsonb; e text := ''; j text := ''; n int := 0;
  ht numeric; tva numeric; ttc numeric; ded numeric; tva_ded numeric; tva_non numeric; sens int; cpt_tva text; lib text; base_charge numeric;
  lignes jsonb; reste numeric; i int; plus_gros int; montant numeric;
  num text := '';
begin
  if p_mois !~ '^\d{4}-\d{2}$' then raise exception 'Mois attendu au format AAAA-MM'; end if;

  -- N° de pièce : attribué au premier export, jamais changé ensuite
  select coalesce(max(substring(piece from '(\d+)$')::int), 0) into i from factures_achats where piece like 'AC-' || exo || '-%';
  for f in select id from factures_achats where piece is null and statut in ('classee', 'validee') and coalesce(mois_comptable, date_facture) >= debut and coalesce(mois_comptable, date_facture) < fin order by date_facture, id loop
    i := i + 1; update factures_achats set piece = 'AC-' || exo || '-' || lpad(i::text, 4, '0') where id = f.id;
  end loop;

  e := 'Journal;Date;Société;Pièce;Tiers;N° facture;Compte;Libellé;Débit;Crédit;Fichier' || chr(10);
  j := 'Pièce;Sens;Date;Mois;Exercice;Société;Tiers;Compte tiers;N° facture;Type;Famille;Libellé famille;Compte;Onglet plan;Régime TVA;Déclaration;Mention obligatoire;HT;TVA;TVA déductible;TTC;Taux implicite;Devise;Date échéance;Mois échéance;Date paiement;Description;Signalement;Fichier;Traité le' || chr(10);

  for f in
    select a.*, fo.nom as tiers, coalesce(fo.regime_tva, 'FR') as regime, coalesce(a.tva_deductible, fo.tva_deductible, 'OUI') as deductible, fo.famille,
      fam.libelle as lib_famille, fam.onglet
    from factures_achats a
    left join factures_fournisseurs fo on fo.id = a.fournisseur_id
    left join (values (1,'Achats matières premières','ACHATS'),(2,'Achats marchandises','ACHATS'),(3,'Emballages et conditionnement','ACHATS'),
      (4,'Sous-traitance de production','ACHATS'),(5,'Transport sur ventes','TRANSPORT'),(6,'Transport sur achats','TRANSPORT'),(7,'Marketing et publicité','MARKETING'),
      (8,'Loyers et charges locatives','LOYERS'),(9,'Énergie (électricité, gaz, eau)','FRAIS GÉNÉRAUX'),(10,'Entretien et maintenance','FRAIS GÉNÉRAUX'),
      (11,'Outils et abonnements IT','FRAIS GÉNÉRAUX'),(12,'Honoraires et sous-traitance','FRAIS GÉNÉRAUX'),(13,'Véhicules et déplacements','VÉHICULES'),
      (14,'Banque et assurances','FRAIS GÉNÉRAUX'),(15,'Impôts et taxes','IMPÔTS ET TAXES'),(16,'Fournitures et frais divers','FRAIS GÉNÉRAUX'),
      (17,'Investissements (immobilisations)','')) fam(num, libelle, onglet) on fam.num = fo.famille
    where a.statut in ('classee', 'validee') and coalesce(a.mois_comptable, a.date_facture) >= debut and coalesce(a.mois_comptable, a.date_facture) < fin
    order by a.piece
  loop
    n := n + 1;
    sens := case when f.type_doc = 'avoir' then -1 else 1 end;   -- avoir : débit et crédit inversés
    ttc := coalesce(f.montant_ttc, 0);
    ht := coalesce(f.montant_ht, ttc - coalesce(f.montant_tva, 0));
    tva := coalesce(f.montant_tva, 0);
    ded := case when upper(f.deductible) = 'NON' then 0 when f.deductible ~ '^\d+ ?%$' then replace(replace(f.deductible, '%', ''), ' ', '')::numeric / 100 else 1 end;
    cpt_tva := case when f.famille = 17 then '44562' else '44566' end;
    lib := left(coalesce(f.tiers, f.fournisseur, '') || ' ' || coalesce(f.num_facture, ''), 60);
    lignes := coalesce(f.ventilation, '[]'::jsonb);
    if jsonb_array_length(lignes) = 0 and f.compte is not null then lignes := jsonb_build_array(jsonb_build_object('compte', f.compte, 'montant_ht', ht)); end if;

    -- Base des charges : HT, ou TTC sans TVA ; la part de TVA non déductible s'ajoute (FR)
    if f.regime = 'SANS_TVA' then base_charge := ttc; tva_ded := 0; tva_non := 0;
    elsif f.regime like 'AUTOLIQ%' then base_charge := ht; tva_ded := round(ht * 0.2 * ded, 2); tva_non := 0;
    else base_charge := ht + round(tva * (1 - ded), 2); tva_ded := round(tva * ded, 2); tva_non := round(tva * (1 - ded), 2);
    end if;

    -- Lignes de charge : ventilation au prorata, l'arrondi et la TVA non déductible sur la plus grosse ligne
    reste := base_charge; plus_gros := 0;
    for i in 0 .. greatest(jsonb_array_length(lignes) - 1, 0) loop
      if jsonb_array_length(lignes) = 0 then exit; end if;
      if abs((lignes->i->>'montant_ht')::numeric) > abs((lignes->plus_gros->>'montant_ht')::numeric) then plus_gros := i; end if;
    end loop;
    for i in 0 .. jsonb_array_length(lignes) - 1 loop
      v := lignes->i;
      montant := case when i = plus_gros then null else round((v->>'montant_ht')::numeric * coalesce(base_charge / nullif(fa_somme_ventil(lignes), 0), 1), 2) end;
      if montant is not null then reste := reste - montant;
        e := e || fa_ecriture(f.date_facture, f.piece, coalesce(f.tiers, f.fournisseur), f.num_facture, v->>'compte', left(lib || coalesce(' · ' || (v->>'sous_rubrique'), ''), 90), sens * montant, f.drive_url);
      end if;
    end loop;
    if jsonb_array_length(lignes) > 0 then e := e || fa_ecriture(f.date_facture, f.piece, coalesce(f.tiers, f.fournisseur), f.num_facture, lignes->plus_gros->>'compte', left(lib || coalesce(' · ' || (lignes->plus_gros->>'sous_rubrique'), ''), 90), sens * reste, f.drive_url);
    else e := e || fa_ecriture(f.date_facture, f.piece, coalesce(f.tiers, f.fournisseur), f.num_facture, '471000', lib || ' (compte à préciser)', sens * base_charge, f.drive_url); end if;

    -- TVA et fournisseur
    if f.regime like 'AUTOLIQ%' then
      e := e || fa_ecriture(f.date_facture, f.piece, coalesce(f.tiers, f.fournisseur), f.num_facture, '401', lib, -sens * ht, f.drive_url);
      if tva_ded <> 0 then
        e := e || fa_ecriture(f.date_facture, f.piece, coalesce(f.tiers, f.fournisseur), f.num_facture, '445662', lib || ' TVA autoliquidée', sens * tva_ded, f.drive_url);
        e := e || fa_ecriture(f.date_facture, f.piece, coalesce(f.tiers, f.fournisseur), f.num_facture, '4452', lib || ' TVA autoliquidée', -sens * tva_ded, f.drive_url);
      end if;
    else
      if tva_ded <> 0 then e := e || fa_ecriture(f.date_facture, f.piece, coalesce(f.tiers, f.fournisseur), f.num_facture, cpt_tva, lib || ' TVA', sens * tva_ded, f.drive_url); end if;
      e := e || fa_ecriture(f.date_facture, f.piece, coalesce(f.tiers, f.fournisseur), f.num_facture, '401', lib, -sens * ttc, f.drive_url);
    end if;

    j := j || concat_ws(';', f.piece, 'ACHAT', to_char(f.date_facture, 'DD/MM/YYYY'), to_char(f.date_facture, 'YYYY-MM'), exo, 'SHINE',
      fa_csv(coalesce(f.tiers, f.fournisseur)), '401', fa_csv(f.num_facture), coalesce(f.type_doc, 'facture'), coalesce(lpad(f.famille::text, 2, '0'), ''), fa_csv(f.lib_famille),
      coalesce((select string_agg((x->>'compte') || coalesce(' / ' || (x->>'sous_rubrique'), ''), ' + ') from jsonb_array_elements(lignes) x), f.compte, ''), fa_csv(f.onglet), f.regime,
      case f.regime when 'AUTOLIQ_UE_SERVICES' then 'DES' when 'AUTOLIQ_UE_BIENS' then 'EMEBI' when 'AUTOLIQ_IMPORT' then 'Autoliquidation import (CA3)' else '' end, '',
      fa_nombre(sens * ht), fa_nombre(sens * tva), fa_nombre(sens * tva_ded), fa_nombre(sens * ttc),
      case when f.regime = 'FR' and ht <> 0 then replace(round(tva / ht * 100, 2)::text, '.', ',') else '' end, coalesce(f.devise, 'EUR'),
      '', '', '', fa_csv(f.categorie),
      fa_csv(concat_ws(' · ', case when coalesce(f.devise, 'EUR') <> 'EUR' then 'montants en ' || f.devise || ', conversion à faire' end,
        case when f.statut = 'validee' then 'validée par ' || f.valide_par end,
        (select string_agg(c->>'detail', ' · ') from jsonb_array_elements(coalesce(f.controles, '[]')) c where c->>'effet' = 'signal'))),
      fa_csv(f.drive_url), coalesce(to_char(coalesce(f.valide_le, f.traite_le) at time zone 'Europe/Paris', 'DD/MM/YYYY HH24:MI'), '')) || chr(10);
  end loop;

  return jsonb_build_object('mois', p_mois, 'exercice', exo, 'factures', n,
    'nom_ecritures', p_mois || '_SHINE_ecritures_achats.csv', 'nom_journal', p_mois || '_SHINE_journal_achats.csv',
    'ecritures', chr(65279) || e, 'journal', chr(65279) || j);
end $$;

-- Données du livre du mois : factures du mois comptable (rangées, à vérifier, écartées) et libellés des comptes
create or replace function public.factures_livre_donnees(p_mois text)
returns jsonb language sql stable security definer set search_path = public as $$
  with m as (select to_date(p_mois || '-01', 'YYYY-MM-DD') as debut)
  select jsonb_build_object(
    'factures', coalesce((select jsonb_agg(jsonb_build_object(
        'id', a.id, 'statut', a.statut, 'type_doc', a.type_doc, 'date_facture', a.date_facture, 'mois_comptable', a.mois_comptable,
        'fournisseur', coalesce(fo.nom, a.fournisseur), 'num_facture', a.num_facture, 'montant_ht', a.montant_ht, 'montant_tva', a.montant_tva,
        'montant_ttc', a.montant_ttc, 'devise', a.devise, 'ventilation', a.ventilation, 'compte', a.compte, 'controles', a.controles, 'motif', a.motif,
        'drive_url', a.drive_url, 'fichier', a.fichier, 'regime', coalesce(fo.regime_tva, 'FR'), 'deductible', coalesce(a.tva_deductible, fo.tva_deductible, 'OUI'),
        'periode_debut', a.lecture->>'periode_debut', 'periode_fin', a.lecture->>'periode_fin') order by a.date_facture, a.id)
      from factures_achats a left join factures_fournisseurs fo on fo.id = a.fournisseur_id, m
      where a.lecture is not null and a.statut in ('classee', 'validee', 'a_verifier', 'ecartee')
        and date_trunc('month', coalesce(a.mois_comptable, a.date_facture))::date = m.debut), '[]'::jsonb),
    'libelles', coalesce((select jsonb_object_agg(compte, libelle) from factures_comptes where libelle is not null), '{}'::jsonb))
$$;
revoke execute on function public.factures_livre_donnees(text) from public, anon, authenticated;
grant execute on function public.factures_livre_donnees(text) to service_role;

update factures_fournisseurs set regles = '[{"si":["indemnite","indemnisation","sinistre"],"ecarter":"indemnité d''assurance : un produit (export des ventes, onglet « Hors ventes »), pas un achat"},{"si":["responsabilite civile","RC PRO","RC professionnelle"],"verifier":"échéancier RC Pro 2026-2027 : 680,83 € par mois d''octobre 2026 à septembre 2027, à passer chaque mois avec la même pièce (document annuel)"}]'::jsonb,
  note = 'Multirisque en 61611000 ; indemnités écartées ; échéancier RC Pro à vérifier, comme tout document annuel (Jérémy, 07/10/2026).', modifie_par = 'livre 2026-09', modifie_le = now()
  where nom = 'Gan Assurances';
