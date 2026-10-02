-- Nexus (client EBP CL00803) : refacturation entre sociétés du groupe, à isoler dans la famille « Intragroupe » (demandé par Jérémy le 02/10/2026).
-- La facture FA00004605 du 30/09/2026 (190 508,51 € HT : matières premières, salaires, matériel…) n'est pas encore dans la base
-- (import EBP de fin septembre à relancer). La fiche est créée d'avance, segment validé, pour qu'elle arrive directement dans la bonne famille.
-- Retour arrière : delete from clients_sources where source = 'ebp' and source_client_id = 'CL00803'; delete from clients where client_id = 'ebp:CL00803';

insert into clients (client_id, client_nom, canal_origine, segment, segment_valide, groupe_client, actif, note)
values ('ebp:CL00803', 'NEXUS', 'ebp', 'INTRAGROUPE', true, 'Intragroupe', true, 'Intragroupe validé par Jérémy le 02/10/2026 : refacturations Nexus, à part du CA des ventes')
on conflict (client_id) do update set segment = 'INTRAGROUPE', segment_valide = true, groupe_client = 'Intragroupe', note = excluded.note, maj_le = now();

insert into clients_sources (source, source_client_id, client_id)
values ('ebp', 'CL00803', 'ebp:CL00803')
on conflict do nothing;
