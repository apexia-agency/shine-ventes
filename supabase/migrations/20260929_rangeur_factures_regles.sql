-- Rangeur de factures V5 (spécification de Jérémy du 28/09/2026, décidé avec Robin le 29/09/2026).
-- Claude LIT la facture (fournisseur, montants, lignes) ; ces tables DÉCIDENT du compte :
-- fournisseur → territoire (FR / INTRA / IMPORT) → nature → compte. Rien de douteux n'est tranché :
-- la facture part « à vérifier » avec son motif, et Robin vide la file chaque semaine.
-- Les règles viennent de regles.xlsx (onglets Fournisseurs, Fournisseurs à éclater, Dictionnaire produit),
-- nettoyées par outils/factures/fournisseurs-regroupement.mjs ; les données sont chargées par
-- 20260929_rangeur_factures_donnees.sql. Retour arrière : drop des trois tables et des colonnes ajoutées.

-- Un fournisseur réel, reconnu par ses alias (nom de fichier, texte du PDF) ou mieux par son n° de TVA / SIREN
create table if not exists factures_fournisseurs (
  id serial primary key,
  nom text not null unique,
  alias text[] not null default '{}',
  tva_intracom text[] not null default '{}',
  siren text[] not null default '{}',
  compte text,                 -- fournisseur mono-nature : le compte, toujours
  famille int,                 -- famille de regles.xlsx (1 matières premières … 17 investissements)
  regime_tva text check (regime_tva in ('FR', 'AUTOLIQ_UE_BIENS', 'AUTOLIQ_UE_SERVICES', 'AUTOLIQ_IMPORT', 'SANS_TVA')),
  territoire text check (territoire in ('FR', 'INTRA', 'IMPORT')),
  nature text,                 -- MP_CHIMIE, PF_ACCESSOIRE… (dictionnaire produit)
  tva_deductible text,         -- OUI, NON, ou un pourcentage (80 %, 10 %)
  mode text not null default 'mono' check (mode in ('mono', 'eclater')),
  eclatement jsonb,            -- règles propres au fournisseur [{mots, compte, libelle}] ; sinon le dictionnaire produit
  statut text not null default 'a_valider' check (statut in ('ok', 'a_valider', 'hors')),
  motifs text[] not null default '{}',   -- pourquoi « à valider »
  note text,
  notes_jeremy text[] not null default '{}',
  montant_exercice numeric,    -- montant 2025-2026 du grand livre, pour prioriser
  origine text not null default 'regles.xlsx V5 (Jérémy)',
  modifie_par text,
  modifie_le timestamptz not null default now()
);

-- Dictionnaire produit : pour les fournisseurs à éclater, chaque ligne de facture est reconnue par ses mots-clés.
-- Le premier mot trouvé dans l'ordre gagne (le fret avant tout, la cire avant la chimie, l'emballage avant l'accessoire).
create table if not exists factures_dictionnaire (
  nature text primary key,
  ordre int not null,
  mots text[] not null,
  compte_fr text,
  compte_intra text,
  compte_import text,          -- null = pas de compte (à créer par le comptable, ou nature impossible sur ce territoire)
  regle text
);

-- Clés du grand livre qui ne désignent pas un fournisseur : trop vagues (raison sociale à retrouver) ou écartées
create table if not exists factures_cles_ecartees (
  cle text primary key,
  type text not null check (type in ('vague', 'ecartee')),
  motif text,
  compte text,
  montant numeric,
  note text
);

-- La facture lue garde maintenant le résultat du classement par les règles
alter table factures_achats
  add column if not exists statut text not null default 'a_verifier' check (statut in ('classee', 'a_verifier', 'validee', 'ecartee')),
  add column if not exists fournisseur_id int references factures_fournisseurs(id),
  add column if not exists compte text,
  add column if not exists territoire text,
  add column if not exists regime_tva text,
  add column if not exists ventilation jsonb,     -- [{compte, nature, montant_ht, lignes}] : une ou plusieurs imputations
  add column if not exists controles jsonb,       -- [{n, controle, effet, detail}] : contrôles levés
  add column if not exists fournisseur_tva text,
  add column if not exists destinataire text,
  add column if not exists texte_pdf boolean,
  add column if not exists source text,           -- 'serveur' (P:) ou 'drive'
  add column if not exists drive_id text,
  add column if not exists drive_url text,
  add column if not exists lecture jsonb,         -- ce que Claude a lu, tel quel : permet de rejouer les règles sans relire
  add column if not exists texte text;            -- couche texte du PDF (20 000 caractères au plus) ; vide = scan

alter table factures_fournisseurs enable row level security;
alter table factures_dictionnaire enable row level security;
alter table factures_cles_ecartees enable row level security;
drop policy if exists lecture_associes on factures_fournisseurs;
drop policy if exists lecture_associes on factures_dictionnaire;
drop policy if exists lecture_associes on factures_cles_ecartees;
create policy lecture_associes on factures_fournisseurs for select to authenticated using ((select est_associe()));
create policy lecture_associes on factures_dictionnaire for select to authenticated using ((select est_associe()));
create policy lecture_associes on factures_cles_ecartees for select to authenticated using ((select est_associe()));
