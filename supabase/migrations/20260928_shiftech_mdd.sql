-- Shiftech = MDD (Robin, 28/09/2026). Appliqué le 28/09/2026.
-- Clients EBP Shiftech, jusque-là revendeurs (« Autres réseaux ») : Tours (6 167 € en 2025-2026, dont 5 828 € de
-- produits SHTC à la marque Shiftech), Nantes (861 € + 86 €), Strasbourg (172 €) → segment MDD, sous-segment Shiftech.
-- Les comptes « Shiftech » du site particuliers dans le groupe « Client » restent en Particuliers (règle : le groupe
-- client fait foi, groupe Client = tarif particulier). Le groupe « Shiftech » du site particuliers passe en MDD.
update clients set segment = 'MDD', sous_segment = 'Shiftech', segment_valide = true, maj_le = now(),
  note = trim(coalesce(note, '') || ' — MDD (Shiftech) validé par Robin le 28/09/2026, avant : ' || segment || coalesce(' / ' || sous_segment, ''))
where client_id in ('ebp:CL00713', 'ebp:CL00769', 'ebp:CL00439') and segment <> 'MDD';
update agg_clients set segment = 'MDD', segment_valide = true where client_id in ('ebp:CL00713', 'ebp:CL00769', 'ebp:CL00439');
update groupes_segments set segment_propose = 'MDD', sous_segment_propose = 'Shiftech', note = 'Shiftech = MDD (Robin, 28/09/2026)'
where source = 'prestashop_b2c' and groupe_client = 'Shiftech';
update ebp_clients_import set segment = 'MDD', sous_segment = 'Shiftech' where code in ('CL00713', 'CL00769', 'CL00439');

-- L'import des clients EBP écrasait segment et sous-segment même après une validation manuelle dans le board.
-- Désormais une validation manuelle (note « validé par … ») est toujours gardée.
do $$
declare d text;
  a1 text := 'sous_segment = excluded.sous_segment, segment = case when clients.segment_valide and not excluded.segment_valide then clients.segment else excluded.segment end,';
  b1 text := 'sous_segment = case when clients.note ilike ''%validé par%'' then clients.sous_segment else excluded.sous_segment end, segment = case when clients.note ilike ''%validé par%'' or (clients.segment_valide and not excluded.segment_valide) then clients.segment else excluded.segment end,';
begin
  d := pg_get_functiondef('public.importer_clients_ebp(jsonb)'::regprocedure);
  if position('validé par' in d) > 0 then return; end if;
  d := regexp_replace(d, '\s+', ' ', 'g');
  if position(a1 in d) = 0 then raise exception 'texte attendu introuvable'; end if;
  d := replace(d, a1, b1);
  execute d;
end $$;

-- Puis : select finaliser_collecte();  (les onglets Revendeurs / MDD se mettent à jour)
