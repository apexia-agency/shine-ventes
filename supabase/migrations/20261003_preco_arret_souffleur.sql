-- Produits arrêtés : souffleur sécheur ACS73 (Jérémy, 03/10/2026). Le pistolet de soufflage ACS63 n'est pas concerné.
insert into preco_arrets (sku, etat, decision, arrete, note)
values ('ACS73', null, 'Oui définitif', true, 'arrêt annoncé par Jérémy le 03/10/2026')
on conflict (sku) do update set decision = excluded.decision, arrete = true, note = excluded.note, maj_le = now();
