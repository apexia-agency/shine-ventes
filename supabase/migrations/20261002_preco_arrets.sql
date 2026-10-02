-- Préco de vente : produits sortis du catalogue (liste de Jérémy du 02/10/2026, fichier « 80_20 DESTOCKAGE », feuille 3).
-- Un produit arrêté n'a plus de préconisation (ni à conditionner, ni à commander) : le board montre seulement son stock restant.
-- « Oui définitif » = arrêté ; « Non reviendra » = en rupture mais reste au catalogue (pas arrêté).
-- ACS67 (Cache roue) apparaît deux fois dans la liste (« Oui définitif » et « Non reviendra ») : marqué arrêté, à confirmer par Jérémy.
-- Retour arrière : drop table preco_arrets;   (ou update preco_arrets set arrete = false where sku = '…')

create table if not exists preco_arrets (
  sku text primary key,
  etat text,                 -- état du stock dans la liste (En rupture / Disponible)
  decision text,             -- texte de la liste (Oui définitif / Non reviendra)
  arrete boolean not null,
  note text,
  maj_le timestamptz default now()
);
alter table preco_arrets enable row level security;
drop policy if exists lecture_associes on preco_arrets;
create policy lecture_associes on preco_arrets for select to authenticated using ((select est_associe()));
revoke all on preco_arrets from anon;
revoke insert, update, delete, truncate on preco_arrets from authenticated;

insert into preco_arrets (sku, etat, decision, arrete, note)
select v.sku, v.etat, v.decision, v.decision = 'Oui définitif', v.note from (values
  ('ACS65','En rupture','Oui définitif',null),('ACS67','En rupture','Oui définitif','aussi listé « Non reviendra » : à confirmer'),('AS47-A650-400','En rupture','Oui définitif',null),
  ('ROBI-P','En rupture','Oui définitif',null),('ACS28-75','En rupture','Oui définitif',null),('ACSP02','En rupture','Oui définitif',null),('ACS62','Disponible','Oui définitif',null),
  ('AS1003-2500','Disponible','Oui définitif',null),('ACS71','Disponible','Oui définitif',null),('AS1002-2500','En rupture','Oui définitif',null),('AS15-450','Disponible','Oui définitif',null),
  ('AS15-5','En rupture','Oui définitif',null),('ACS46','En rupture','Oui définitif',null),('ACS15','En rupture','Oui définitif',null),('AS30-450','En rupture','Oui définitif',null),
  ('AS1008-A650-500','Disponible','Oui définitif',null),('AS12-5','En rupture','Oui définitif',null),('ACS70','En rupture','Oui définitif',null),('AS07-5','En rupture','Oui définitif',null),
  ('ACS45','En rupture','Oui définitif',null),('AS1001-2500','En rupture','Oui définitif',null),('ACSP01','En rupture','Oui définitif',null),('AS1007-A520-400','Disponible','Oui définitif',null),
  ('ACS19','En rupture','Oui définitif',null),('AS39-100','Disponible','Oui définitif',null),('AS1004-2500','En rupture','Oui définitif',null),('AS07-750','En rupture','Oui définitif',null),
  ('AS20-450','En rupture','Oui définitif',null),('ACS36','Disponible','Oui définitif',null),('ACS31','En rupture','Oui définitif',null),('ACS47','Disponible','Oui définitif',null),
  ('ACS44','En rupture','Oui définitif',null),('AS49','En rupture','Non reviendra','référence sans format dans la liste'),('ACS2','En rupture','Non reviendra',null),
  ('AS41','En rupture','Non reviendra',null),('ACS59','En rupture','Non reviendra',null)
) v(sku, etat, decision, note)
on conflict (sku) do update set etat = excluded.etat, decision = excluded.decision, arrete = excluded.arrete, note = excluded.note, maj_le = now();
