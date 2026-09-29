-- Board « Factures » à part (factures.html), réservé à quelques personnes (Robin, 29/09/2026).
-- Accès : rôle admin, ou acces_board.boards->'factures' = 'lecture' | 'valideur' | 'admin'.
-- Ajouter quelqu'un : update acces_board set boards = coalesce(boards, '{}') || '{"factures": "valideur"}' where email = '…';
-- Les trois fonctions de la file ne passent plus par est_associe() (tout associé) mais par acces_factures().

create or replace function public.acces_factures()
returns text language sql stable security definer set search_path = public as $$
  select case when a.role = 'admin' then 'admin' else nullif(a.boards->>'factures', '') end
  from acces_board a where lower(a.email) = lower((select auth.jwt()->>'email'))
$$;
revoke execute on function public.acces_factures() from public, anon;
grant execute on function public.acces_factures() to authenticated;

create or replace function public.factures_a_verifier_liste()
returns table (id bigint, fichier text, fournisseur text, fournisseur_id int, fournisseur_lu text, fournisseur_tva text, num_facture text,
  date_facture date, montant_ht numeric, montant_tva numeric, montant_ttc numeric, devise text, statut text, motif text, controles jsonb,
  ventilation jsonb, suggestion text, drive_url text, source text, traite_le timestamptz, valide_par text, valide_le timestamptz, regle_apprise text)
language sql stable security definer set search_path = public as $$
  select f.id, f.fichier, f.fournisseur, f.fournisseur_id, f.lecture->>'fournisseur_nom', f.fournisseur_tva, f.num_facture,
    f.date_facture, f.montant_ht, f.montant_tva, f.montant_ttc, f.devise, f.statut, f.motif, f.controles,
    f.ventilation, f.categorie, f.drive_url, f.source, f.traite_le, f.valide_par, f.valide_le, f.regle_apprise
  from factures_achats f
  where (select acces_factures()) is not null and f.lecture is not null
    and (f.statut = 'a_verifier' or (f.statut in ('validee', 'ecartee', 'classee') and coalesce(f.valide_le, f.traite_le) > now() - interval '60 days'))
  order by (f.statut = 'a_verifier') desc, f.date_facture desc nulls last, f.id desc
$$;

drop function if exists public.factures_fournisseurs_liste(); -- colonnes ajoutées : on la recrée
create function public.factures_fournisseurs_liste()
returns table (id int, nom text, compte text, mode text, statut text, territoire text, regime_tva text, alias text[], motifs text[], montant_exercice numeric, modifie_par text)
language sql stable security definer set search_path = public as $$
  select id, nom, compte, mode, statut, territoire, regime_tva, alias, motifs, montant_exercice, modifie_par
  from factures_fournisseurs where (select acces_factures()) is not null order by nom
$$;

-- traiter_facture : même corps qu'avant, seul le contrôle d'accès change (valideur ou admin du board Factures)
do $$
declare def text;
begin
  def := pg_get_functiondef('public.traiter_facture(bigint, text, int, text, boolean, text)'::regprocedure);
  def := replace(def, $r$select role into r from acces_board where lower(email) = lower(qui);
  if r is null or r not in ('valideur', 'admin') then raise exception 'Accès refusé'; end if;$r$,
    $r$r := (select acces_factures());
  if r is null or r not in ('valideur', 'admin') then raise exception 'Accès refusé : board Factures en lecture seule ou non autorisé'; end if;$r$);
  if position('acces_factures' in def) = 0 then raise exception 'traiter_facture : contrôle d''accès introuvable, rien n''est changé'; end if;
  execute def;
end $$;

revoke execute on function public.factures_fournisseurs_liste() from public, anon;
grant execute on function public.factures_fournisseurs_liste() to authenticated;
