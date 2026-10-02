-- Rangeur de factures V5 : ce que Claude a lu sur la facture (lecture brute) et le texte extrait du PDF.
-- Appliquée dans Supabase le 29/09/2026 (version 20260929132238) depuis la conversation du rangeur ;
-- ajoutée au dépôt le 02/10/2026, reprise telle quelle de supabase_migrations.schema_migrations.
alter table factures_achats
  add column if not exists lecture jsonb,
  add column if not exists texte text;
