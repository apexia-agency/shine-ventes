-- Rangeur de factures V7 (07/10/2026) : rapprochement bancaire.
-- Les relevés déposés dans le Drive « Factures SHINE / 4 - BANQUE A DEPOSER » (CSV Crédit Agricole, CIC, PayPal) sont lus par la fonction
-- livre-achats (action « releve ») et chargés ici sans doublon (empreinte : banque, date, libellé, montants, rang dans le fichier).
-- Le livre des achats du mois reçoit un onglet « Rapprochement banque » : factures payées, paiements sans facture, factures des mois
-- précédents, mouvements sans facture d'achat (prêts, impôts, banque, compte courant Space Up, remboursements de clients).
-- Règles : celles du plan de trésorerie (« Règles banque » de regles.xlsx), chargées à part dans banque_regles (elles contiennent
-- des prénoms de salariés, pas dans le dépôt). Correspondances « nom à la banque → nom dans le livre » dans banque_correspondances.
-- Retour arrière : drop de factures_banque_donnees et des trois tables.

create table if not exists banque_operations (
  id bigserial primary key,
  empreinte text not null unique,
  banque text not null,            -- CA, CIC, PayPal
  date date not null,
  libelle text not null,
  debit numeric not null default 0,
  credit numeric not null default 0,
  fichier text,                    -- relevé d'origine
  charge_le timestamptz not null default now()
);
create index if not exists banque_operations_date on banque_operations (date);

create table if not exists banque_regles (
  id serial primary key,
  ordre int not null,
  sens text not null check (sens in ('D', 'C', 'X')),
  motif text not null,
  onglet text not null,            -- catégorie du plan de trésorerie (ACHATS, SALAIRES, DETTE…)
  ligne text,
  source text not null default 'regles.xlsx (Règles banque)'
);

create table if not exists banque_correspondances (
  id serial primary key,
  banque text not null unique,     -- mot du libellé bancaire
  livre text not null,             -- nom du fournisseur dans le livre
  note text,
  modifie_le timestamptz not null default now()
);
insert into banque_correspondances (banque, livre, note) values
  ('LOLA POIREAU', 'MEEMO', 'factures Meemo payées à Lola Poireau (F-2025-0025)'),
  ('CHIMIE RECHERCHE ENVIRON', 'CREE', 'Chimie Recherche Environnement'),
  ('SCAPAUTO', 'LECLERC', 'frais de gestion Leclerc payés à Scapauto'),
  ('FORGET ABOUT IT', 'CLEDERE CINDY', 'infogérance'),
  ('LE GROUPE LA POSTE', 'COLISSIMO', null),
  ('GOOGLE IRELAND', 'GOOGLE', 'Google Ads'),
  ('CM-CIC LEASING', 'MUTUALEASE', null),
  ('GAN ASS ENC', 'GAN ASSURANCES', null),
  ('CREDIT AGRICOLE LEASIN', 'CREDIT AGRICOLE LEASING', null),
  ('ELECTRICITE DE FRANCE', 'EDF', null),
  ('SCI SCHADLI', 'CHADLI', 'loyer'),
  ('FRANFINANCE', 'FRANFINANCE', null),
  ('CARMONA', 'CARMONA', 'location de stockage')
on conflict (banque) do nothing;

alter table banque_operations enable row level security;
alter table banque_regles enable row level security;
alter table banque_correspondances enable row level security;
drop policy if exists lecture_factures on banque_operations;
drop policy if exists lecture_factures on banque_regles;
drop policy if exists lecture_factures on banque_correspondances;
create policy lecture_factures on banque_operations for select to authenticated using ((select acces_factures()) is not null);
create policy lecture_factures on banque_regles for select to authenticated using ((select acces_factures()) is not null);
create policy lecture_factures on banque_correspondances for select to authenticated using ((select acces_factures()) is not null);

-- Données du rapprochement d'un mois : paiements du mois, factures du rangeur des 6 mois précédents (à payer),
-- lignes du grand livre des 12 mois précédents (factures déjà passées), règles et correspondances
create or replace function public.factures_banque_donnees(p_mois text)
returns jsonb language sql stable security definer set search_path = public as $$
  with m as (select to_date(p_mois || '-01', 'YYYY-MM-DD') as debut, (to_date(p_mois || '-01', 'YYYY-MM-DD') + interval '1 month')::date as fin)
  select jsonb_build_object(
    'operations', coalesce((select jsonb_agg(jsonb_build_object('banque', o.banque, 'date', o.date, 'libelle', o.libelle, 'debit', o.debit, 'credit', o.credit) order by o.date, o.id)
      from banque_operations o, m where o.date >= m.debut and o.date < m.fin), '[]'::jsonb),
    'factures', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'fournisseur', coalesce(fo.nom, a.fournisseur), 'alias', coalesce(to_jsonb(fo.alias), '[]'::jsonb),
        'num_facture', a.num_facture, 'date_facture', a.date_facture, 'montant_ttc', a.montant_ttc, 'statut', a.statut))
      from factures_achats a left join factures_fournisseurs fo on fo.id = a.fournisseur_id, m
      where a.lecture is not null and a.statut <> 'ecartee' and a.date_facture >= m.debut - interval '6 months' and a.date_facture < m.fin), '[]'::jsonb),
    'livre', coalesce((select jsonb_agg(jsonb_build_object('date', g.date, 'libelle', g.libelle, 'debit', g.debit))
      from factures_grand_livre g, m where g.date >= m.debut - interval '13 months' and g.date < m.fin), '[]'::jsonb),
    'regles', coalesce((select jsonb_agg(jsonb_build_object('ordre', r.ordre, 'sens', r.sens, 'motif', r.motif, 'onglet', r.onglet, 'ligne', r.ligne)) from banque_regles r), '[]'::jsonb),
    'correspondances', coalesce((select jsonb_agg(jsonb_build_object('banque', c.banque, 'livre', c.livre)) from banque_correspondances c), '[]'::jsonb))
$$;
revoke execute on function public.factures_banque_donnees(text) from public, anon, authenticated;
grant execute on function public.factures_banque_donnees(text) to service_role;
