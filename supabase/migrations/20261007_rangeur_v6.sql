-- Rangeur de factures V6 (07/10/2026) : calé sur le livre des achats de septembre 2026 validé par Jérémy.
-- Banc d'essai (outils/factures/banc-livre-2026-09.mts) : même rangement que le livre sur 77 factures sur 83 ; les 6 autres partent
-- « à vérifier » pour une vraie raison (devise, fin de bail, mention proforma, ticket) ou à 1 centime près.
-- 1. Fournisseurs : sous-rubrique (« Créer nouveau compte » du livre) et règles de contenu (plaque, mots de la facture, ligne par ligne).
-- 2. Factures : taux de TVA déductible propre à la facture (voiture de tourisme, carburant), types « ticket » et « échéancier ».
-- 3. Grand livre déjà passé par le cabinet (octobre 2025 - août 2026, chargé à part) : une facture en retard déjà saisie est écartée.
-- 4. Export comptable et rangement Drive : sous-rubrique dans le libellé et dans le dossier du compte ; TVA propre à la facture.
-- 5. Règles des fournisseurs (outils/factures/regles-livre-2026-09.mjs) : marquées modifie_par = 'livre 2026-09'.
-- Retour arrière : drop des colonnes regles, sous_rubrique, tva_deductible (factures_achats), de la table factures_grand_livre ;
-- recréer les deux fonctions depuis 20260929_rangeur_export_comptable.sql et 20260929_rangeur_plan_de_comptes.sql ;
-- les règles d'avant sont dans 20260929_rangeur_factures_donnees.sql.

alter table factures_fournisseurs add column if not exists sous_rubrique text, add column if not exists regles jsonb;
alter table factures_achats add column if not exists tva_deductible text;
alter table factures_achats drop constraint if exists factures_achats_type_doc_check;
alter table factures_achats add constraint factures_achats_type_doc_check
  check (type_doc = any (array['facture', 'avoir', 'proforma', 'devis', 'acompte', 'ticket', 'echeancier', 'autre']));

create table if not exists factures_grand_livre (
  id bigserial primary key,
  compte text not null,
  date date not null,
  piece text,
  libelle text not null,
  debit numeric not null,
  source text not null      -- ex. « Grand compte COMPTA (3), ALL LIVRES 600-620, 2025-10 à 2026-08 »
);
create index if not exists factures_grand_livre_date on factures_grand_livre (date);
alter table factures_grand_livre enable row level security;
drop policy if exists lecture_factures on factures_grand_livre;
create policy lecture_factures on factures_grand_livre for select to authenticated using ((select acces_factures()) is not null);

create or replace function public.factures_chemin_rangement(p_id bigint)
returns jsonb language sql stable security definer set search_path = public as $$
  with f as (
    select id, date_facture, coalesce((select v->>'compte' from jsonb_array_elements(ventilation) v order by abs((v->>'montant_ht')::numeric) desc limit 1), compte) as compte,
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
  for f in select id from factures_achats where piece is null and statut in ('classee', 'validee') and date_facture >= debut and date_facture < fin order by date_facture, id loop
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

update factures_fournisseurs set alias = array['BOUTIQUE STORE', 'BOUTIQUE STORE LOYER', 'ANGEL STORES', 'BOUTIQUE DU STORE', 'LA BOUTIQUE DU STORE']::text[], compte = '61323000', regles = '[{"si":["taxe fonciere","taxes foncieres"],"ligne":true,"compte":"61410000","note":"taxe foncière refacturée par le bailleur : charges locatives"},{"si":["electricite"],"ligne":true,"compte":"60610000"}]'::jsonb, modifie_par = 'livre 2026-09', modifie_le = now() where nom = 'Boutique Store (loyer Veauche)';
update factures_fournisseurs set alias = array['SCI CMD IMMOBILIER', 'IMMO COMUNICA', 'SCI IMMO COMUNICA']::text[], compte = '61327000', regime_tva = 'FR', tva_deductible = 'OUI', statut = 'ok', motifs = array[]::text[], note = 'Loyer des locaux 348 rue François Durafour (Jérémy, livre de septembre 2026).', modifie_par = 'livre 2026-09', modifie_le = now() where nom = 'SCI CMD Immobilier';
insert into factures_fournisseurs (nom, alias, compte, sous_rubrique, famille, regime_tva, territoire, tva_deductible, mode, regles, statut, motifs, note, origine)
  values ('Direction générale des Finances publiques', array['DIRECTION GENERALE DES FINANCES PUBLIQUES', 'FINANCES PUBLIQUES', 'DGFIP']::text[], null, null, 15, 'SANS_TVA', 'FR', 'OUI', 'mono', '[{"si":["taxe fonciere","taxes foncieres"],"ecarter":"avis de taxe foncière du propriétaire : justificatif d''une refacturation, pas à saisir"}]'::jsonb, 'ok', array[]::text[], 'Impôts : seuls les avis de taxe foncière du propriétaire sont écartés ; le reste est à vérifier.', 'livre de septembre 2026 (Jérémy, 07/10/2026)')
  on conflict (nom) do nothing;
update factures_fournisseurs set tva_deductible = 'OUI', note = 'Loyer de la visseuse passé HT par le cabinet (livre de septembre 2026).', modifie_par = 'livre 2026-09', modifie_le = now() where nom = 'La Banque Postale (leasing visseuse)';
update factures_fournisseurs set compte = null, regime_tva = 'FR', tva_deductible = 'OUI', statut = 'ok', motifs = array[]::text[], regles = '[{"si":["FN 425 QX","308"],"compte":"61221110","note":"Peugeot 308 : voiture de société, loyer HT (Jérémy, 07/10/2026)"},{"si":["FG 937 ME","GOLF"],"compte":"61221100","note":"Golf : voiture de société, loyer HT (Jérémy, 07/10/2026)"},{"si":["DX 934 GV","IVECO"],"compte":"61229000"},{"si":["CHARIOT"],"compte":"61351600"}]'::jsonb, note = 'Un compte par véhicule ; véhicule inconnu → à vérifier.', modifie_par = 'livre 2026-09', modifie_le = now() where nom = 'Capitole Finance';
update factures_fournisseurs set alias = array['VOLKSWAGEN', 'VOLKSWAGEN CUPRA', 'VOLKSWAGEN BANK', 'VOLKSWAGEN FINANCIAL SERVICES']::text[], compte = null, regime_tva = 'FR', tva_deductible = 'NON', statut = 'ok', motifs = array[]::text[], regles = '[{"si":["GZ 505 XD","ATECA"],"ecarter":"véhicule de SPACE UP (Jérémy, 07/10/2026) : pas un achat de SHINE"},{"si":["GT 479 WH"],"ecarter":"véhicule de SPACE UP (Jérémy, 07/10/2026) : pas un achat de SHINE"},{"si":["GR 171 EW"],"compte":"61225000"},{"si":["GR 172 EW"],"compte":"61228000"},{"si":["GR 197 AH"],"compte":"61226000"}]'::jsonb, note = 'Voitures de tourisme : loyer TTC (TVA non déductible). Ateca et Cupra GT479WH : véhicules de Space Up, écartés.', modifie_par = 'livre 2026-09', modifie_le = now() where nom = 'Volkswagen Bank';
insert into factures_fournisseurs (nom, alias, compte, sous_rubrique, famille, regime_tva, territoire, tva_deductible, mode, regles, statut, motifs, note, origine)
  values ('HDV Automobiles', array['HDV AUTOMOBILES', 'HDV']::text[], '61520000', null, 13, 'FR', 'FR', 'NON', 'mono', null, 'ok', array[]::text[], 'Carrosserie : réparations des voitures de tourisme (TVA non déductible).', 'livre de septembre 2026 (Jérémy, 07/10/2026)')
  on conflict (nom) do nothing;
insert into factures_fournisseurs (nom, alias, compte, sous_rubrique, famille, regime_tva, territoire, tva_deductible, mode, regles, statut, motifs, note, origine)
  values ('Carrefour Market Veauche (Veauch Distri)', array['VEAUCH DISTRI', 'CARREFOUR MARKET VEAUCHE', 'CARREFOUR MARKET']::text[], '62570000', null, 16, 'FR', 'FR', 'OUI', 'mono', '[{"si":["GZ 505 XD"],"ecarter":"carburant de la Seat Ateca, véhicule de SPACE UP (Jérémy, 07/10/2026) : pas un achat de SHINE"},{"si":["gazole","gasoil","diesel","essence","carburant","SP95","SP98","E10"],"compte":"60614000","tva_deductible":"80%"}]'::jsonb, 'ok', array[]::text[], 'Tickets : carburant (80 % de la TVA déductible) ou café et fournitures du bureau.', 'livre de septembre 2026 (Jérémy, 07/10/2026)')
  on conflict (nom) do nothing;
update factures_fournisseurs set alias = array['INTER', 'INTERMARCHE']::text[], statut = 'ok', motifs = array[]::text[], note = 'Carburant : 80 % de la TVA déductible.', modifie_par = 'livre 2026-09', modifie_le = now() where nom = 'Intermarché (carburant) ?';
update factures_fournisseurs set alias = array['ULYS', 'ASF', 'VINCI AUTOROUTES']::text[], modifie_par = 'livre 2026-09', modifie_le = now() where nom = 'Ulys (péages)';
update factures_fournisseurs set alias = array['GAN ASS MULTIRISQUE', 'GAN ASS ENC', 'GAN ASSURANCES', 'GAN']::text[], compte = '61611000', regime_tva = 'SANS_TVA', statut = 'ok', motifs = array[]::text[], regles = '[{"si":["indemnite","indemnisation","sinistre"],"ecarter":"indemnité d''assurance : un produit (export des ventes, onglet « Hors ventes »), pas un achat"},{"si":["responsabilite civile","RC PRO","RC professionnelle"],"ecarter":"échéancier RC Pro 2026-2027 : 680,83 € par mois d''octobre 2026 à septembre 2027, passés chaque mois avec la même pièce"}]'::jsonb, note = 'Multirisque en 61611000 ; indemnités et échéancier RC Pro écartés (Jérémy, 07/10/2026).', modifie_par = 'livre 2026-09', modifie_le = now() where nom = 'Gan Assurances';
insert into factures_fournisseurs (nom, alias, compte, sous_rubrique, famille, regime_tva, territoire, tva_deductible, mode, regles, statut, motifs, note, origine)
  values ('Edenred', array['EDENRED', 'EDENRED FRANCE']::text[], '62700000', null, 14, 'FR', 'FR', 'OUI', 'mono', '[{"si":["commission"],"ligne":true,"compte":"62700000"},{"si":["valeur faciale","titres restaurant","titre restaurant","ticket restaurant"],"ligne":true,"ecarter":"valeur des titres-restaurant : paie (part SHINE 60 % en 6475, part des salariés retenue sur la paie)"}]'::jsonb, 'ok', array[]::text[], 'Seule la commission est un achat (Jérémy, 07/10/2026).', 'livre de septembre 2026 (Jérémy, 07/10/2026)')
  on conflict (nom) do nothing;
update factures_fournisseurs set compte = '60110000', sous_rubrique = 'MP CHIMIE POUR NEXUS', modifie_par = 'livre 2026-09', modifie_le = now() where nom = 'Univar';
update factures_fournisseurs set compte = '60110000', sous_rubrique = 'MP CHIMIE POUR NEXUS', modifie_par = 'livre 2026-09', modifie_le = now() where nom = 'Vidara';
update factures_fournisseurs set compte = '60110000', sous_rubrique = 'MP CHIMIE POUR NEXUS', modifie_par = 'livre 2026-09', modifie_le = now() where nom = 'Quimidroga';
update factures_fournisseurs set compte = '60110000', sous_rubrique = 'MP CHIMIE POUR NEXUS', modifie_par = 'livre 2026-09', modifie_le = now() where nom = 'Interchimie';
update factures_fournisseurs set compte = '60110000', sous_rubrique = 'MP CHIMIE POUR NEXUS', modifie_par = 'livre 2026-09', modifie_le = now() where nom = 'Stockmeier';
update factures_fournisseurs set compte = '60110000', sous_rubrique = 'MP CHIMIE POUR NEXUS', modifie_par = 'livre 2026-09', modifie_le = now() where nom = 'Keyser';
update factures_fournisseurs set compte = '60130000', sous_rubrique = 'MP CHIMIE INTRA POUR NEXUS', statut = 'ok', motifs = array[]::text[], modifie_par = 'livre 2026-09', modifie_le = now() where nom = 'Spiess';
update factures_fournisseurs set compte = '60130000', sous_rubrique = 'MP CHIMIE INTRA POUR NEXUS', statut = 'ok', motifs = array[]::text[], modifie_par = 'livre 2026-09', modifie_le = now() where nom = 'Chemipol';
insert into factures_fournisseurs (nom, alias, compte, sous_rubrique, famille, regime_tva, territoire, tva_deductible, mode, regles, statut, motifs, note, origine)
  values ('Labbox', array['LABBOX', 'LABBOX FRANCE']::text[], '60130000', 'AMENAGEMENT POUR NEXUS', 17, 'FR', 'FR', 'OUI', 'mono', null, 'ok', array[]::text[], null, 'livre de septembre 2026 (Jérémy, 07/10/2026)')
  on conflict (nom) do nothing;
update factures_fournisseurs set compte = '60130000', sous_rubrique = 'AMENAGEMENT POUR NEXUS', statut = 'ok', motifs = array[]::text[], modifie_par = 'livre 2026-09', modifie_le = now() where nom = 'Labomat';
update factures_fournisseurs set compte = '60130000', sous_rubrique = 'AMENAGEMENT POUR NEXUS', statut = 'ok', motifs = array[]::text[], modifie_par = 'livre 2026-09', modifie_le = now() where nom = 'Mecalux';
insert into factures_fournisseurs (nom, alias, compte, sous_rubrique, famille, regime_tva, territoire, tva_deductible, mode, regles, statut, motifs, note, origine)
  values ('RS Développement', array['RS DEVELOPPEMENT']::text[], '60400000', null, 12, 'FR', 'FR', 'OUI', 'mono', '[{"si":["NEXUS","point eclair","points eclair"],"compte":"60110000","sous_rubrique":"MP CHIMIE POUR NEXUS","note":"factures marquées Nexus et points éclair : MP chimie pour Nexus (Jérémy, 07/10/2026)"}]'::jsonb, 'ok', array[]::text[], null, 'livre de septembre 2026 (Jérémy, 07/10/2026)')
  on conflict (nom) do nothing;
update factures_fournisseurs set compte = '60263000', sous_rubrique = 'CALAGE ET SCOTCH + BTC', regles = '[{"si":["film","banderole","stretch","etirable"],"ligne":true,"compte":"60263000","sous_rubrique":"FILM + BTB"}]'::jsonb, modifie_par = 'livre 2026-09', modifie_le = now() where nom = 'Plast''Embal';
update factures_fournisseurs set compte = '60112000', statut = 'ok', motifs = array[]::text[], note = 'MP étiquetage, comme dans le livre (Jérémy).', modifie_par = 'livre 2026-09', modifie_le = now() where nom = 'Napack';
update factures_fournisseurs set compte = '60711200', statut = 'ok', motifs = array[]::text[], modifie_par = 'livre 2026-09', modifie_le = now() where nom = 'Plastic Billat';
update factures_fournisseurs set alias = array['TNM LES ECHETS', 'TNM EMBALLAGES', 'TNM']::text[], modifie_par = 'livre 2026-09', modifie_le = now() where nom = 'TNM (VPK) Les Échets';
insert into factures_fournisseurs (nom, alias, compte, sous_rubrique, famille, regime_tva, territoire, tva_deductible, mode, regles, statut, motifs, note, origine)
  values ('AB Packaging', array['AB PACKAGING']::text[], '60261000', null, 3, 'FR', 'FR', 'OUI', 'mono', null, 'ok', array[]::text[], null, 'livre de septembre 2026 (Jérémy, 07/10/2026)')
  on conflict (nom) do nothing;
insert into factures_fournisseurs (nom, alias, compte, sous_rubrique, famille, regime_tva, territoire, tva_deductible, mode, regles, statut, motifs, note, origine)
  values ('F2MI', array['F2MI']::text[], '60711100', null, 2, 'FR', 'FR', 'OUI', 'mono', null, 'ok', array[]::text[], null, 'livre de septembre 2026 (Jérémy, 07/10/2026)')
  on conflict (nom) do nothing;
update factures_fournisseurs set alias = array['CONSEILS', 'RG CONSEILS', 'EMENIS']::text[], statut = 'ok', motifs = array[]::text[], modifie_par = 'livre 2026-09', modifie_le = now() where nom = 'Cabinet comptable (RG Conseils ?)';
update factures_fournisseurs set alias = array['CYLIUM DEV', 'CYLIUM', 'CYLIUMDEV']::text[], note = 'Contrat arrêté en juillet 2026 (Jérémy, 07/10/2026).', modifie_par = 'livre 2026-09', modifie_le = now() where nom = 'Cylium';
insert into factures_fournisseurs (nom, alias, compte, sous_rubrique, famille, regime_tva, territoire, tva_deductible, mode, regles, statut, motifs, note, origine)
  values ('Kheminos', array['KHEMINOS']::text[], '60400000', null, 12, 'FR', 'FR', 'OUI', 'mono', null, 'ok', array[]::text[], null, 'livre de septembre 2026 (Jérémy, 07/10/2026)')
  on conflict (nom) do nothing;
insert into factures_fournisseurs (nom, alias, compte, sous_rubrique, famille, regime_tva, territoire, tva_deductible, mode, regles, statut, motifs, note, origine)
  values ('L.A. Autoclean', array['AUTOCLEAN', 'L A AUTOCLEAN']::text[], '61530000', null, 10, 'FR', 'FR', 'OUI', 'mono', null, 'ok', array[]::text[], 'Réparations prises en charge pour des litiges clients.', 'livre de septembre 2026 (Jérémy, 07/10/2026)')
  on conflict (nom) do nothing;
update factures_fournisseurs set regles = '[{"si":["droits","douane","dedouanement","import","TVA import"],"compte":"62380000","sous_rubrique":"TRANSPORT SUR ACHATS IMPORT"}]'::jsonb, modifie_par = 'livre 2026-09', modifie_le = now() where nom = 'UPS';
update factures_fournisseurs set alias = array['CHANNABLE', 'PRODUCTIMPULSE']::text[], regime_tva = 'AUTOLIQ_UE_SERVICES', territoire = 'INTRA', modifie_par = 'livre 2026-09', modifie_le = now() where nom = 'Channable';
update factures_fournisseurs set regime_tva = 'AUTOLIQ_UE_SERVICES', territoire = 'INTRA', modifie_par = 'livre 2026-09', modifie_le = now() where nom = 'Shopify';
update factures_fournisseurs set regime_tva = 'AUTOLIQ_IMPORT', territoire = 'IMPORT', note = 'Factures émises depuis le Royaume-Uni : TVA à autoliquider.', modifie_par = 'livre 2026-09', modifie_le = now() where nom = 'TikTok';
