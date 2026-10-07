# Règles pour Claude sur le dépôt shine-ventes

Ce fichier est lu au début de chaque conversation Claude ouverte dans ce dépôt. Plusieurs personnes travaillent en même temps sur ce dépôt et sur la base : Jérémy, Robin, et une ou plusieurs conversations Claude pour chacun. Ces règles évitent qu'un travail écrase l'autre.

## Avant de commencer

1. `git pull --rebase`, puis lire les derniers commits (`git log --oneline -15`) et les dernières migrations (`ls supabase/migrations | tail`). Quelqu'un a peut-être changé le board ou la base depuis la dernière fois.
2. Lire le `README.md` : fonctionnement, chiffres de contrôle, décisions déjà prises.
3. Vérifier dans Supabase (`supabase_migrations.schema_migrations`) les migrations appliquées récemment. Une migration peut être appliquée dans la base avant d'être poussée sur GitHub.

## Pendant le travail

- **Git d'abord, Supabase ensuite.** Toute modification de la base est écrite dans un fichier `supabase/migrations/AAAAMMJJ_sujet.sql`, commitée et poussée **avant** d'être appliquée dans Supabase. Sinon l'autre ne voit pas le changement et risque de l'écraser.
- **Pousser souvent** : un commit par changement cohérent, `git pull --rebase` juste avant chaque `git push`. Chaque push sur `main` met le board en ligne (Vercel).
- **Ne jamais réécrire l'historique** (pas de `push --force`, pas de `reset --hard` sur du travail poussé).
- **Modifier une fonction SQL existante** (`rafraichir_agregats`, fusions…) : partir de sa définition actuelle dans la base (`pg_get_functiondef`), pas d'une ancienne copie, et ne changer que la partie voulue. Une autre conversation l'a peut-être modifiée entre-temps.
- **Ne rien supprimer dans les données** : on marque (`retenue = false`, `doublon_de = 'motif:…'`, fusions journalisées) et on prévoit le retour arrière dans la migration.
- **Même zone de code que quelqu'un d'autre** (même carte du board, même fonction) : s'arrêter et demander à Jérémy avant de trancher.
- Après un changement qui touche aux chiffres : relancer `rafraichir_agregats()` et comparer aux chiffres de contrôle du `README.md`. Tout écart est expliqué ou corrigé avant de pousser.
- Fonctions Edge (`supabase/functions/`) : une modification ne s'applique qu'après redéploiement. Le dire dans le commit si ce n'est pas fait.

## Commits et textes

- Messages de commit **en français**, qui disent ce qui change pour la personne qui regarde le board (« Ventes : filtre Chimie / Accessoires dans les volumes »), pas le détail technique.
- Textes du board et des fichiers livrés : français simple, sans jargon, montants en euros avec espaces (12 345 €).
- Mettre à jour le `README.md` quand une règle, un chiffre de contrôle ou une source change.

## Architecture (à respecter, pas à réinventer)

- **Board Ventes** `index.html` (une seule page, onglets, boards Achats et Charges via `#achats`, `#charges`) et **Data Center** `data-center.html`. Ils ne lisent que des **agrégats** (`agg_ventes_mensuel`, `agg_produits`, `agg_produits_mensuel`, `agg_commandes_mensuel`, `agg_clients`, `agg_jour`), jamais les tables de détail.
- **Base Supabase** `dfolpanugctzebwpfhze` :
  - `ventes_pieces` / `ventes_lignes` : factures et lignes (`retenue`, `doublon_de`) ;
  - `clients` / `clients_sources` : une fiche par client, rattachée à ses identifiants PrestaShop et EBP ;
  - `produits`, `produits_composants` (nomenclatures), `packs_composition` (packs éclatés en produits) ;
  - `tresorerie_mensuel` (achats et charges) ; schéma `marketing` pour le Data Center.
- **`rafraichir_agregats()`** recalcule tous les agrégats. Il tourne chaque nuit après la collecte : un nouveau calcul se branche dedans.
- **Familles de clients (segments)** : B2C (Particuliers), B2B_PRO (Pros), B2B_REVENDEUR (Revendeurs), MARKETPLACE, MDD, AUTRE, INTRAGROUPE, HORS_PRODUIT, NON_SEGMENTE. **Le segment vient de la fiche client, pas du canal** (un revendeur qui commande sur le site particuliers reste un revendeur). Les segments validés à la main (`segment_valide`) ne sont jamais écrasés.
- **Exercice** : du 1er octobre au 30 septembre (2025-2026 arrêté au 31/08/2026 pour la compta).
- **Canaux** : `prestashop_b2c` (shine-group.fr), `prestashop_pro` (site pro, depuis mai 2026), `ebp_revendeur` / `ebp_pro` (EBP, agrégé par client et par mois), `tiktok_b2c`, `jokeriders_marketplace`, `myclear` (hors CA SHINE).
- **Packs** éclatés en produits sur un niveau, au prorata du prix de référence (prix moyen particuliers sur 12 mois) : le CA éclaté est égal au CA facturé.

## Comptabilité des achats

- Rangeur de factures (board Factures, fonctions `lire-facture` et `livre-achats`) : voir la section du `README.md`.
- Clôture mensuelle des achats : procédure écrite pour un humain `outils/factures/PROCEDURE_CLOTURE_ACHATS.md` ; dans Claude, commande `/cloture-achats AAAA-MM`.
- Toute décision comptable devient une règle (`outils/factures/regles-livre-*.mjs` + migration), jamais seulement une réponse dans la conversation.

## Données et confidentialité

- **Les données vivantes restent ici.** Les autres conversations Claude (compta, etc.) ne reçoivent que des fichiers figés à une date, jamais un accès à la base.
- Fichiers livrés à Jérémy : dossier `C:\Users\jeremy\Documents\SHINE - Dépôt pour Claude\`, nom daté (`SHINE_sujet_AAAA-MM-JJ.xlsx`), jamais écraser une version qu'il a peut-être ouverte : créer `_v2`, `_v3`.
- Aucune clé ni mot de passe dans le code : secrets Supabase uniquement.
- Aucune donnée client (fichiers Excel, CSV d'export) dans le dépôt.

## En fin de conversation

- Tout est commité et poussé, migrations comprises ; `git status` propre.
- Dire clairement à Jérémy ce qui est en ligne, ce qui est appliqué dans Supabase, ce qui reste à faire (fonction à redéployer, question ouverte).
