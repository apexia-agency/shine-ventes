-- Préco de vente : lecture de nuit du tableau de Laurent (Google Sheet « COMMANDES FOURNISSEURS - Inventaires V2 »).
-- Un flux n8n à part (« Préco — lecture du tableau de Laurent ») lit cinq onglets avec la connexion Google Sheets de Jérémy
-- et envoie la réponse brute de Google à cette fonction, qui range la copie du jour dans preco_laurent, preco_cuves et
-- preco_accessoires. Les colonnes sont retrouvées par leur TITRE (pas par leur position) : si Laurent déplace une colonne,
-- la lecture suit ; si un titre disparaît ou si un onglet revient presque vide, tout le chargement est refusé.
-- Unités : « Bidons Chimie » et « Aérosols et chimie spé. » = unités ; « Vrac Production » = litres.
-- Retour arrière : drop function charger_tableau_laurent(jsonb); drop function preco_num(text);
--                  delete from preco_laurent / preco_cuves / preco_accessoires where lu_le = '<jour>' pour retirer une copie.

create or replace function public.preco_num(t text) returns numeric language sql immutable as $$
  select case when t ~ '^\s*-?[0-9]+([.,][0-9]+)?\s*$' then replace(trim(t), ',', '.')::numeric end
$$;

create or replace function public.charger_tableau_laurent(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  vr jsonb; onglet text; lignes jsonb; hdr jsonb; i_hdr int;
  c_code int; c_des int; c_stock int; c_cde int; c_flux int; c_four int; c_delai int; c_cond int; c_cond2 int; c_cond3 int; c_pru int; c_cmd int;
  lib_cmd text; v_jour date := (now() at time zone 'Europe/Paris')::date;
  n_bid int := 0; n_cuv int := 0; n_acc int := 0; n_cont int := 0; n int;
begin
  create temp table t_bid (sku text, flux numeric, stock numeric, cde numeric) on commit drop;
  create temp table t_cuv (code text, des text, litres numeric, cde numeric) on commit drop;
  create temp table t_acc (sku text, des text, stock numeric, cde numeric, flux numeric, four text, delai numeric, cond numeric, pru numeric) on commit drop;
  create temp table t_cont (sku text, q numeric) on commit drop;

  for vr in select * from jsonb_array_elements(coalesce(p->'valueRanges', '[]'::jsonb)) loop
    onglet := trim(both '''' from split_part(vr->>'range', '!', 1));
    lignes := coalesce(vr->'values', '[]'::jsonb);
    -- ligne de titres : la première qui contient « Code Article » (ou « Réf » pour la préco conteneur)
    select o - 1, l into i_hdr, hdr from jsonb_array_elements(lignes) with ordinality x(l, o)
    where l @> '["Code Article"]'::jsonb or l @> '["Réf"]'::jsonb order by o limit 1;
    if hdr is null then raise exception 'Onglet « % » : ligne de titres introuvable', onglet; end if;
    select max(o - 1) filter (where v in ('Code Article', 'Réf')), max(o - 1) filter (where v = 'Désignation'),
           max(o - 1) filter (where v = 'Stock Théorique IA - Vivant'), max(o - 1) filter (where v = 'Reliquat ou en CDE'),
           max(o - 1) filter (where v like 'Flux mensuel corrigé%'), max(o - 1) filter (where v = 'Fournisseur'),
           max(o - 1) filter (where v like 'Délai moyen fournisseur%'), max(o - 1) filter (where v = 'Cond. appro (u)'),
           max(o - 1) filter (where v like 'Quantité par Palette ou Carton%'), max(o - 1) filter (where v = 'Qté / carton'),
           max(o - 1) filter (where v like 'PRU BDD%'), min(o - 1) filter (where v like 'Cmd %')
      into c_code, c_des, c_stock, c_cde, c_flux, c_four, c_delai, c_cond, c_cond2, c_cond3, c_pru, c_cmd
    from jsonb_array_elements_text(hdr) with ordinality h(v, o);

    if onglet like '%Conteneur%' then
      if c_cmd is null then raise exception 'Onglet « % » : colonne « Cmd … » introuvable', onglet; end if;
      lib_cmd := replace(hdr->>c_cmd, 'Cmd ', '');
      insert into t_cont select trim(l->>c_code), preco_num(l->>c_cmd)
      from jsonb_array_elements(lignes) with ordinality x(l, o)
      where o - 1 > i_hdr and trim(coalesce(l->>c_code, '')) <> '' and preco_num(l->>2) is not null;
    else
      if c_stock is null or c_cde is null or c_flux is null then raise exception 'Onglet « % » : une colonne attendue a changé de titre (stock, en commande ou flux)', onglet; end if;
      if onglet = 'Vrac Production' then
        insert into t_cuv select trim(l->>c_code), trim(l->>c_des), preco_num(l->>c_stock), preco_num(l->>c_cde)
        from jsonb_array_elements(lignes) with ordinality x(l, o)
        where o - 1 > i_hdr and trim(coalesce(l->>c_code, '')) <> '' and preco_num(l->>0) is not null;
      elsif onglet = 'Accessoires' then
        insert into t_acc select trim(l->>c_code), trim(l->>c_des), preco_num(l->>c_stock), preco_num(l->>c_cde), preco_num(l->>c_flux),
               nullif(trim(coalesce(l->>c_four, '')), ''), preco_num(l->>c_delai),
               coalesce(preco_num(l->>c_cond), preco_num(l->>c_cond2), preco_num(l->>c_cond3)), preco_num(l->>c_pru)
        from jsonb_array_elements(lignes) with ordinality x(l, o)
        where o - 1 > i_hdr and trim(coalesce(l->>c_code, '')) <> '' and preco_num(l->>0) is not null;
      else  -- Bidons Chimie, Aérosols et chimie spé. : unités
        insert into t_bid select trim(l->>c_code), preco_num(l->>c_flux), preco_num(l->>c_stock), preco_num(l->>c_cde)
        from jsonb_array_elements(lignes) with ordinality x(l, o)
        where o - 1 > i_hdr and trim(coalesce(l->>c_code, '')) <> '' and preco_num(l->>0) is not null;
      end if;
    end if;
  end loop;

  select count(*) into n_bid from t_bid; select count(*) into n_cuv from t_cuv; select count(*) into n_acc from t_acc; select count(*) into n_cont from t_cont;
  if n_bid < 100 or n_cuv < 20 or n_acc < 50 then
    raise exception 'Lecture incomplète (bidons %, cuves %, accessoires %) : rien n''est chargé', n_bid, n_cuv, n_acc;
  end if;

  insert into preco_laurent (sku, lu_le, flux_mensuel, stock, en_commande)
  select distinct on (sku) sku, v_jour, flux, stock, cde from t_bid
  on conflict (sku, lu_le) do update set flux_mensuel = excluded.flux_mensuel, stock = excluded.stock, en_commande = excluded.en_commande;
  insert into preco_cuves (code, lu_le, designation, litres, en_commande)
  select distinct on (code) code, v_jour, des, litres, cde from t_cuv
  on conflict (code, lu_le) do update set designation = excluded.designation, litres = excluded.litres, en_commande = excluded.en_commande;
  insert into preco_accessoires (sku, lu_le, designation, stock, en_commande, flux_mensuel, fournisseur, delai_sem, cond_appro, pru, preco_laurent, preco_laurent_date)
  select distinct on (a.sku) a.sku, v_jour, a.des, a.stock, a.cde, a.flux, a.four, a.delai, a.cond, a.pru, c.q, case when c.sku is not null then lib_cmd end
  from t_acc a left join t_cont c on c.sku = a.sku
  on conflict (sku, lu_le) do update set designation = excluded.designation, stock = excluded.stock, en_commande = excluded.en_commande,
    flux_mensuel = excluded.flux_mensuel, fournisseur = excluded.fournisseur, delai_sem = excluded.delai_sem, cond_appro = excluded.cond_appro,
    pru = excluded.pru, preco_laurent = excluded.preco_laurent, preco_laurent_date = excluded.preco_laurent_date;

  return jsonb_build_object('jour', v_jour, 'bidons', n_bid, 'cuves', n_cuv, 'accessoires', n_acc, 'preco_conteneur', n_cont,
    'fournisseurs_sans_origine', (select coalesce(jsonb_agg(distinct a.four), '[]'::jsonb) from t_acc a where a.four is not null and not exists (select 1 from preco_fournisseurs f where f.fournisseur = a.four)));
end $$;
revoke all on function public.charger_tableau_laurent(jsonb) from public, anon, authenticated;
grant execute on function public.charger_tableau_laurent(jsonb) to service_role;
