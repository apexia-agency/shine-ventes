-- MyClear : chargement des frais TikTok sans perte quand un export couvre un mois de relevé en partie.
-- On garde, par mois de relevé, les jours couverts (du / au). Un nouvel export remplace un mois seulement
-- s'il le couvre au moins autant que ce qui est déjà chargé ; s'il en couvre moins, le mois est ignoré ;
-- si les deux se chevauchent sans que l'un contienne l'autre, le chargement s'arrête (exporter le mois entier).
-- Retour arrière : drop table myclear_releves_mois ; remettre myclear_charger_frais_tiktok de 20261005_myclear_marge.sql.
create table if not exists myclear_releves_mois (
  mois_releve date primary key,
  du date not null,
  au date not null
);
alter table myclear_releves_mois enable row level security;
revoke all on myclear_releves_mois from anon, authenticated;

-- Couverture des deux exports déjà chargés (31/03 → 21/05 et 08/07 → 05/10/2026)
insert into myclear_releves_mois (mois_releve, du, au)
select date_trunc('month', g)::date, min(g)::date, max(g)::date
  from myclear_imports_tiktok i, generate_series(i.releves_du, i.releves_au, interval '1 day') g
 group by 1
on conflict (mois_releve) do nothing;

create or replace function myclear_charger_frais_tiktok(p_du date, p_au date, p_lignes jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare qui text := coalesce((select auth.jwt()->>'email'), current_user);
  m date; ndu date; nau date; o myclear_releves_mois; remplaces text[] := '{}'; ignores text[] := '{}'; n int := 0; k int;
begin
  if (select auth.jwt()->>'email') is not null
     and coalesce((select role from acces_board where lower(email) = lower(qui)), '') <> 'admin' then
    raise exception 'Accès refusé';
  end if;
  for m in select generate_series(date_trunc('month', p_du), date_trunc('month', p_au), interval '1 month')::date loop
    ndu := greatest(m, p_du); nau := least((m + interval '1 month - 1 day')::date, p_au);
    select * into o from myclear_releves_mois where mois_releve = m;
    if found and not (ndu <= o.du and nau >= o.au) then
      if ndu >= o.du and nau <= o.au then ignores := ignores || to_char(m, 'YYYY-MM'); continue; end if;
      raise exception 'Relevé de % : déjà chargé du % au %, le nouvel export va du % au %. Exporter le mois entier.', to_char(m, 'MM/YYYY'), o.du, o.au, ndu, nau;
    end if;
    delete from myclear_frais_tiktok where mois_releve = m;
    insert into myclear_frais_tiktok (mois_releve, mois, poste, montant)
    select m, (l->>'mois')::date, l->>'poste', (l->>'montant')::numeric
      from jsonb_array_elements(p_lignes) l where (l->>'mois_releve')::date = m;
    get diagnostics k = row_count; n := n + k;
    insert into myclear_releves_mois values (m, ndu, nau) on conflict (mois_releve) do update set du = excluded.du, au = excluded.au;
    remplaces := remplaces || to_char(m, 'YYYY-MM');
  end loop;
  insert into myclear_imports_tiktok (releves_du, releves_au, importe_par) values (p_du, p_au, qui);
  return jsonb_build_object('ok', true, 'lignes', n, 'mois_charges', remplaces, 'mois_ignores', ignores);
end $$;
revoke execute on function myclear_charger_frais_tiktok(date, date, jsonb) from public, anon, authenticated;
