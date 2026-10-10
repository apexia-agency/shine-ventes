-- Appliquée dans Supabase le 25/09/2026 (version 20260925142552), exportée dans le dépôt le 10/10/2026.

-- Lecture du Data Center : un seul appel par période (le comparateur appelle deux fois).
-- Accès : rôle défini pour le board 'data_center' dans acces_board (ou admin global).
create or replace function public.dc_donnees(p_du date, p_au date)
returns jsonb language plpgsql stable security definer set search_path = marketing, public, pg_catalog as $$
declare v_role text; r jsonb := '{}'::jsonb;
begin
  v_role := public.role_board('data_center');
  if v_role is null then raise exception 'Accès au Data Center non autorisé'; end if;

  -- Commerce (PrestaShop particuliers) : par jour
  r := r || jsonb_build_object('commerce', coalesce((
    with p as (
      select pc.id, pc.date_facture jour, pc.avoir, pc.frais_port_facture_ht, pc.source_client_id
      from public.ventes_pieces pc
      join public.groupes_segments g on g.source = 'prestashop_b2c' and g.groupe_client = pc.groupe_client and g.segment_propose = 'B2C'
      where pc.canal = 'prestashop_b2c' and pc.retenue and pc.doublon_de is null and pc.date_facture between p_du and p_au
    ), l as (select piece_id, sum(total_ligne_ht) ca from public.ventes_lignes where piece_id in (select id from p) group by 1)
    select jsonb_agg(x order by x.jour) from (
      select p.jour, count(*) filter (where not p.avoir) commandes, round(coalesce(sum(l.ca),0),2) ca_ht,
             round(coalesce(sum(p.frais_port_facture_ht),0),2) port_ht, count(distinct p.source_client_id) clients
      from p left join l on l.piece_id = p.id group by p.jour) x), '[]'::jsonb));

  -- Nouveaux clients (première commande particulier dans la période)
  r := r || jsonb_build_object('nouveaux_clients', (
    select count(*) from (
      select pc.source_client_id, min(pc.date_facture) premiere
      from public.ventes_pieces pc
      join public.groupes_segments g on g.source = 'prestashop_b2c' and g.groupe_client = pc.groupe_client and g.segment_propose = 'B2C'
      where pc.canal = 'prestashop_b2c' and pc.retenue and pc.doublon_de is null and not pc.avoir
      group by 1) f where f.premiere between p_du and p_au));

  -- Régies par jour et plateforme
  r := r || jsonb_build_object('regie_jour', coalesce((select jsonb_agg(x order by x.jour) from (
      select jour, plateforme, round(sum(depense),2) depense, sum(clics) clics, sum(impressions) impressions,
             round(sum(conversions_revendiquees),1) conv, round(sum(valeur_revendiquee),2) valeur
      from fait_regie_jour where jour between p_du and p_au group by 1,2) x), '[]'::jsonb));

  -- GA4 total par jour
  r := r || jsonb_build_object('ga4_jour', coalesce((select jsonb_agg(x order by x.jour) from (
      select jour, sessions, sessions_engagees, utilisateurs, transactions, ca_mesure, sessions_sans_page_entree
      from fait_analytics_total_jour where jour between p_du and p_au) x), '[]'::jsonb));

  -- Canaux GA4 (période)
  r := r || jsonb_build_object('canaux', coalesce((select jsonb_agg(x order by x.sessions desc) from (
      select coalesce(canal,'Unassigned') canal, sum(sessions) sessions, sum(sessions_engagees) engagees,
             sum(transactions) transactions, round(sum(ca_mesure),2) ca
      from fait_analytics_jour where jour between p_du and p_au group by 1) x), '[]'::jsonb));

  -- Sources / supports GA4 (top 40)
  r := r || jsonb_build_object('sources', coalesce((select jsonb_agg(x) from (
      select source || ' / ' || medium sm, max(canal) canal, sum(sessions) sessions, sum(sessions_engagees) engagees,
             sum(transactions) transactions, round(sum(ca_mesure),2) ca
      from fait_analytics_jour where jour between p_du and p_au group by 1 order by 3 desc limit 40) x), '[]'::jsonb));

  -- Campagnes payantes : régie + GA4 (jointure par identifiant, puis nom historisé)
  r := r || jsonb_build_object('campagnes', coalesce((select jsonb_agg(x order by x.depense desc) from (
      select plateforme, campagne_id, max(campagne) campagne, round(sum(depense),2) depense, sum(clics) clics, sum(impressions) impressions,
             round(sum(conv_rev),1) conv_rev, round(sum(valeur_rev),2) valeur_rev,
             sum(sessions) sessions, sum(sessions_engagees) engagees, sum(transactions) transactions, round(sum(ca_mesure),2) ca_mesure
      from v_perf_campagne_jour where jour between p_du and p_au group by 1,2 having sum(depense) > 0) x), '[]'::jsonb));

  -- Réseaux (Google : SEARCH/YOUTUBE/DISCOVER… ; Meta : facebook/instagram/audience_network…)
  r := r || jsonb_build_object('reseaux', coalesce((select jsonb_agg(x order by x.depense desc) from (
      select plateforme, reseau, round(sum(depense),2) depense, sum(clics) clics, sum(impressions) impressions,
             round(sum(conversions_revendiquees),1) conv_rev, round(sum(valeur_revendiquee),2) valeur_rev
      from fait_regie_jour where jour between p_du and p_au group by 1,2) x), '[]'::jsonb));
  r := r || jsonb_build_object('reseaux_jour', coalesce((select jsonb_agg(x order by x.jour) from (
      select jour, plateforme, reseau, round(sum(depense),2) depense, sum(clics) clics, round(sum(valeur_revendiquee),2) valeur_rev
      from fait_regie_jour where jour between p_du and p_au group by 1,2,3) x), '[]'::jsonb));

  -- Publicités Meta + ce que GA4 mesure par utm_content (nom de pub)
  r := r || jsonb_build_object('pubs', coalesce((select jsonb_agg(x order by x.depense desc) from (
      select p.plateforme, p.pub_nom, max(p.groupe_nom) groupe, max(dc.nom_actuel) campagne, round(sum(p.depense),2) depense,
             sum(p.impressions) impressions, sum(p.clics_lien) clics_lien, round(sum(p.conversions_revendiquees),1) conv_rev,
             round(sum(p.valeur_revendiquee),2) valeur_rev,
             (select sum(a.sessions) from fait_analytics_jour a where a.contenu_brut = p.pub_nom and a.jour between p_du and p_au) sessions,
             (select sum(a.transactions) from fait_analytics_jour a where a.contenu_brut = p.pub_nom and a.jour between p_du and p_au) transactions,
             (select round(sum(a.ca_mesure),2) from fait_analytics_jour a where a.contenu_brut = p.pub_nom and a.jour between p_du and p_au) ca_mesure
      from fait_regie_pub_jour p left join dim_campagne dc on dc.plateforme = p.plateforme and dc.campagne_id = p.campagne_id
      where p.jour between p_du and p_au group by p.plateforme, p.pub_nom having sum(p.depense) > 0 limit 60) x), '[]'::jsonb));

  -- Pages d'entrée (top 25)
  r := r || jsonb_build_object('pages', coalesce((select jsonb_agg(x) from (
      select page_entree, sum(sessions) sessions, sum(sessions_engagees) engagees, sum(transactions) transactions, round(sum(ca_mesure),2) ca
      from fait_analytics_page_jour where jour between p_du and p_au group by 1 order by 2 desc limit 25) x), '[]'::jsonb));

  -- Organique, e-mail, SEO
  r := r || jsonb_build_object('organique', coalesce((select jsonb_agg(x) from (
      select plateforme, max(abonnes) abonnes, sum(abonnes_gagnes) gagnes, sum(impressions) impressions, sum(portee) portee,
             sum(vues) vues, sum(engagements) engagements, sum(clics_lien) clics_lien, sum(publications) publications
      from fait_organique_jour where jour between p_du and p_au group by 1) x), '[]'::jsonb));
  r := r || jsonb_build_object('posts', coalesce((select jsonb_agg(x) from (
      select plateforme, post_id, publie_le, format, left(legende,140) legende, lien, vues, portee, engagements, likes, commentaires, partages, enregistrements
      from fait_organique_post where publie_le::date between p_du and p_au order by coalesce(engagements,0) desc limit 30) x), '[]'::jsonb));
  r := r || jsonb_build_object('emails', coalesce((select jsonb_agg(x order by x.envoye_le desc) from (
      select campagne_id, nom, type_envoi, envoye_le, destinataires, delivres, ouvertures_uniques, clics_uniques, desabonnements,
             commandes_revendiquees, ca_revendique
      from fait_email_campagne where envoye_le::date between p_du and p_au) x), '[]'::jsonb));
  r := r || jsonb_build_object('seo_jour', coalesce((select jsonb_agg(x order by x.jour) from (
      select jour, clics, impressions, position from fait_seo_jour where requete = '(total)' and jour between p_du and p_au) x), '[]'::jsonb));
  r := r || jsonb_build_object('seo_requetes', coalesce((select jsonb_agg(x) from (
      select requete, sum(clics) clics, sum(impressions) impressions, round(avg(position),1) position
      from fait_seo_jour where requete <> '(total)' and jour between p_du and p_au group by 1 order by 2 desc limit 25) x), '[]'::jsonb));

  -- Fiabilité
  r := r || jsonb_build_object('fiabilite', coalesce((select jsonb_agg(x order by x.du) from (
      select du, au, plateforme, perimetre, metrique, fiabilite, raison from evenement_qualite
      where du <= p_au and coalesce(au, 'infinity'::date) >= p_du and fiabilite <> 'fiable') x), '[]'::jsonb));
  r := r || jsonb_build_object('controles_ko', coalesce((select jsonb_agg(x order by x.jour) from (
      select jour, source, controle, attendu, obtenu, ecart_pct from controle_ingestion
      where jour between p_du and p_au and not ok) x), '[]'::jsonb));
  r := r || jsonb_build_object('fraicheur', (select jsonb_object_agg(source, fin) from (
      select source, max(fin) fin from journal_ingestion where statut = 'ok' group by 1) x));
  r := r || jsonb_build_object('preconisations', coalesce((select jsonb_agg(x order by x.cree_le desc) from (
      select id, cree_le, origine, gravite, titre, constat, action_proposee, gain_estime, fiabilite_donnee, statut, plateforme, perimetre
      from preconisation where statut in ('proposee','acceptee') ) x), '[]'::jsonb));
  r := r || jsonb_build_object('role', v_role, 'du', p_du, 'au', p_au);
  return r;
end $$;
revoke all on function public.dc_donnees(date, date) from public, anon;
grant execute on function public.dc_donnees(date, date) to authenticated;

create or replace function public.dc_operations()
returns jsonb language sql stable security definer set search_path = marketing, public as $$
  select case when public.role_board('data_center') is null then '[]'::jsonb
  else coalesce((select jsonb_agg(o order by o.du desc) from marketing.operation o), '[]'::jsonb) end
$$;
revoke all on function public.dc_operations() from public, anon;
grant execute on function public.dc_operations() to authenticated;

-- Préconisations : seuls les admins du board changent le statut
create or replace function public.dc_statuer(p_id bigint, p_statut text)
returns void language plpgsql security definer set search_path = marketing, public as $$
begin
  if public.role_board('data_center') <> 'admin' then raise exception 'Réservé aux administrateurs du Data Center'; end if;
  update marketing.preconisation set statut = p_statut, decide_par = (select auth.jwt()->>'email'), decide_le = now(),
         verifier_le = case when p_statut = 'faite' then current_date + 14 else verifier_le end
  where id = p_id;
end $$;
revoke all on function public.dc_statuer(bigint, text) from public, anon;
grant execute on function public.dc_statuer(bigint, text) to authenticated;
