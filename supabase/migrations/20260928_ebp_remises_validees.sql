-- Écart EBP (appliqué le 28/09/2026).
-- Le CA EBP vient de l'export du CA par client et par mois (les factures) ; le détail par produit vient de
-- l'« Historique par articles », AVANT les remises en pied de facture. appliquer_ebp_detail répartit l'écart sur les
-- articles au prorata quand la facture fait 70 % à 130 % du détail (remises courantes : 5 à 25 % selon le client).
-- Au-delà, l'écart est pris pour une anomalie : détail laissé tel quel + ligne « Écart entre facture et détail ».
-- Seul vrai cas trouvé : J&J Discount, août 2025, facture 7 642,71 € HT pour 14 251 € de détail.
-- Robin (28/09) : facture juste, grosse remise, vente spéciale DOM-TOM (Nouvelle-Calédonie).
-- → table des remises validées : pour ces mois-là, la remise est répartie comme les autres.
-- Résultat : août 2025 re-détaillé (appliquer_ebp_detail('2025-08-01','2025-08-31')), total inchangé (71 881,99 €),
-- plus aucun mois en écart sur août. Reste < 1 000 € d'écarts minimes (Point S Crolles, KT Glass, SublimCar, Dachser).

create table if not exists ebp_remises_validees (
  code text not null,
  mois date not null,
  note text,
  valide_par text,
  valide_le timestamptz not null default now(),
  primary key (code, mois)
);
alter table ebp_remises_validees enable row level security;

insert into ebp_remises_validees (code, mois, note, valide_par)
values ('CL00647', '2025-08-01', 'J&J Discount : grosse remise, vente spéciale DOM-TOM (Nouvelle-Calédonie). Facture 7 642,71 € HT juste.', 'robin.l@shine-group.fr')
on conflict do nothing;

do $$
declare d text; avant text := 'if f < 0.7 or f > 1.3 then f := 1; end if;';
begin
  d := pg_get_functiondef('public.appliquer_ebp_detail(date,date)'::regprocedure);
  if position('ebp_remises_validees' in d) > 0 then return; end if;
  if position(avant in d) = 0 then raise exception 'texte attendu introuvable'; end if;
  d := replace(d, avant, 'if (f < 0.7 or f > 1.3) and not exists (select 1 from ebp_remises_validees r where r.code = pc.source_client_id and r.mois = pc.mois) then f := 1; end if;');
  execute d;
end $$;

-- Puis : select appliquer_ebp_detail('2025-08-01', '2025-08-31');  puis  select finaliser_collecte();
