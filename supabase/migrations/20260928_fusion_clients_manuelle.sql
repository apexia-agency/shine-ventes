-- Fusions de fiches clients validées à la main (appliqué le 28/09/2026).
-- Cas visé : le même client commande dans EBP et sur PrestaShop sous un nom un peu différent
-- (ex. « Centre Auto Leclerc - IFS DISTRIBUTION - 7014 » dans EBP, « Centre Auto Leclerc - IFS - SAS IFS DISTRIBUTION - 7014 » sur le site).
-- La fiche EBP reste la fiche principale ; la fiche PrestaShop lui est rattachée (clients_sources) puis désactivée.
-- Les factures et le CA ne changent pas : seuls la fiche client et le classement des clients regroupent les deux.
-- Règle de Robin : on ne fusionne que des fiches de même statut (revendeur avec revendeur, pro avec pro).
-- Chaque fusion est journalisée dans fusions_clients_manuelles ; retour arrière : select defaire_fusion_manuelle('<fiche absorbée>');

create table if not exists fusions_clients_manuelles (
  absorbe text primary key,
  maitre text not null,
  motif text,
  sources jsonb not null,        -- lignes de clients_sources déplacées
  etat_absorbe jsonb not null,   -- actif, note de la fiche absorbée avant fusion
  etat_maitre jsonb not null,    -- segment de la fiche maître avant fusion
  fait_le timestamptz not null default now()
);
alter table fusions_clients_manuelles enable row level security;

create or replace function public.fusionner_clients_manuel(p_maitre text, p_absorbe text, p_motif text)
returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if p_maitre = p_absorbe then raise exception 'Même fiche'; end if;
  if not exists (select 1 from clients where client_id = p_maitre and actif) then raise exception 'Fiche maître % absente ou inactive', p_maitre; end if;
  if not exists (select 1 from clients where client_id = p_absorbe and actif) then raise exception 'Fiche % absente ou déjà fusionnée', p_absorbe; end if;
  insert into fusions_clients_manuelles (absorbe, maitre, motif, sources, etat_absorbe, etat_maitre)
  select p_absorbe, p_maitre, p_motif,
    (select coalesce(jsonb_agg(jsonb_build_object('source', source, 'source_client_id', source_client_id)), '[]') from clients_sources where client_id = p_absorbe),
    (select jsonb_build_object('actif', actif, 'note', note) from clients where client_id = p_absorbe),
    (select jsonb_build_object('segment', segment, 'sous_segment', sous_segment, 'segment_valide', segment_valide) from clients where client_id = p_maitre);
  -- Le maître prend le segment validé de l'absorbé s'il n'en a pas lui-même
  update clients m set segment = a.segment, sous_segment = a.sous_segment, segment_valide = true
    from clients a where m.client_id = p_maitre and a.client_id = p_absorbe and not m.segment_valide and a.segment_valide;
  update clients_sources set client_id = p_maitre where client_id = p_absorbe;
  get diagnostics n = row_count;
  update clients set actif = false, note = trim(coalesce(note, '') || ' Fusionnée dans ' || p_maitre || ' (' || coalesce(p_motif, 'fusion manuelle') || ').')
    where client_id = p_absorbe;
  return n;
end $$;

create or replace function public.defaire_fusion_manuelle(p_absorbe text)
returns text language plpgsql security definer set search_path = public as $$
declare f fusions_clients_manuelles;
begin
  select * into f from fusions_clients_manuelles where absorbe = p_absorbe;
  if not found then return null; end if;
  update clients_sources cs set client_id = p_absorbe
    from jsonb_to_recordset(f.sources) s(source text, source_client_id text)
    where cs.source = s.source and cs.source_client_id = s.source_client_id and cs.client_id = f.maitre;
  update clients set actif = (f.etat_absorbe->>'actif')::boolean, note = f.etat_absorbe->>'note' where client_id = p_absorbe;
  update clients set segment = f.etat_maitre->>'segment', sous_segment = f.etat_maitre->>'sous_segment', segment_valide = (f.etat_maitre->>'segment_valide')::boolean
    where client_id = f.maitre;
  delete from fusions_clients_manuelles where absorbe = p_absorbe;
  return f.maitre;
end $$;

revoke execute on function public.fusionner_clients_manuel(text, text, text) from public, anon, authenticated;
revoke execute on function public.defaire_fusion_manuelle(text) from public, anon, authenticated;

-- Essai sur un client (28/09/2026) : Leclerc IFS 7014
-- select fusionner_clients_manuel('ebp:CL00084', 'prestashop_b2c:20813', 'même client EBP / PrestaShop, validé par Robin le 28/09/2026');
