-- Appliquée dans Supabase le 25/09/2026 (version 20260925143351), exportée dans le dépôt le 10/10/2026.

do $$
declare d text;
begin
  d := pg_get_functiondef('marketing.generer_preconisations()'::regprocedure);
  d := replace(d, $a$  for r in select campagne_brut, sum(sessions) s, sum(transactions) t from fait_analytics_jour
           where jour between hier - 6 and hier and medium = 'cpc' and campagne_brut like 'campaign:%' group by 1 having sum(sessions) >= 20 loop
    if not exists (select 1 from _deja where regle_code = 'R6' and perimetre = r.campagne_brut) then$a$,
  $a$  for r in select 'omnisend_en_cpc'::text campagne_brut, sum(sessions) s, sum(transactions) t, count(distinct campagne_brut) nb,
                  string_agg(distinct regexp_replace(campagne_brut, '^campaign: | \([0-9a-f]+\)$', '', 'g'), ' · ') liste
           from fait_analytics_jour where jour between hier - 6 and hier and medium = 'cpc' and campagne_brut like 'campaign:%'
           having sum(sessions) >= 20 loop
    if not exists (select 1 from _deja where regle_code = 'R6') then$a$);
  d := replace(d, $a$format('Envoi Omnisend compté en Paid Search : %s', left(r.campagne_brut, 80)),
        format('%s sessions et %s commandes de cet e-mail arrivent en google / cpc au lieu de omnisend / email.', r.s, r.t),$a$,
  $a$format('%s envois Omnisend comptés en Paid Search sur 7 jours', r.nb),
        format('%s sessions et %s commandes d''e-mails arrivent en google / cpc au lieu de omnisend / email : %s', r.s, r.t, left(r.liste, 600)),$a$);
  d := replace(d, $a$'Corriger les paramètres UTM de l''envoi (utm_source=omnisend, utm_medium=email) dans Omnisend.'$a$,
                  $a$'Corriger les paramètres UTM par défaut du compte Omnisend (utm_source=omnisend, utm_medium=email) : le problème touche tous les envois, pas un seul.'$a$);
  d := replace(d, $a$round(r.ca / nullif(r.dep,0), 2))$a$, $a$replace(round(r.ca / nullif(r.dep,0), 2)::text, '.', ','))$a$);
  d := replace(d, $a$round(r.val / r.ca, 1))$a$, $a$replace(round(r.val / r.ca, 1)::text, '.', ','))$a$);
  d := replace(d, $a$format('%s %% des sessions sans page d''entrée', r.ecart_pct)$a$, $a$format('%s %% des sessions sans page d''entrée', replace(r.ecart_pct::text, '.', ','))$a$);
  d := replace(d, $a$format('GA4 n''a vu que %s %% des commandes PrestaShop', r.ecart_pct)$a$, $a$format('GA4 n''a vu que %s %% des commandes PrestaShop', replace(r.ecart_pct::text, '.', ','))$a$);
  d := replace(d, $a$format('Google Ads : valeur moyenne de %s € par conversion le %s', round(r.v / r.c, 2),$a$, $a$format('Google Ads : valeur moyenne de %s € par conversion le %s', replace(round(r.v / r.c, 2)::text, '.', ','),$a$);
  if position('omnisend_en_cpc' in d) = 0 then raise exception 'remplacement R6 non appliqué'; end if;
  execute d;
end $$;
delete from marketing.preconisation;
select marketing.generer_preconisations();
