-- Export comptable mensuel du rangeur de factures (29/09/2026, document 39 de Jérémy, point 5 bis).
-- Deux CSV par mois, déposés par n8n dans 2 - CLASSEES/<exercice>/<mois>/ :
--   AAAA-MM_SHINE_ecritures_achats.csv : une ligne par ligne d'écriture (fichier d'import du cabinet)
--   AAAA-MM_SHINE_journal_achats.csv   : une ligne par facture (pilotage)
-- Format Excel français : séparateur « ; », virgule décimale, UTF-8 avec BOM.
-- Factures prises : statut classée ou validée, date de facture dans le mois. Les écartées et les « à vérifier » n'y sont pas.
-- Écritures (PCG) selon le régime de TVA du fournisseur :
--   FR, TVA déductible     : 6xx HT (par compte de la ventilation) + 44566 TVA  / 401 TTC            (3 lignes au moins)
--   FR, TVA non déductible : la part non déductible s'ajoute à la charge ; 44566 = part déductible   (2 lignes si NON)
--   Autoliquidation (UE biens, UE services, import) : 6xx HT / 401 HT ; 445662 TVA / 4452 TVA  (TVA = HT × 20 %)
--   Sans TVA (assurances…) : 6xx TTC / 401 TTC
--   Immobilisations (famille 17) : 44562 au lieu de 44566. Avoir : débit et crédit inversés.
-- N° de pièce AC-<exercice>-0001 attribué une fois pour toutes au premier export (ordre date, puis id).

alter table factures_achats add column if not exists piece text unique;

-- Aides : champ CSV protégé, nombre à la française, une ligne d'écriture (montant > 0 = débit, < 0 = crédit).
-- concat_ws saute les NULL : chaque champ est ramené à '' pour que les colonnes ne se décalent jamais.
create or replace function public.fa_csv(t text) returns text language sql immutable as $$
  select case when t is null then '' when t ~ '[;"\n\r]' then '"' || replace(t, '"', '""') || '"' else t end $$;
create or replace function public.fa_nombre(x numeric) returns text language sql immutable as $$
  select case when x is null then '' else replace(to_char(round(x, 2), 'FM999999990.00'), '.', ',') end $$;
create or replace function public.fa_somme_ventil(l jsonb) returns numeric language sql immutable as $$
  select sum((x->>'montant_ht')::numeric) from jsonb_array_elements(l) x $$;
create or replace function public.fa_ecriture(d date, piece text, tiers text, num text, compte text, lib text, montant numeric, fichier text)
returns text language sql immutable as $$
  select case when coalesce(montant, 0) = 0 then '' else concat_ws(';', 'AC', to_char(d, 'DD/MM/YYYY'), 'SHINE', piece, fa_csv(tiers), fa_csv(num),
    compte, fa_csv(lib), case when montant > 0 then fa_nombre(montant) else '' end, case when montant < 0 then fa_nombre(-montant) else '' end, fa_csv(fichier)) || chr(10) end $$;


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
  for f in select id from factures_achats where piece is null and statut in ('classee', 'validee') and date_facture >= debut and date_facture < fin order by date_facture, id loop
    i := i + 1; update factures_achats set piece = 'AC-' || exo || '-' || lpad(i::text, 4, '0') where id = f.id;
  end loop;

  e := 'Journal;Date;Société;Pièce;Tiers;N° facture;Compte;Libellé;Débit;Crédit;Fichier' || chr(10);
  j := 'Pièce;Sens;Date;Mois;Exercice;Société;Tiers;Compte tiers;N° facture;Type;Famille;Libellé famille;Compte;Onglet plan;Régime TVA;Déclaration;Mention obligatoire;HT;TVA;TVA déductible;TTC;Taux implicite;Devise;Date échéance;Mois échéance;Date paiement;Description;Signalement;Fichier;Traité le' || chr(10);

  for f in
    select a.*, fo.nom as tiers, coalesce(fo.regime_tva, 'FR') as regime, coalesce(fo.tva_deductible, 'OUI') as deductible, fo.famille,
      fam.libelle as lib_famille, fam.onglet
    from factures_achats a
    left join factures_fournisseurs fo on fo.id = a.fournisseur_id
    left join (values (1,'Achats matières premières','ACHATS'),(2,'Achats marchandises','ACHATS'),(3,'Emballages et conditionnement','ACHATS'),
      (4,'Sous-traitance de production','ACHATS'),(5,'Transport sur ventes','TRANSPORT'),(6,'Transport sur achats','TRANSPORT'),(7,'Marketing et publicité','MARKETING'),
      (8,'Loyers et charges locatives','LOYERS'),(9,'Énergie (électricité, gaz, eau)','FRAIS GÉNÉRAUX'),(10,'Entretien et maintenance','FRAIS GÉNÉRAUX'),
      (11,'Outils et abonnements IT','FRAIS GÉNÉRAUX'),(12,'Honoraires et sous-traitance','FRAIS GÉNÉRAUX'),(13,'Véhicules et déplacements','VÉHICULES'),
      (14,'Banque et assurances','FRAIS GÉNÉRAUX'),(15,'Impôts et taxes','IMPÔTS ET TAXES'),(16,'Fournitures et frais divers','FRAIS GÉNÉRAUX'),
      (17,'Investissements (immobilisations)','')) fam(num, libelle, onglet) on fam.num = fo.famille
    where a.statut in ('classee', 'validee') and a.date_facture >= debut and a.date_facture < fin
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
        e := e || fa_ecriture(f.date_facture, f.piece, coalesce(f.tiers, f.fournisseur), f.num_facture, v->>'compte', lib, sens * montant, f.drive_url);
      end if;
    end loop;
    if jsonb_array_length(lignes) > 0 then e := e || fa_ecriture(f.date_facture, f.piece, coalesce(f.tiers, f.fournisseur), f.num_facture, lignes->plus_gros->>'compte', lib, sens * reste, f.drive_url);
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
      coalesce(f.compte, (select string_agg(x->>'compte', ' + ') from jsonb_array_elements(lignes) x), ''), fa_csv(f.onglet), f.regime,
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

revoke execute on function public.factures_export_mois(text) from public, anon, authenticated;
grant execute on function public.factures_export_mois(text) to service_role;
