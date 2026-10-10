-- Appliquée dans Supabase le 25/09/2026 (version 20260925143322), exportée dans le dépôt le 10/10/2026.

-- Moteur de préconisations (règles déterministes), chaque nuit après le chargement.
create or replace function marketing.generer_preconisations()
returns int language plpgsql security definer set search_path = marketing, public as $$
declare hier date := (now() at time zone 'Europe/Paris')::date - 1; n int := 0; r record;
  procedure_ok boolean;
begin
  -- évite les doublons : même règle, même périmètre, déjà ouverte depuis moins de 7 jours
  create temp table if not exists _deja on commit drop as
    select regle_code, perimetre from preconisation where statut in ('proposee','acceptee') and cree_le > now() - interval '7 days';

  -- R1 : un réseau dépense sans produire de valeur (cas Discover)
  for r in select plateforme, reseau, sum(depense) dep, sum(valeur_revendiquee) val from fait_regie_jour
           where jour between hier - 2 and hier group by 1,2 having sum(depense) > 60 and coalesce(sum(valeur_revendiquee),0) = 0 loop
    if not exists (select 1 from _deja where regle_code = 'R1' and perimetre = r.plateforme||':'||r.reseau) then
      insert into preconisation(origine, regle_code, periode_du, periode_au, plateforme, perimetre, gravite, titre, constat, action_proposee, gain_estime, fiabilite_donnee, preuve)
      values ('regle','R1', hier-2, hier, r.plateforme, r.plateforme||':'||r.reseau, 'haute',
        format('Réseau %s : %s € dépensés en 3 jours sans aucune valeur', r.reseau, round(r.dep)),
        'La régie elle-même ne s''attribue aucune vente sur ce réseau. Les clics sont comptés par les serveurs de la régie : ce n''est pas un problème de tracking.',
        'Vérifier la répartition par réseau de la campagne et limiter ce réseau (exclusions, cible de ROAS, format).',
        format('~%s €/jour', round(r.dep/3)), 'dépense : fiable', jsonb_build_object('depense', r.dep, 'valeur', r.val));
      n := n + 1;
    end if;
  end loop;

  -- R2 : campagne sous le seuil de rentabilité mesurée (ROAS GA4 < 1,5 sur 3 jours, > 100 €/j)
  for r in select plateforme, campagne_id, max(campagne) campagne, sum(depense) dep, sum(ca_mesure) ca from v_perf_campagne_jour
           where jour between hier - 2 and hier group by 1,2 having sum(depense) > 300 and sum(ca_mesure) < 1.5 * sum(depense) loop
    if not exists (select 1 from _deja where regle_code = 'R2' and perimetre = r.campagne_id) then
      insert into preconisation(origine, regle_code, periode_du, periode_au, plateforme, perimetre, gravite, titre, constat, action_proposee, gain_estime, fiabilite_donnee, preuve)
      values ('regle','R2', hier-2, hier, r.plateforme, r.campagne_id, 'moyenne',
        format('%s : ROAS mesuré %s sur 3 jours', r.campagne, round(r.ca / nullif(r.dep,0), 2)),
        format('%s € dépensés pour %s € de CA mesuré par GA4 (dernier clic). À lire avec le facteur de gonflement de la régie.', round(r.dep), round(r.ca)),
        'Réduire le budget ou le réaffecter vers la campagne la plus rentable de la même régie ; une seule modification à la fois.',
        format('jusqu''à %s €/jour', round(r.dep/3)), 'CA mesuré : partiel (~87 % des commandes)', jsonb_build_object('depense', r.dep, 'ca_mesure', r.ca));
      n := n + 1;
    end if;
  end loop;

  -- R3 : la régie revendique plus de 5 fois ce que GA4 mesure (7 jours)
  for r in select plateforme, campagne_id, max(campagne) campagne, sum(valeur_rev) val, sum(ca_mesure) ca from v_perf_campagne_jour
           where jour between hier - 6 and hier group by 1,2 having sum(ca_mesure) > 0 and sum(valeur_rev) > 5 * sum(ca_mesure) and sum(depense) > 200 loop
    if not exists (select 1 from _deja where regle_code = 'R3' and perimetre = r.campagne_id) then
      insert into preconisation(origine, regle_code, periode_du, periode_au, plateforme, perimetre, gravite, titre, constat, action_proposee, fiabilite_donnee, preuve)
      values ('regle','R3', hier-6, hier, r.plateforme, r.campagne_id, 'moyenne',
        format('%s : la régie revendique %s fois ce que GA4 mesure', r.campagne, round(r.val / r.ca, 1)),
        format('%s € revendiqués contre %s € mesurés sur 7 jours. Au-delà de ×5, l''attribution de la régie ne permet plus de piloter.', round(r.val), round(r.ca)),
        'Piloter cette campagne sur le ROAS mesuré et le MER, pas sur le ROAS affiché par la régie ; envisager une attribution 7 j clic / 0 j vue.',
        'revendiqué : non fiable', jsonb_build_object('revendique', r.val, 'mesure', r.ca));
      n := n + 1;
    end if;
  end loop;

  -- R4 / R5 : contrôles de tracking en échec hier
  for r in select controle, attendu, obtenu, ecart_pct from controle_ingestion
           where jour = hier and not ok and controle in ('captation_vs_prestashop','sessions_sans_page_entree') loop
    if not exists (select 1 from _deja where regle_code = 'R4' and perimetre = r.controle) then
      insert into preconisation(origine, regle_code, periode_du, periode_au, plateforme, perimetre, gravite, titre, constat, action_proposee, fiabilite_donnee, preuve)
      values ('regle','R4', hier, hier, 'ga4', r.controle, 'haute',
        case r.controle when 'captation_vs_prestashop' then format('GA4 n''a vu que %s %% des commandes PrestaShop', r.ecart_pct)
             else format('%s %% des sessions sans page d''entrée', r.ecart_pct) end,
        case r.controle when 'captation_vs_prestashop' then 'Normal : 85 à 95 %. En dessous, la balise d''achat ou le consentement ne remonte plus correctement.'
             else 'Normal : moins de 10 %. Au-dessus, des sessions sont créées sans page vue (balise, consentement, script tiers ou robots).' end,
        'Vérifier l''historique GTM, les modules PrestaShop et le bandeau de consentement mis à jour récemment.',
        'sessions : à vérifier', jsonb_build_object('attendu', r.attendu, 'obtenu', r.obtenu));
      n := n + 1;
    end if;
  end loop;

  -- R6 : e-mails Omnisend étiquetés comme du payant (google / cpc)
  for r in select campagne_brut, sum(sessions) s, sum(transactions) t from fait_analytics_jour
           where jour between hier - 6 and hier and medium = 'cpc' and campagne_brut like 'campaign:%' group by 1 having sum(sessions) >= 20 loop
    if not exists (select 1 from _deja where regle_code = 'R6' and perimetre = r.campagne_brut) then
      insert into preconisation(origine, regle_code, periode_du, periode_au, plateforme, perimetre, gravite, titre, constat, action_proposee, fiabilite_donnee, preuve)
      values ('regle','R6', hier-6, hier, 'ga4', r.campagne_brut, 'moyenne',
        format('Envoi Omnisend compté en Paid Search : %s', left(r.campagne_brut, 80)),
        format('%s sessions et %s commandes de cet e-mail arrivent en google / cpc au lieu de omnisend / email.', r.s, r.t),
        'Corriger les paramètres UTM de l''envoi (utm_source=omnisend, utm_medium=email) dans Omnisend.',
        'attribution : erronée', jsonb_build_object('sessions', r.s, 'commandes', r.t));
      n := n + 1;
    end if;
  end loop;

  -- R7 : valeur de conversion Google Ads anormalement basse (repli à 1 €)
  for r in select jour, sum(conversions_revendiquees) c, sum(valeur_revendiquee) v from fait_regie_jour
           where plateforme = 'google_ads' and jour between hier - 2 and hier group by 1
           having sum(conversions_revendiquees) >= 3 and sum(valeur_revendiquee) / sum(conversions_revendiquees) < 20 loop
    if not exists (select 1 from _deja where regle_code = 'R7') then
      insert into preconisation(origine, regle_code, periode_du, periode_au, plateforme, perimetre, gravite, titre, constat, action_proposee, fiabilite_donnee, preuve)
      values ('regle','R7', r.jour, r.jour, 'google_ads', 'tout', 'haute',
        format('Google Ads : valeur moyenne de %s € par conversion le %s', round(r.v / r.c, 2), to_char(r.jour, 'DD/MM')),
        'Le panier moyen réel est proche de 70 € HT. Une valeur aussi basse signale le repli à 1 € de la variable GTM de valeur.',
        'Remplacer la variable GTM « Domaine valeur de transaction » (chez Adam).',
        'valeur : non fiable', jsonb_build_object('conversions', r.c, 'valeur', r.v));
      n := n + 1;
    end if;
  end loop;

  -- les préconisations proposées de plus de 30 jours expirent
  update preconisation set statut = 'expiree' where statut = 'proposee' and cree_le < now() - interval '30 days';
  return n;
end $$;
revoke all on function marketing.generer_preconisations() from public, anon, authenticated;

select cron.schedule('dc-preconisations', '15 3 * * *', 'select marketing.generer_preconisations()');
