-- Propositions de fusion de fiches clients EBP / PrestaShop, validées une par une dans le board
-- (carte « Fusions de clients à valider », section Données, validation et export). Appliqué le 28/09/2026.
-- Remplie le 28/09 : 23 Leclerc (même n° de magasin), 29 autres paires sûres (même société), 7 à confirmer
-- (Auto Loisir Bergeracoise : 2 magasins EBP pour 1 compte site ; statuts différents Shiftech, Cover Custom, Netexpert ;
-- noms proches Fresh/French Detailer, Detailing Supreme/Supreme Shine), + Leclerc IFS 7014 déjà fusionné à l'essai.
-- decider_fusion : 'valider' → fusionner_clients_manuel (voir 20260928_fusion_clients_manuelle.sql),
--                  'refuser' → écartée, 'annuler' → defaire_fusion_manuelle. Réservé aux rôles valideur et admin.

create table if not exists propositions_fusion (
  id serial primary key,
  maitre text not null,             -- fiche gardée (EBP)
  absorbe text not null,            -- fiche rattachée (PrestaShop)
  niveau text not null default 'sur' check (niveau in ('sur', 'a_confirmer')),
  raison text,
  statut text not null default 'proposee' check (statut in ('proposee', 'validee', 'refusee')),
  decide_par text,
  decide_le timestamptz,
  cree_le timestamptz not null default now(),
  unique (maitre, absorbe),
  constraint propositions_fusion_distinct check (maitre <> absorbe)
);
alter table propositions_fusion enable row level security;

create or replace function public.propositions_fusion_liste()
returns table (id int, niveau text, raison text, statut text, decide_par text, decide_le timestamptz,
  maitre text, maitre_nom text, maitre_segment text, maitre_ca numeric,
  absorbe text, absorbe_nom text, absorbe_segment text, absorbe_ca numeric)
language sql stable security definer set search_path = public as $$
  select p.id, p.niveau, p.raison, p.statut, p.decide_par, p.decide_le,
    p.maitre, m.client_nom, m.segment, (select round(sum(a.ca_ht)) from agg_clients a where a.client_id = p.maitre),
    p.absorbe, b.client_nom, coalesce((f.etat_maitre->>'segment'), b.segment),
    (select round(sum(ch.total)) from (select sum(l.total_ligne_ht) total from ventes_pieces vp join ventes_lignes l on l.piece_id = vp.id
        join jsonb_to_recordset(coalesce(f.sources, (select jsonb_agg(jsonb_build_object('source', cs.source, 'source_client_id', cs.source_client_id)) from clients_sources cs where cs.client_id = p.absorbe))) s(source text, source_client_id text)
          on vp.source = s.source and vp.source_client_id = s.source_client_id
        where vp.retenue) ch)
  from propositions_fusion p join clients m on m.client_id = p.maitre join clients b on b.client_id = p.absorbe
  left join fusions_clients_manuelles f on f.absorbe = p.absorbe
  where (select est_associe())
  order by (p.statut = 'proposee') desc, (p.niveau = 'sur') desc, p.id
$$;

create or replace function public.decider_fusion(p_id int, p_decision text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r text; p propositions_fusion; qui text := (select auth.jwt()->>'email');
begin
  select role into r from acces_board where lower(email) = lower(qui);
  if r is null or r not in ('valideur', 'admin') then raise exception 'Accès refusé'; end if;
  select * into p from propositions_fusion where id = p_id for update;
  if not found then raise exception 'Proposition inconnue'; end if;
  if p_decision = 'valider' then
    if p.statut <> 'validee' then
      perform fusionner_clients_manuel(p.maitre, p.absorbe, 'même client EBP / PrestaShop, validé par ' || qui);
    end if;
    update propositions_fusion set statut = 'validee', decide_par = qui, decide_le = now() where id = p_id;
  elsif p_decision = 'refuser' then
    if p.statut = 'validee' then raise exception 'Annule d''abord la fusion'; end if;
    update propositions_fusion set statut = 'refusee', decide_par = qui, decide_le = now() where id = p_id;
  elsif p_decision = 'annuler' then
    if p.statut = 'validee' then perform defaire_fusion_manuelle(p.absorbe); end if;
    update propositions_fusion set statut = 'proposee', decide_par = null, decide_le = null where id = p_id;
  else raise exception 'Décision inconnue';
  end if;
  return jsonb_build_object('ok', true);
end $$;

revoke execute on function public.decider_fusion(int, text) from public, anon;
grant execute on function public.decider_fusion(int, text) to authenticated;
grant execute on function public.propositions_fusion_liste() to authenticated;
