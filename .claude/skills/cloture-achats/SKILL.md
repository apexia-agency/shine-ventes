---
name: cloture-achats
description: Clôture mensuelle des achats SHINE (rangeur de factures) — contrôle des factures du mois, rapprochement avec la banque, décisions transformées en règles, livre envoyé au cabinet puis chargé comme mois clos. Utiliser quand Jérémy demande « clôture d'octobre », « clôturer les achats du mois », « vérifier le livre des achats ».
---

# Clôture mensuelle des achats

Argument : le mois `AAAA-MM` (sinon : le mois précédent). Lire d'abord, en entier :
1. `outils/factures/PROCEDURE_CLOTURE_ACHATS.md` — la procédure humaine ; tu en fais les mêmes étapes, rien d'autre.
2. La section « Board Factures (rangeur de factures d'achat V6) » du `README.md`.
3. `outils/factures/regles-livre-2026-09.mjs` (et les `regles-livre-*.mjs` plus récents) — les décisions déjà prises : ne jamais les rejouer autrement.
4. `outils/factures/ALIGNEMENT_LIVRE_JEREMY_2026-10.md` — écarts connus entre le rangeur et le livre de Jérémy.

Base Supabase `dfolpanugctzebwpfhze`. Tables : `factures_achats` (statut `classee` / `validee` / `a_verifier` / `ecartee`, `mois_comptable`, `ventilation`, `controles`, `motif`, `lecture`), `factures_fournisseurs` (règles), `factures_grand_livre` (mois déjà envoyés au cabinet), `factures_comptes`.
Fonctions : `factures_livre_donnees(mois)` (données du livre), `factures_export_mois(mois)` (CSV). Le livre Excel est fabriqué par `supabase/functions/livre-achats/livre.ts` (testable en local avec node et exceljs).

## Étapes

1. **État du mois** : nombre de factures par statut pour `coalesce(mois_comptable, date_facture)` dans le mois ; total en charge. Lister les « à vérifier » avec leur motif.
2. **À vérifier** : pour chacune, proposer un compte en t'appuyant sur les règles existantes, l'historique du fournisseur (`factures_grand_livre`, `factures_achats`) et la facture (lien Drive). Poser les questions à Jérémy **regroupées**, jamais une par une. Rien n'est validé sans sa réponse.
3. **Rapprochement banque** : relevés du mois (Drive « 4 - BANQUE A DEPOSER » ou `C:\Users\jeremy\Documents\SHINE-DIAGNOSTIC\01_BANQUE - EXPORT\` : CA, CIC, PayPal, Pleo). Chaque débit fournisseur doit avoir sa facture ; chaque facture son paiement ou rester due. Lister : paiements sans facture, factures payées deux fois, écarts de montant (acompte, trop-payé, devise). Les mouvements de compte courant avec Space Up (prêts, remboursements) ne sont pas des charges.
4. **Factures habituelles manquantes** : comparer les fournisseurs récurrents des trois mois précédents (`factures_grand_livre`) à ceux du mois.
5. **Doublons et documents annuels** : relire les contrôles `Doublon`, `Doublon possible`, `Document annuel`, `Mois déjà envoyé au cabinet`.
6. **Décisions → règles** : chaque décision durable devient une entrée dans un fichier `outils/factures/regles-livre-AAAA-MM.mjs` (même format), puis une migration `supabase/migrations/AAAAMMJJ_rangeur_regles_AAAA_MM.sql`, **commitée et poussée avant d'être appliquée** (règles du `CLAUDE.md`). Relancer `outils/factures/banc-livre-2026-09.mts` pour vérifier que rien ne recule.
7. **Livre final** : dans `C:\Users\jeremy\Documents\SHINE - Dépôt pour Claude\Fichier comptable\`, `SHINE_livre_achats_600-620_AAAA-MM.xlsx` (puis `_v2`… sans jamais écraser). Même présentation que le livre de septembre 2026.
8. **Mois clos** : une fois le livre envoyé au cabinet (Jérémy le confirme), charger ses lignes dans `factures_grand_livre` (source « Livre des achats AAAA-MM vN ») ; méthode : fonction RPC temporaire protégée par jeton, supprimée aussitôt après.
9. **Compte rendu** à Jérémy : ce qui est validé, les questions ouvertes, le total du mois, les règles ajoutées. Pas de mot pour le cabinet sauf demande.

## Garde-fous

- Ne jamais supprimer une facture ni une ligne : marquer (`ecartee`, motif) et garder le retour arrière.
- Ne pas trancher un cas nouveau sans Jérémy ; un doute reste « à vérifier ».
- Montants en euros avec espaces (12 345,67 €), français simple.
