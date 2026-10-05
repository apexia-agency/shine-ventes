-- MyClear : transport calculé commande par commande avec la grille Colissimo Domicile Sans Signature négociée 2026
-- (classeur MY CLEAR V27, onglet « Hypothèses & coûts »), au lieu d'un coût moyen par colis.
-- Poids d'une commande = somme quantité × poids unitaire (onglet « Articles individuels » ; packs = somme de leurs composants).
-- Prix d'un colis = tarif de la 1re tranche dont le poids max ≥ poids de la commande × (1 + surtaxe gasoil du mois) + taxe,
-- surtaxe et taxe lues dans les factures Colissimo (transport_colis, colis à domicile ; dernier mois connu sinon).
-- Contrôle du 05/10/2026 : 6,22 € × 1,138 + 0,05 = 7,13 €, le montant des factures Colissimo des colis TikTok.
-- Retour arrière : drop function myclear_prix_colis, myclear_gasoil ; drop table myclear_grille_transport ;
--   alter table myclear_couts drop column poids_kg ; réappliquer 20261005_myclear_marge_par_canal.sql.

create table if not exists myclear_grille_transport (
  poids_max numeric(6,2) primary key,
  tarif_ht numeric(8,2) not null
);
insert into myclear_grille_transport (poids_max, tarif_ht) values
  (2, 6.22), (3, 6.90), (4, 7.60), (5, 8.31), (6, 9.02), (7, 9.73), (8, 10.45), (9, 11.18), (10, 11.91), (15, 15.52), (30, 30.08)
on conflict (poids_max) do update set tarif_ht = excluded.tarif_ht;
alter table myclear_grille_transport enable row level security;
revoke all on myclear_grille_transport from anon, authenticated;

-- Poids unitaire (kg) à côté du coût
alter table myclear_couts add column if not exists poids_kg numeric(6,3);
update myclear_couts c set poids_kg = v.p from (values
  ('MC06-450',0.520),('MC17-450',0.500),('MC42-150',0.210),('MC03-450',0.590),('MC05-450',0.480),('MC09-450',0.460),
  ('MC28-450',0.520),('MC22-450',0.520),('MC21-450',0.450),('MC10-450',0.470),('MCA-8',0.620),('MCA-11',0.200),
  ('MCA-24',0.120),('MCA-56',0.300),('MCA-14',0.120),('MCA-72',0.100),('MCA-39',0.250),('MCA-25',0.060),('MCA-43',0.070),
  ('MCA-5',0.060),('MCA-27-XL',0.230),('MCA-50',0.300),('MCA-18',0.250),
  -- packs : somme des composants (site myclear.fr ; versions TikTok d'après leur nom)
  ('MCP01',1.590),('MCP02',4.920),('MCP03',1.380),('MCP04',2.500),
  ('MCP01-TT',1.590),('MCP02-TT',2.850),('MCP03-TT',1.050),('MCP04-TT',2.500)
) v(sku, p) where c.sku = v.sku;

-- Surtaxe gasoil (taux) et taxe par colis d'un mois, lues dans les factures Colissimo (dernier mois avec au moins 200 colis)
create or replace function myclear_gasoil(p_mois date, out taux numeric, out taxe numeric)
language sql stable security definer set search_path to 'public' as $$
  select coalesce(avg(gasoil / nullif(transport, 0)), 0.138), coalesce(avg(taxes), 0.05)
    from transport_colis
   where transporteur = 'Colissimo' and mode = 'coli_dom' and transport > 0 and poids_kg <= 30
     and date_trunc('month', date_envoi) = (
       select max(m) from (select date_trunc('month', date_envoi) m from transport_colis
                            where transporteur = 'Colissimo' and mode = 'coli_dom' and transport > 0 and poids_kg <= 30
                              and date_envoi < (p_mois + interval '1 month') group by 1 having count(*) >= 200) x);
$$;

-- Prix HT d'un colis d'un poids donné un mois donné
create or replace function myclear_prix_colis(p_poids numeric, p_mois date)
returns numeric language sql stable security definer set search_path to 'public' as $$
  select round(g.tarif_ht * (1 + s.taux) + s.taxe, 2)
    from myclear_gasoil(p_mois) s,
         lateral (select tarif_ht from myclear_grille_transport where poids_max >= coalesce(p_poids, 0) order by poids_max limit 1) g;
$$;
revoke execute on function myclear_gasoil(date) from public, anon;
revoke execute on function myclear_prix_colis(numeric, date) from public, anon;
grant execute on function myclear_prix_colis(numeric, date) to authenticated;

-- myclear_marge : transport = somme des prix de colis de chaque commande (au lieu de commandes × coût moyen).
-- Modifiée à partir de sa définition en base ; seules ces expressions changent.
do $$
declare d text := pg_get_functiondef('public.myclear_marge(date,date)'::regprocedure);
  r text[][] := array[
    array['select mois, canal, count(*) filter (where not avoir) colis, sum(coalesce(frais_port_facture_ht, 0)) port from pieces group by 1, 2',
          'select pc.mois, pc.canal, count(*) filter (where not pc.avoir) colis, sum(coalesce(pc.frais_port_facture_ht, 0)) port,
           sum(case when pc.avoir then 0 else myclear_prix_colis(w.poids, pc.mois) end) transport,
           count(*) filter (where not pc.avoir and w.poids > 2) colis_lourds
      from pieces pc left join lateral (
        select sum(l.quantite * coalesce(c.poids_kg, 0)) poids from ventes_lignes l
          left join myclear_alias_sku al on al.sku_source = l.sku
          left join myclear_couts c on c.sku = coalesce(al.sku, l.sku)
         where l.piece_id = pc.id) w on true
     group by 1, 2'],
    array['coalesce(c.port, 0) port_client_ht', 'coalesce(c.port, 0) port_client_ht, coalesce(c.transport, 0) transport_cmd, coalesce(c.colis_lourds, 0) colis_lourds'],
    array['myclear_cout_colis(cm.mois) cout_colis_ht,
           round(cm.colis * myclear_cout_colis(cm.mois), 2) transport_ht,',
          'round(cm.transport_cmd / nullif(cm.colis, 0), 2) cout_colis_ht,
           round(cm.transport_cmd, 2) transport_ht,'],
    array['max(cout_colis_ht) cout_colis_ht', 'round(sum(transport_ht) / nullif(sum(colis), 0), 2) cout_colis_ht, sum(colis_lourds) colis_lourds'],
    array['''colis'', colis,', '''colis'', colis, ''colis_lourds'', colis_lourds,']];
  i int;
begin
  for i in 1 .. array_length(r, 1) loop
    if position(r[i][1] in d) = 0 then raise exception 'Expression % introuvable dans myclear_marge', i; end if;
    d := replace(d, r[i][1], r[i][2]);
  end loop;
  execute d;
end $$;
