-- Appliquée dans Supabase le 25/09/2026 (version 20260925113041), exportée dans le dépôt le 10/10/2026.

-- Chargement idempotent : on remplace la plage [du, au] d'une source par ce que la source renvoie aujourd'hui
-- (les régies et GA4 réécrivent leur passé). Appelé uniquement par l'Edge Function (service_role).
create or replace function public.dc_charger(p_source text, p_du date, p_au date, p_lignes jsonb)
returns jsonb language plpgsql security definer set search_path = marketing, public, pg_catalog as $$
declare n int := 0; v_id bigint;
begin
  insert into marketing.journal_ingestion(source, du, au, statut) values (p_source, p_du, p_au, 'partiel') returning id into v_id;

  if p_source in ('google_ads','meta','tiktok_ads') then
    delete from fait_regie_jour where plateforme = p_source and jour between p_du and p_au;
    insert into fait_regie_jour(jour, plateforme, compte_id, campagne_id, reseau, campagne_nom, impressions, clics, clics_lien,
                                depense, conversions_revendiquees, valeur_revendiquee, fenetre_attribution)
    select (r->>'jour')::date, p_source, r->>'compte_id', r->>'campagne_id', coalesce(nullif(r->>'reseau',''),'TOUS'),
           max(r->>'campagne_nom'), sum((r->>'impressions')::numeric), sum((r->>'clics')::numeric), sum((r->>'clics_lien')::numeric),
           sum((r->>'depense')::numeric), sum((r->>'conversions')::numeric), sum((r->>'valeur')::numeric), max(r->>'fenetre')
    from jsonb_array_elements(p_lignes) r
    where r->>'campagne_id' is not null
    group by 1,2,3,4,5;
    get diagnostics n = row_count;

    -- identité des campagnes + historique des noms
    insert into dim_campagne(plateforme, campagne_id, compte_id, type_campagne, nom_actuel, premiere_vue, derniere_vue)
    select p_source, campagne_id, max(compte_id), max(type_campagne), (array_agg(nom order by jour desc))[1], min(jour), max(jour)
    from (select r->>'campagne_id' campagne_id, r->>'compte_id' compte_id, r->>'type_campagne' type_campagne,
                 r->>'campagne_nom' nom, (r->>'jour')::date jour from jsonb_array_elements(p_lignes) r) s
    where campagne_id is not null group by campagne_id
    on conflict (plateforme, campagne_id) do update set
      nom_actuel   = case when excluded.derniere_vue >= dim_campagne.derniere_vue then excluded.nom_actuel else dim_campagne.nom_actuel end,
      type_campagne= coalesce(excluded.type_campagne, dim_campagne.type_campagne),
      premiere_vue = least(dim_campagne.premiere_vue, excluded.premiere_vue),
      derniere_vue = greatest(dim_campagne.derniere_vue, excluded.derniere_vue);

    insert into dim_campagne_nom(plateforme, campagne_id, nom, vu_du, vu_au)
    select p_source, r->>'campagne_id', r->>'campagne_nom', min((r->>'jour')::date), max((r->>'jour')::date)
    from jsonb_array_elements(p_lignes) r where r->>'campagne_id' is not null and coalesce(r->>'campagne_nom','') <> ''
    group by 2,3
    on conflict (plateforme, campagne_id, nom) do update set
      vu_du = least(dim_campagne_nom.vu_du, excluded.vu_du), vu_au = greatest(dim_campagne_nom.vu_au, excluded.vu_au);

  elsif p_source in ('google_ads_pub','meta_pub','tiktok_ads_pub') then
    delete from fait_regie_pub_jour where plateforme = replace(p_source,'_pub','') and jour between p_du and p_au;
    insert into fait_regie_pub_jour(jour, plateforme, campagne_id, groupe_id, pub_id, pub_nom, groupe_nom, impressions, clics, clics_lien,
                                    depense, conversions_revendiquees, valeur_revendiquee, vues_video_3s)
    select (r->>'jour')::date, replace(p_source,'_pub',''), r->>'campagne_id', coalesce(r->>'groupe_id',''), r->>'pub_id',
           max(r->>'pub_nom'), max(r->>'groupe_nom'), sum((r->>'impressions')::numeric), sum((r->>'clics')::numeric),
           sum((r->>'clics_lien')::numeric), sum((r->>'depense')::numeric), sum((r->>'conversions')::numeric),
           sum((r->>'valeur')::numeric), sum((r->>'vues_video_3s')::numeric)
    from jsonb_array_elements(p_lignes) r where r->>'pub_id' is not null
    group by 1,2,3,4,5;
    get diagnostics n = row_count;

  elsif p_source = 'ga4' then
    delete from fait_analytics_jour where jour between p_du and p_au;
    insert into fait_analytics_jour(jour, source, medium, campagne_brut, campagne_id, contenu_brut, canal,
                                    sessions, sessions_engagees, utilisateurs, nouveaux_utilisateurs, transactions, ca_mesure)
    select (r->>'jour')::date, coalesce(r->>'source','(not set)'), coalesce(r->>'medium','(not set)'),
           coalesce(r->>'campagne',''), coalesce(r->>'campagne_id',''), coalesce(r->>'contenu',''), max(r->>'canal'),
           sum((r->>'sessions')::numeric), sum((r->>'sessions_engagees')::numeric), sum((r->>'utilisateurs')::numeric),
           sum((r->>'nouveaux')::numeric), sum((r->>'transactions')::numeric), sum((r->>'ca')::numeric)
    from jsonb_array_elements(p_lignes) r group by 1,2,3,4,5,6;
    get diagnostics n = row_count;

  elsif p_source = 'ga4_total' then
    insert into fait_analytics_total_jour(jour, sessions, sessions_engagees, utilisateurs, transactions, ca_mesure, sessions_sans_page_entree, charge_le)
    select (r->>'jour')::date, (r->>'sessions')::int, (r->>'sessions_engagees')::int, (r->>'utilisateurs')::int,
           (r->>'transactions')::int, (r->>'ca')::numeric, (r->>'sans_page')::int, now()
    from jsonb_array_elements(p_lignes) r
    on conflict (jour) do update set sessions = excluded.sessions, sessions_engagees = excluded.sessions_engagees,
      utilisateurs = excluded.utilisateurs, transactions = excluded.transactions, ca_mesure = excluded.ca_mesure,
      sessions_sans_page_entree = coalesce(excluded.sessions_sans_page_entree, fait_analytics_total_jour.sessions_sans_page_entree),
      charge_le = now();
    get diagnostics n = row_count;

  elsif p_source = 'ga4_page' then
    delete from fait_analytics_page_jour where jour between p_du and p_au;
    insert into fait_analytics_page_jour(jour, page_entree, canal, sessions, sessions_engagees, transactions, ca_mesure)
    select (r->>'jour')::date, coalesce(nullif(r->>'page',''),'(sans page)'), coalesce(r->>'canal',''),
           sum((r->>'sessions')::numeric), sum((r->>'sessions_engagees')::numeric), sum((r->>'transactions')::numeric), sum((r->>'ca')::numeric)
    from jsonb_array_elements(p_lignes) r group by 1,2,3;
    get diagnostics n = row_count;

  elsif p_source = 'organique_jour' then
    insert into fait_organique_jour(jour, plateforme, compte_id, abonnes, abonnes_gagnes, abonnes_perdus, impressions, portee, vues,
                                    vues_profil, engagements, clics_lien, publications, charge_le)
    select (r->>'jour')::date, r->>'plateforme', r->>'compte_id', (r->>'abonnes')::bigint, (r->>'abonnes_gagnes')::int,
           (r->>'abonnes_perdus')::int, (r->>'impressions')::bigint, (r->>'portee')::bigint, (r->>'vues')::bigint,
           (r->>'vues_profil')::int, (r->>'engagements')::int, (r->>'clics_lien')::int, (r->>'publications')::int, now()
    from jsonb_array_elements(p_lignes) r
    on conflict (jour, plateforme, compte_id) do update set abonnes = excluded.abonnes, abonnes_gagnes = excluded.abonnes_gagnes,
      abonnes_perdus = excluded.abonnes_perdus, impressions = excluded.impressions, portee = excluded.portee, vues = excluded.vues,
      vues_profil = excluded.vues_profil, engagements = excluded.engagements, clics_lien = excluded.clics_lien,
      publications = excluded.publications, charge_le = now();
    get diagnostics n = row_count;

  elsif p_source = 'organique_post' then
    insert into fait_organique_post(plateforme, compte_id, post_id, publie_le, format, legende, lien, impressions, portee, vues,
                                    likes, commentaires, partages, enregistrements, engagements, duree_visionnage_moy, releve_le)
    select r->>'plateforme', r->>'compte_id', r->>'post_id', (r->>'publie_le')::timestamptz, r->>'format', left(r->>'legende',500), r->>'lien',
           (r->>'impressions')::bigint, (r->>'portee')::bigint, (r->>'vues')::bigint, (r->>'likes')::int, (r->>'commentaires')::int,
           (r->>'partages')::int, (r->>'enregistrements')::int, (r->>'engagements')::int, (r->>'duree_visionnage_moy')::numeric, current_date
    from jsonb_array_elements(p_lignes) r
    on conflict (plateforme, compte_id, post_id) do update set impressions = excluded.impressions, portee = excluded.portee,
      vues = excluded.vues, likes = excluded.likes, commentaires = excluded.commentaires, partages = excluded.partages,
      enregistrements = excluded.enregistrements, engagements = excluded.engagements,
      duree_visionnage_moy = excluded.duree_visionnage_moy, releve_le = current_date;
    get diagnostics n = row_count;

  elsif p_source = 'email' then
    insert into fait_email_campagne(plateforme, campagne_id, nom, type_envoi, envoye_le, destinataires, delivres, ouvertures_uniques,
                                    clics_uniques, desabonnements, plaintes, commandes_revendiquees, ca_revendique, releve_le)
    select 'omnisend', r->>'campagne_id', r->>'nom', r->>'type_envoi', (r->>'envoye_le')::timestamptz, (r->>'destinataires')::int,
           (r->>'delivres')::int, (r->>'ouvertures')::int, (r->>'clics')::int, (r->>'desabonnements')::int, (r->>'plaintes')::int,
           (r->>'commandes')::int, (r->>'ca')::numeric, current_date
    from jsonb_array_elements(p_lignes) r
    on conflict (plateforme, campagne_id) do update set nom = excluded.nom, destinataires = excluded.destinataires,
      delivres = excluded.delivres, ouvertures_uniques = excluded.ouvertures_uniques, clics_uniques = excluded.clics_uniques,
      desabonnements = excluded.desabonnements, plaintes = excluded.plaintes, commandes_revendiquees = excluded.commandes_revendiquees,
      ca_revendique = excluded.ca_revendique, releve_le = current_date;
    get diagnostics n = row_count;

  elsif p_source = 'seo' then
    delete from fait_seo_jour where jour between p_du and p_au;
    insert into fait_seo_jour(jour, site, requete, clics, impressions, ctr, position)
    select (r->>'jour')::date, r->>'site', coalesce(nullif(r->>'requete',''),'(total)'), sum((r->>'clics')::numeric),
           sum((r->>'impressions')::numeric), avg((r->>'ctr')::numeric), avg((r->>'position')::numeric)
    from jsonb_array_elements(p_lignes) r group by 1,2,3;
    get diagnostics n = row_count;
  else
    raise exception 'source inconnue: %', p_source;
  end if;

  update marketing.journal_ingestion set lignes = n, statut = 'ok', fin = now() where id = v_id;
  return jsonb_build_object('source', p_source, 'lignes', n);
end $$;
revoke all on function public.dc_charger(text, date, date, jsonb) from public, anon, authenticated;
grant execute on function public.dc_charger(text, date, date, jsonb) to service_role;

-- Contrôles de cohérence après chargement
create or replace function public.dc_controler(p_du date, p_au date)
returns jsonb language plpgsql security definer set search_path = marketing, public, pg_catalog as $$
declare r record; nb int := 0;
begin
  delete from controle_ingestion where jour between p_du and p_au;
  -- 1. GA4 : somme des lignes détaillées = total du jour (à 1 %)
  for r in select t.jour, t.sessions attendu, coalesce(sum(a.sessions),0) obtenu, t.transactions t_att, coalesce(sum(a.transactions),0) t_obt
           from fait_analytics_total_jour t left join fait_analytics_jour a on a.jour = t.jour
           where t.jour between p_du and p_au group by t.jour, t.sessions, t.transactions loop
    insert into controle_ingestion(jour, source, controle, attendu, obtenu, ecart_pct, ok)
    values (r.jour, 'ga4', 'sessions_detail_vs_total', r.attendu, r.obtenu,
            round(100.0*(r.obtenu - r.attendu)/nullif(r.attendu,0),2), abs(r.obtenu - r.attendu) <= greatest(0.01*r.attendu, 5)),
           (r.jour, 'ga4', 'transactions_detail_vs_total', r.t_att, r.t_obt,
            round(100.0*(r.t_obt - r.t_att)/nullif(r.t_att,0),2), r.t_obt = r.t_att);
    nb := nb + 2;
  end loop;
  -- 2. Captation GA4 vs PrestaShop particuliers (bande normale 80–100 %)
  for r in select c.jour, c.commandes attendu, t.transactions obtenu from v_commerce_jour c
           join fait_analytics_total_jour t on t.jour = c.jour where c.jour between p_du and p_au loop
    insert into controle_ingestion(jour, source, controle, attendu, obtenu, ecart_pct, ok)
    values (r.jour, 'ga4', 'captation_vs_prestashop', r.attendu, r.obtenu, round(100.0*r.obtenu/nullif(r.attendu,0),1),
            r.obtenu between 0.8*r.attendu and 1.1*r.attendu);
    nb := nb + 1;
  end loop;
  -- 3. Sessions sans page d'entrée (normal < 10 %)
  for r in select jour, sessions attendu, sessions_sans_page_entree obtenu from fait_analytics_total_jour
           where jour between p_du and p_au and sessions_sans_page_entree is not null loop
    insert into controle_ingestion(jour, source, controle, attendu, obtenu, ecart_pct, ok)
    values (r.jour, 'ga4', 'sessions_sans_page_entree', r.attendu, r.obtenu, round(100.0*r.obtenu/nullif(r.attendu,0),1),
            r.obtenu <= 0.10*r.attendu);
    nb := nb + 1;
  end loop;
  return jsonb_build_object('controles', nb);
end $$;
revoke all on function public.dc_controler(date, date) from public, anon, authenticated;
grant execute on function public.dc_controler(date, date) to service_role;
