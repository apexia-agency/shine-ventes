-- Data Center : mise à jour du registre de fiabilité (marketing.evenement_qualite) au 10/10/2026,
-- d'après les passations « conversation ADS » et « état complet » du 10/10.
--
-- Retour arrière :
--   update marketing.evenement_qualite set au = null where id = 7;
--   update marketing.evenement_qualite set fiabilite = 'a_verifier',
--     raison = '12 291 sessions dont 4 121 sans page d''entrée, engagement 29 % ; sessions engagées stables (3 285 vs 2 977) ; achats cohérents avec PrestaShop'
--     where id = 10;
--   delete from marketing.evenement_qualite where source = 'journal_20261010';

-- 1. Valeur Google Ads : le repli à 1 € est corrigé depuis la version 78 du conteneur GTM (21/09 à 21 h 04).
update marketing.evenement_qualite set au = '2026-09-20'
where id = 7 and plateforme = 'google_ads' and metrique = 'valeur' and au is null;

insert into marketing.evenement_qualite (du, au, plateforme, perimetre, metrique, fiabilite, raison, source) values
 ('2026-09-21', null, 'google_ads', 'tout', 'valeur', 'fiable',
  'GTM version 78 (21/09) : la balise d''achat Google Ads envoie le montant réel TTC de la commande, fin du repli à 1 €. Panier moyen Google Ads remonté à 70 € contre 59 € en juillet-août.',
  'journal_20261010');

-- 2. 24/09 : ce n'était pas un incident, GA4 n'avait pas fini de traiter la journée (relue le 26/09 : 5 157 sessions, 0 % sans source).
update marketing.evenement_qualite
set fiabilite = 'fiable',
    raison = 'Faux incident : journée lue à J+1, avant que GA4 ait fini de la traiter (12 291 sessions et 58 % d''achats sans source). Relue le 26/09 : 5 157 sessions, 0 % sans source, achats et CA inchangés. Incident clos le 10/10.'
where id = 10 and du = '2026-09-24';

-- 3. Attribution GA4 : ce qui reste mal rangé aujourd'hui.
insert into marketing.evenement_qualite (du, au, plateforme, perimetre, metrique, fiabilite, raison, source) values
 ('2026-09-21', null, 'ga4', 'tout', 'attribution', 'partiel',
  'Des envois Omnisend arrivent dans GA4 en google / cpc au lieu de omnisend / email (≈ 45 commandes en septembre comptées à tort en Paid Search). Sans effet sur les chiffres par campagne Google, mais le total « Google payant » de GA4 est gonflé.',
  'journal_20261010'),
 ('2026-09-22', null, 'meta', 'tout', 'attribution', 'partiel',
  'Trois conventions UTM coexistent sur Meta (facebook / cpc, meta / paid_social, fb ou ig / paid). Le rattachement par identifiant de campagne (utm_id) fonctionne pour 93 % des achats ; les macros non remplacées ({{campaign.id}}) sont perdues. À unifier dans Meta.',
  'journal_20261010');
