-- Board Transport : coûts des colis DPD et Colissimo, lus dans les factures et exports des transporteurs.
-- Lecture des fichiers : transport-lecteurs.js (board, glisser-déposer) et outils/transport/charger.mjs (chargement initial).
--
-- transport_fichiers : un fichier lu (export DPD, facture Colissimo), avec son statut (intégré, doublon, partiel, retiré).
-- transport_colis    : une ligne par colis (DPD : aussi les frais ajoutés sur un colis déjà facturé, colis = 0 ;
--                      Colissimo nouveau format : une ligne par service et par tarif, sans poids ni code postal ;
--                      Colissimo ancien format : une ligne « ajustement » par service pour ce que le détail n'explique pas).
--                      Coût HT = transport + gasoil + taxes + annexes. Pas de nom ni d'adresse de destinataire.
-- transport_comptes_rendus : commentaires mensuels saisis dans le board.
-- Lecture par le board : transport_donnees(du, au), agrégats seulement. Import : transport_importer(fichier, lignes).
-- Droits : tous les associés (comme Achats et Charges).
-- Retour arrière : drop function transport_donnees, transport_importer, transport_retirer_fichier ;
--                  drop table transport_colis, transport_fichiers, transport_comptes_rendus, transport_jetons.

create table if not exists public.transport_fichiers (
  id bigint generated always as identity primary key,
  transporteur text not null check (transporteur in ('DPD', 'Colissimo')),
  format text not null,              -- dpd_excel, colissimo_pdf (détail par colis), colissimo_pdf_recap (nouveau format)
  service text,                      -- DPD : relais, predict, classic
  compte text,
  nom_fichier text,
  empreinte text not null unique,    -- sha256 du fichier : le même fichier déposé deux fois est reconnu
  num_facture text,
  date_facture date,
  mois text not null,                -- AAAA-MM : mois de la facture (grille de couverture)
  periode_du date,
  periode_au date,
  colis int not null default 0,
  nb_lignes int not null default 0,
  lignes_ajoutees int not null default 0,
  montant_ht numeric(12,2) not null default 0,         -- somme des lignes lues (coût des colis)
  prestations_ht numeric(12,2) not null default 0,     -- Colissimo : prestations complémentaires (retours payants…)
  indemnites_ht numeric(12,2) not null default 0,      -- Colissimo : indemnisations reçues (négatif)
  avoirs_ht numeric(12,2) not null default 0,          -- Colissimo : avoirs et régularisations portés sur la facture
  total_facture_ht numeric(12,2),                      -- total HT imprimé sur la facture, pour contrôle
  statut text not null default 'integre' check (statut in ('integre', 'doublon', 'partiel', 'retire')),
  doublon_de bigint references public.transport_fichiers(id),
  details jsonb,
  importe_le timestamptz not null default now(),
  importe_par text
);

create table if not exists public.transport_colis (
  id bigint generated always as identity primary key,
  fichier_id bigint not null references public.transport_fichiers(id),
  transporteur text not null check (transporteur in ('DPD', 'Colissimo')),
  mode text not null check (mode in ('dpd_dom', 'dpd_rel', 'dpd_cla', 'dpd_multi', 'coli_dom', 'coli_pr', 'coli_aut')),
  code_service text,
  date_envoi date not null,
  num_facture text,
  num_colis text,                    -- n° de suivi (rapprochement futur avec ventes_pieces.num_suivi)
  ref_envoi text,                    -- empreinte de « Votre référence 1 » DPD : regroupe les colis d'un même envoi
  colis int not null default 0,
  poids_kg numeric(10,3),
  cp text,
  pays text,
  region text not null,
  tranche text not null,             -- 0-1, 1-2, 2-5, 5-10, 10-30, 30+, inconnue, frais (ligne sans colis)
  transport numeric(10,2) not null default 0,
  gasoil numeric(10,2) not null default 0,
  taxes numeric(10,2) not null default 0,
  annexes numeric(10,2) not null default 0,
  annexes_detail jsonb,
  cle text not null unique           -- une même ligne déposée deux fois n'est comptée qu'une fois
);
create index if not exists transport_colis_date on public.transport_colis (date_envoi);
create index if not exists transport_colis_fichier on public.transport_colis (fichier_id);
create index if not exists transport_colis_suivi on public.transport_colis (num_colis);

create table if not exists public.transport_comptes_rendus (
  mois text primary key,             -- AAAA-MM
  texte text,
  statut text,                       -- à faire, en cours, fait
  maj_par text,
  maj_le timestamptz not null default now()
);

-- Jetons à usage unique pour le chargement initial depuis un poste (outils/transport/charger.mjs).
-- Aucune politique : illisible par l'API. Créés et supprimés à la main dans Supabase, jamais écrits dans le dépôt.
create table if not exists public.transport_jetons (jeton text primary key, cree_le timestamptz not null default now());

alter table public.transport_fichiers enable row level security;
alter table public.transport_colis enable row level security;
alter table public.transport_comptes_rendus enable row level security;
alter table public.transport_jetons enable row level security;

drop policy if exists lecture_associes on public.transport_fichiers;
create policy lecture_associes on public.transport_fichiers for select using ((select public.est_associe()));
drop policy if exists lecture_associes on public.transport_comptes_rendus;
create policy lecture_associes on public.transport_comptes_rendus for select using ((select public.est_associe()));
drop policy if exists ecriture_associes on public.transport_comptes_rendus;
create policy ecriture_associes on public.transport_comptes_rendus for all
  using ((select public.est_associe())) with check ((select public.est_associe()));
-- transport_colis : pas de lecture directe, le board passe par transport_donnees (agrégats).

-- ---------------------------------------------------------------- Import d'un fichier (en un ou plusieurs lots de lignes)
-- p_fichier : en-tête lu par transport-lecteurs.js ; p_lignes : lignes (lot) ; p_suite : id du fichier pour les lots suivants.
-- Renvoie { statut, fichier_id, lignes_ajoutees, doublon_de }.
--   deja     : ce fichier exact a déjà été déposé (rien n'est enregistré)
--   doublon  : autre fichier au contenu déjà intégré (même facture Colissimo, ou toutes les lignes déjà connues)
--   partiel  : une partie des lignes était déjà connue
--   integre  : tout est nouveau
create or replace function public.transport_importer(p_fichier jsonb, p_lignes jsonb, p_jeton text default null, p_suite bigint default null)
returns jsonb language plpgsql security definer set search_path = public, pg_catalog as $$
declare
  v_id bigint; v_exist record; v_ajout int; v_total int; v_dbl bigint; v_statut text;
begin
  if not (public.est_associe() or (p_jeton is not null and exists (select 1 from transport_jetons where jeton = p_jeton))) then
    raise exception 'Accès au board Transport non autorisé';
  end if;

  if p_suite is null then
    select id, nom_fichier into v_exist from transport_fichiers where empreinte = p_fichier->>'empreinte';
    if found then
      return jsonb_build_object('statut', 'deja', 'fichier_id', v_exist.id, 'lignes_ajoutees', 0, 'termine', true, 'doublon_de', v_exist.nom_fichier);
    end if;
    -- Colissimo : une facture déjà intégrée sous un autre nom de fichier
    if p_fichier->>'transporteur' = 'Colissimo' then
      select id, nom_fichier into v_exist from transport_fichiers
      where transporteur = 'Colissimo' and num_facture = p_fichier->>'num_facture' and statut in ('integre', 'partiel') limit 1;
      if found then
        insert into transport_fichiers (transporteur, format, service, compte, nom_fichier, empreinte, num_facture, date_facture, mois,
          periode_du, periode_au, colis, nb_lignes, montant_ht, prestations_ht, indemnites_ht, avoirs_ht, total_facture_ht, statut, doublon_de, details, importe_par)
        select x.transporteur, x.format, x.service, x.compte, x.nom_fichier, x.empreinte, x.num_facture, x.date_facture, x.mois,
          x.periode_du, x.periode_au, x.colis, x.nb_lignes, x.montant_ht, coalesce(x.prestations_ht, 0), coalesce(x.indemnites_ht, 0), coalesce(x.avoirs_ht, 0),
          x.total_facture_ht, 'doublon', v_exist.id, x.details, coalesce(auth.jwt()->>'email', 'chargement initial')
        from jsonb_populate_record(null::transport_fichiers, p_fichier) x
        returning id into v_id;
        return jsonb_build_object('statut', 'doublon', 'fichier_id', v_id, 'lignes_ajoutees', 0, 'termine', true, 'doublon_de', v_exist.nom_fichier);
      end if;
    end if;
    insert into transport_fichiers (transporteur, format, service, compte, nom_fichier, empreinte, num_facture, date_facture, mois,
      periode_du, periode_au, colis, nb_lignes, montant_ht, prestations_ht, indemnites_ht, avoirs_ht, total_facture_ht, statut, details, importe_par)
    select x.transporteur, x.format, x.service, x.compte, x.nom_fichier, x.empreinte, x.num_facture, x.date_facture, x.mois,
      x.periode_du, x.periode_au, x.colis, x.nb_lignes, x.montant_ht, coalesce(x.prestations_ht, 0), coalesce(x.indemnites_ht, 0), coalesce(x.avoirs_ht, 0),
      x.total_facture_ht, 'integre', x.details, coalesce(auth.jwt()->>'email', 'chargement initial')
    from jsonb_populate_record(null::transport_fichiers, p_fichier) x
    returning id into v_id;
  else
    v_id := p_suite;
    if not exists (select 1 from transport_fichiers where id = v_id and statut <> 'retire') then raise exception 'Fichier % inconnu', v_id; end if;
  end if;

  with l as (
    select * from jsonb_to_recordset(p_lignes) as x(
      mode text, code_service text, date_envoi date, num_facture text, num_colis text, ref_envoi text, colis int, poids_kg numeric,
      cp text, pays text, region text, tranche text, transport numeric, gasoil numeric, taxes numeric, annexes numeric,
      annexes_detail jsonb, cle text)
  ), ins as (
    insert into transport_colis (fichier_id, transporteur, mode, code_service, date_envoi, num_facture, num_colis, ref_envoi, colis,
      poids_kg, cp, pays, region, tranche, transport, gasoil, taxes, annexes, annexes_detail, cle)
    select v_id, p_fichier->>'transporteur', mode, code_service, date_envoi, num_facture, num_colis, ref_envoi, coalesce(colis, 0),
      poids_kg, cp, pays, coalesce(region, 'Inconnue'), coalesce(tranche, 'inconnue'), coalesce(transport, 0), coalesce(gasoil, 0),
      coalesce(taxes, 0), coalesce(annexes, 0), annexes_detail, cle
    from l
    on conflict (cle) do nothing
    returning 1
  )
  select count(*) into v_ajout from ins;

  update transport_fichiers set lignes_ajoutees = lignes_ajoutees + v_ajout where id = v_id
  returning lignes_ajoutees, nb_lignes into v_ajout, v_total;
  -- Statut du fichier d'après ce qui a été ajouté jusqu'ici (définitif après le dernier lot)
  if v_ajout = 0 then
    select c.fichier_id into v_dbl from jsonb_to_recordset(p_lignes) as x(cle text)
      join transport_colis c on c.cle = x.cle and c.fichier_id <> v_id limit 1;
    v_statut := 'doublon';
  elsif v_ajout < v_total then
    v_statut := 'partiel';
  else
    v_statut := 'integre';
  end if;
  update transport_fichiers set statut = v_statut, doublon_de = coalesce(v_dbl, doublon_de) where id = v_id;
  return jsonb_build_object('statut', v_statut, 'fichier_id', v_id, 'lignes_ajoutees', v_ajout, 'termine', false,
    'doublon_de', (select nom_fichier from transport_fichiers where id = v_dbl));
end $$;

-- Retirer un fichier déposé par erreur : il reste enregistré (statut « retiré ») mais ses lignes ne comptent plus.
create or replace function public.transport_retirer_fichier(p_id bigint, p_retirer boolean default true)
returns void language plpgsql security definer set search_path = public, pg_catalog as $$
begin
  if not public.est_associe() then raise exception 'Accès au board Transport non autorisé'; end if;
  update transport_fichiers set statut = case when p_retirer then 'retire' else
    case when lignes_ajoutees = 0 then 'doublon' when lignes_ajoutees < nb_lignes then 'partiel' else 'integre' end end
  where id = p_id;
end $$;

-- ---------------------------------------------------------------- Données du board (agrégats sur une période d'envoi)
create or replace function public.transport_donnees(p_du date, p_au date)
returns jsonb language plpgsql stable security definer set search_path = public, pg_catalog as $$
declare r jsonb;
begin
  if not public.est_associe() then raise exception 'Accès au board Transport non autorisé'; end if;
  with c as (
    select c.* from transport_colis c join transport_fichiers f on f.id = c.fichier_id and f.statut <> 'retire'
    where c.date_envoi between p_du and p_au
  )
  select jsonb_build_object(
    -- par mois × mode × tranche : [mois, mode, tranche, colis, envois, kg, transport, gasoil, taxes, annexes]
    'cube', coalesce((select jsonb_agg(jsonb_build_array(mois, mode, tranche, colis, envois, kg, transport, gasoil, taxes, annexes) order by mois, mode, tranche) from (
      select to_char(date_envoi, 'YYYY-MM') mois, mode, tranche, sum(colis) colis,
        sum(colis) filter (where transporteur = 'Colissimo')
          + count(distinct coalesce(ref_envoi, num_colis)) filter (where transporteur = 'DPD' and colis > 0) envois,
        round(coalesce(sum(poids_kg) filter (where colis > 0), 0), 1) kg,
        sum(transport) transport, sum(gasoil) gasoil, sum(taxes) taxes, sum(annexes) annexes
      from c group by 1, 2, 3) x), '[]'::jsonb),
    -- par région : [mode, tranche, region, colis, kg, coût]
    'regions', coalesce((select jsonb_agg(jsonb_build_array(mode, tranche, region, colis, kg, cout)) from (
      select mode, tranche, region, sum(colis) colis, round(coalesce(sum(poids_kg) filter (where colis > 0), 0), 1) kg,
        sum(transport + gasoil + taxes + annexes) cout
      from c group by 1, 2, 3) x), '[]'::jsonb),
    -- barème constaté par kilo entamé (colis pesés) : [mode, kg, colis, coût standard = transport + gasoil + taxes]
    'bareme', coalesce((select jsonb_agg(jsonb_build_array(mode, kg, colis, cout) order by mode, kg) from (
      select mode, least(ceil(poids_kg / colis), 31)::int kg, sum(colis) colis, sum(transport + gasoil + taxes) cout
      from c where colis > 0 and poids_kg > 0 group by 1, 2) x), '[]'::jsonb),
    -- frais annexes par nature : [mode, libellé, lignes, montant]
    'annexes', coalesce((select jsonb_agg(jsonb_build_array(mode, lib, n, montant) order by montant desc) from (
      select c.mode, e.key lib, count(*) n, sum((e.value)::numeric) montant
      from c, jsonb_each_text(c.annexes_detail) e
      where e.key <> 'Tarif unitaire brut' group by 1, 2) x), '[]'::jsonb),
    -- éléments de facture hors colis (Colissimo) dont la facture tombe dans la période
    'hors_colis', (select jsonb_build_object('prestations', coalesce(sum(prestations_ht), 0), 'indemnites', coalesce(sum(indemnites_ht), 0),
        'avoirs', coalesce(sum(avoirs_ht), 0))
      from transport_fichiers where statut in ('integre', 'partiel') and coalesce(periode_au, date_facture) between p_du and p_au),
    'bornes', (select jsonb_build_object('min', min(date_envoi), 'max', max(date_envoi)) from transport_colis)
  ) into r;
  return r;
end $$;

-- Fichiers lus (grille de couverture) : lecture directe de transport_fichiers (politique lecture_associes).
