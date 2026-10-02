-- Rangeur de factures V5 : types de documents acceptés (facture, avoir, proforma, devis, acompte, autre).
-- Appliquée dans Supabase le 29/09/2026 (version 20260929135422) depuis la conversation du rangeur ;
-- ajoutée au dépôt le 02/10/2026, reprise telle quelle de supabase_migrations.schema_migrations.
alter table factures_achats drop constraint if exists factures_achats_type_doc_check;
alter table factures_achats add constraint factures_achats_type_doc_check check (type_doc in ('facture', 'avoir', 'proforma', 'devis', 'acompte', 'autre'));
