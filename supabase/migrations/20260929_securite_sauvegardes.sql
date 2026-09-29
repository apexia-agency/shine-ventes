-- Sécurité (29/09/2026) : trois tables de sauvegarde créées les 25 et 26/09 (avant les doublons de bascule et les
-- fusions de clients) n'avaient pas la sécurité par ligne (RLS) : lisibles ET modifiables par n'importe qui avec la
-- clé publique du board (rôle anon), dont bak_clients_20260926 = 68 893 fiches clients (noms, TVA, SIRET, notes).
-- Correction : RLS activée sans aucune règle d'accès (personne ne lit par l'API ; les fonctions et le service les
-- utilisent toujours), et droits retirés aux rôles anon et authenticated. Les sauvegardes restent utilisables pour
-- les retours arrière (defaire_fusion_email, bascule).
alter table public.bak_pieces_pro_20260925 enable row level security;
alter table public.bak_clients_20260926 enable row level security;
alter table public.bak_clients_sources_20260926 enable row level security;
revoke all on public.bak_pieces_pro_20260925, public.bak_clients_20260926, public.bak_clients_sources_20260926 from anon, authenticated;

-- Fonctions de l'onglet « À valider » : déjà protégées de l'intérieur (est_associe), mais inutile qu'une personne
-- non connectée puisse les appeler.
revoke execute on function public.propositions_fusion_liste() from anon, public;
revoke execute on function public.questions_liste() from anon, public;
grant execute on function public.propositions_fusion_liste() to authenticated;
grant execute on function public.questions_liste() to authenticated;
