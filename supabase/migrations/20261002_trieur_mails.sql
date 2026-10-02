-- Trieur de mails de Jérémy (02/10/2026) : tri des boîtes shinegroupfr@gmail.com et jeremy(.b)@shine-group.fr
-- (les adresses pro arrivent déjà dans la boîte Gmail), brouillons de réponse, rien n'est envoyé ni supprimé.
-- Chaîne : flux n8n « Boîte Jérémy · tri et brouillons » → fonction Edge trier-mail → libellé Gmail (+ brouillon).
-- Indépendant de l'agent mail de Robin (flux « Boîte pro », app FRIDAY) : aucune table ni fonction partagée.
--
-- Principe (le même que le rangeur de factures) : les RÈGLES décident d'abord (mails_regles), Claude ne lit que
-- les expéditeurs sans règle. Un mail n'est jamais classé « inutile » s'il vient de SHINE ou d'un client connu.
-- Confidentialité : ni le texte des mails ni les adresses des correspondants ne sont gardés. Le journal garde le
-- domaine de l'expéditeur et l'empreinte SHA-256 de son adresse (même empreinte que clients_email_empreinte).
-- Les règles par adresse ne visent que des expéditeurs commerciaux (lettres d'information), jamais des clients.
--
-- Retour arrière : drop function mail_contexte(text); drop table mails_traites, mails_regles;
--                  drop index clients_email_empreinte_empreinte_idx;

create table if not exists public.mails_regles (
  id bigint generated always as identity primary key,
  portee text not null check (portee in ('adresse', 'domaine')),
  cle text not null check (cle = lower(cle)),          -- adresse complète, ou domaine (vaut aussi pour ses sous-domaines)
  decision text not null check (decision in ('garder', 'inutile')),
  libelle text,                                        -- libellé Gmail à poser (ex. FOURNISSEUR/CREE), facultatif
  note text,
  origine text not null default 'jeremy',              -- 'jeremy' : décidé par Jérémy ; 'claude' : proposé, à confirmer
  actif boolean not null default true,
  cree_le timestamptz not null default now(),
  unique (portee, cle)
);

create table if not exists public.mails_traites (
  gmail_id text primary key,
  thread_id text,
  recu_le timestamptz,
  domaine text,
  empreinte text,
  source text not null check (source in ('regle', 'interne', 'client', 'claude')),
  regle_id bigint references public.mails_regles(id),
  categorie text,
  decision text not null check (decision in ('garder', 'inutile')),
  libelle text,
  reponse_attendue boolean not null default false,
  brouillon boolean not null default false,
  motif text,
  confiance numeric,
  modele text,
  jetons_entree integer,
  jetons_sortie integer,
  cout_usd numeric,
  traite_le timestamptz not null default now()
);
create index if not exists mails_traites_recu_le_idx on public.mails_traites (recu_le desc);
create index if not exists mails_traites_domaine_idx on public.mails_traites (domaine);

-- Clé service uniquement (fonction Edge) : RLS activée, aucune politique
alter table public.mails_regles enable row level security;
alter table public.mails_traites enable row level security;

create index if not exists clients_email_empreinte_empreinte_idx on public.clients_email_empreinte (empreinte);

-- Fiche de contexte d'un expéditeur, retrouvé par l'empreinte de son adresse : famille de client, chiffre d'affaires
-- par exercice, cinq dernières factures (avec transporteur et suivi). null si ce n'est pas un client connu.
-- C'est la seule lecture de la base ouverte à l'agent mail : pas de SQL libre, un mail est un texte écrit par un inconnu.
create or replace function public.mail_contexte(p_empreinte text)
returns jsonb language sql stable security definer set search_path = public as $$
  with fiches as (
    select distinct cs.client_id
    from clients_email_empreinte e
    join clients_sources cs on cs.source = e.source and cs.source_client_id = e.source_client_id
    where e.empreinte = p_empreinte
  )
  select case when not exists (select 1 from fiches) then null else jsonb_build_object(
    'fiches', (select jsonb_agg(jsonb_build_object('nom', c.client_nom, 'famille', c.segment, 'groupe', c.groupe_client, 'pays', c.pays))
               from clients c join fiches f using (client_id)),
    'ca_par_exercice', (select jsonb_agg(x) from (
        select a.exercice, sum(a.nb_factures) as factures, round(sum(a.ca_ht)) as ca_ht, max(a.derniere_facture) as derniere_facture
        from agg_clients a join fiches f using (client_id) group by a.exercice order by a.exercice desc limit 3) x),
    'dernieres_factures', (select jsonb_agg(x) from (
        select p.date_facture, p.num_facture, p.num_commande, p.canal, p.avoir, p.transporteur, p.num_suivi
        from ventes_pieces p
        join clients_sources cs on cs.source = p.source and cs.source_client_id = p.source_client_id
        join fiches f on f.client_id = cs.client_id
        where p.retenue order by p.date_facture desc limit 5) x)
  ) end
$$;
revoke all on function public.mail_contexte(text) from public, anon, authenticated;
grant execute on function public.mail_contexte(text) to service_role;

-- Premières règles, tirées des mails reçus du 25/09 au 02/10/2026 : lettres d'information de boutiques, sans
-- rapport avec SHINE. Proposées par Claude (origine 'claude'), par adresse exacte pour ne pas masquer une
-- confirmation de commande envoyée par la même enseigne depuis une autre adresse.
insert into public.mails_regles (portee, cle, decision, note, origine) values
  ('adresse', 'hello@getjolt.fr', 'inutile', 'lettre d''information', 'claude'),
  ('adresse', 'noreplay@mail.sklum.com', 'inutile', 'promotions', 'claude'),
  ('adresse', 'email@news.traderepublic.com', 'inutile', 'promotions', 'claude'),
  ('adresse', 'hello@easy-clothes.com', 'inutile', 'promotions', 'claude'),
  ('adresse', 'newsletter@email.galerieslafayette.com', 'inutile', 'lettre d''information', 'claude'),
  ('adresse', 'hello@thebradery.com', 'inutile', 'ventes privées', 'claude'),
  ('adresse', 'email@insider.wilson.com', 'inutile', 'promotions', 'claude'),
  ('adresse', 'suno@creators.suno.com', 'inutile', 'lettre d''information', 'claude'),
  ('adresse', 'ae-ai-notice06@newarrival.aliexpress.com', 'inutile', 'promotions', 'claude'),
  ('adresse', 'mailers@euemail.muc-off.com', 'inutile', 'promotions', 'claude'),
  ('adresse', 'info@lesdeux.dk', 'inutile', 'promotions', 'claude'),
  ('adresse', 'info@lesdeux.com', 'inutile', 'promotions', 'claude'),
  ('adresse', 'actu@info.tf1.fr', 'inutile', 'lettre d''information', 'claude'),
  ('adresse', 'customerservice@fathersonsclothing.com', 'inutile', 'promotions', 'claude'),
  ('adresse', 'info@news.magnific.com', 'inutile', 'lettre d''information', 'claude'),
  ('adresse', 'contact@cinqmondes.com', 'inutile', 'promotions', 'claude'),
  ('adresse', 'marketing@channable.com', 'inutile', 'invitations à des webinaires', 'claude')
on conflict (portee, cle) do nothing;
