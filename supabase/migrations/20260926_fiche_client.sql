-- Fiche client du board (clic sur un nom de client) : voir la fonction fiche_client appliquée le 26/09/2026.
-- Index ajoutés pour retrouver vite les factures d'un client.
create index if not exists clients_sources_client on public.clients_sources (client_id);
create index if not exists ventes_pieces_client on public.ventes_pieces (source, source_client_id);
-- La définition complète de public.fiche_client(p_client text) est dans la base (security invoker, lecture associés) :
--   identité (clients), CA produits par mois et par exercice, 25 premiers produits par exercice, 40 dernières factures, totaux.
