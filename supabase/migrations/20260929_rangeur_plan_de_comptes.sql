-- Plan de comptes du rangeur de factures (29/09/2026) : dans « 2 - CLASSEES », une facture est rangée dans
-- <exercice>/<mois>/<livre de compte>, ex. 2025-2026/2025-10_octobre/60262000_CARTON (document 39 de Jérémy, point 4).
-- Libellés : grand livre tel que noté dans regles.xlsx V5 (outils/factures/plan-de-comptes.mjs) ; chargés par
-- 20260929_rangeur_plan_de_comptes_donnees.sql. Un compte absent donne un dossier « <numéro>_A-LIBELLER ».
-- Quand Jérémy fournira son onglet « Plan de comptes » (124 comptes), on recharge : les libellés modifiés à la main sont gardés.

create table if not exists factures_comptes (
  compte text primary key check (compte ~ '^\d{6,8}$'),
  libelle text,
  source text,
  modifie_par text,
  modifie_le timestamptz not null default now()
);
alter table factures_comptes enable row level security;
drop policy if exists lecture_factures on factures_comptes;
create policy lecture_factures on factures_comptes for select to authenticated using ((select acces_factures()) is not null);

-- Nom du dossier Drive d'un compte : « 60262000_CARTON » ; sans libellé : « 60262000_A-LIBELLER »
create or replace function public.dossier_compte(p_compte text)
returns text language sql stable set search_path = public as $$
  select p_compte || '_' || coalesce(nullif(trim(both '-' from regexp_replace(upper(translate(c.libelle,
    'àâäéèêëîïôöùûüçÀÂÄÉÈÊËÎÏÔÖÙÛÜÇ', 'aaaeeeeiioouuucAAAEEEEIIOOUUUC')), '[^A-Z0-9]+', '-', 'g')), ''), 'A-LIBELLER')
  from (select p_compte as compte) k left join factures_comptes c on c.compte = k.compte
$$;

-- Où ranger une facture classée : appelé par le flux n8n après lire-facture (clé service uniquement).
-- Compte de rangement = le compte unique, sinon celui qui porte le plus gros montant de la ventilation.
create or replace function public.factures_chemin_rangement(p_id bigint)
returns jsonb language sql stable security definer set search_path = public as $$
  with f as (
    select id, date_facture, coalesce(compte, (select v->>'compte' from jsonb_array_elements(ventilation) v order by abs((v->>'montant_ht')::numeric) desc limit 1)) as compte
    from factures_achats where id = p_id
  )
  select jsonb_build_object(
    'id', f.id,
    'exercice', case when extract(month from f.date_facture) >= 10 then extract(year from f.date_facture)::int || '-' || (extract(year from f.date_facture)::int + 1)
                     else (extract(year from f.date_facture)::int - 1) || '-' || extract(year from f.date_facture)::int end,
    'mois', to_char(f.date_facture, 'YYYY-MM') || '_' || (array['janvier','février','mars','avril','mai','juin','juillet','août','septembre','octobre','novembre','décembre'])[extract(month from f.date_facture)::int],
    'compte', f.compte,
    'dossier_compte', case when f.compte is null then 'SANS-COMPTE' else dossier_compte(f.compte) end)
  from f where f.date_facture is not null
$$;
revoke execute on function public.factures_chemin_rangement(bigint) from public, anon, authenticated;
grant execute on function public.factures_chemin_rangement(bigint) to service_role;
