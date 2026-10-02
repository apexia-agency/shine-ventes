-- Opération Norauto « OPE DeV » (Mobivia, CL00691) : avoir de PRIX écrit avec des quantités négatives (02/10/2026).
-- Constat de Jérémy, vérifié dans EBP : AV00000325 (25/06/2026) est une remise de prix sur FA00003823
-- (COL1-DEV × −188 à 32,64 €, COL2-DEV × −204 à 59,88 €). Aucune marchandise n'est revenue (204 colis de chaque type livrés).
-- Le CA du board est juste, mais les unités sont fausses : sur mai + juin 2026 le board compte 16 COL1-DEV et 0 COL2-DEV
-- au lieu de 204 et 204 (le détail EBP est cumulé par client, mois et article : juin = −188 COL1, −204 COL2).
-- Correction validée par Jérémy (02/10/2026) et demandée par Robin : rajouter en juin 2026 +188 COL1-DEV et +204 COL2-DEV
-- aux quantités, sans toucher aux montants. Table de corrections pour qu'un futur import du détail ne l'efface pas.
-- Retour arrière : delete from ebp_quantites_corrigees where code = 'CL00691' and mois = '2026-06-01';
--                  puis select appliquer_ebp_detail('2026-06-01', '2026-06-30'); select finaliser_collecte();

create table if not exists ebp_quantites_corrigees (
  code text not null,
  mois date not null,
  code_article text not null,
  ajout_quantite numeric not null,   -- ajouté à la quantité du détail EBP de ce mois (le montant ne change pas)
  note text,
  valide_par text,
  valide_le timestamptz not null default now(),
  primary key (code, mois, code_article)
);
alter table ebp_quantites_corrigees enable row level security;
revoke all on ebp_quantites_corrigees from anon, authenticated;

insert into ebp_quantites_corrigees (code, mois, code_article, ajout_quantite, note, valide_par) values
  ('CL00691', '2026-06-01', 'COL1-DEV', 188, 'AV00000325 = remise de prix sur FA00003823, pas un retour (OPE DeV Norauto)', 'Jérémy et Robin, 02/10/2026'),
  ('CL00691', '2026-06-01', 'COL2-DEV', 204, 'AV00000325 = remise de prix sur FA00003823, pas un retour (OPE DeV Norauto)', 'Jérémy et Robin, 02/10/2026')
on conflict do nothing;

-- appliquer_ebp_detail : la quantité de chaque article tient compte des corrections (partir de la définition actuelle).
do $$
declare d text; avant text := 'd.libelle, d.quantite, d.montant_ht';
begin
  d := pg_get_functiondef('public.appliquer_ebp_detail(date,date)'::regprocedure);
  if position('ebp_quantites_corrigees' in d) > 0 then return; end if;
  if position(avant in d) = 0 then raise exception 'texte attendu introuvable'; end if;
  d := replace(d, avant, 'd.libelle, d.quantite + coalesce((select sum(qc.ajout_quantite) from ebp_quantites_corrigees qc where qc.code = d.code_client and qc.mois = d.mois and qc.code_article = d.code_article), 0), d.montant_ht');
  execute d;
end $$;

-- Puis : select appliquer_ebp_detail('2026-06-01', '2026-06-30');  et  select finaliser_collecte();
