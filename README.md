# Board ventes SHINE

CA par famille de clients, par canal et par produit. En ligne : https://shine-ventes.vercel.app (connexion par lien email).

## Comment ça marche

- `index.html` : tout le board (une seule page). Il lit les agrégats de la base Supabase `shine-ventes`.
- **Chaque push sur `main` met le board en ligne** (Vercel, en une minute environ).
- On ne publie plus par l'API Vercel : tout passe par ce dépôt, sinon le push suivant écrase la version en ligne.

## Règles à deux

1. `git pull` avant de toucher au code : on modifie tous les deux.
2. Messages de commit en français, qui disent ce qui change pour la personne qui regarde le board.
3. En cas de conflit sur la même partie, on en parle avant de trancher.

## Assistant ventes

Panneau de questions ouvert depuis le menu latéral (icône bulle).

- `supabase/functions/assistant/index.ts` : fonction serveur. Elle transmet la question à Claude (modèle `claude-opus-4-8`), qui interroge la base et renvoie la réponse et les tableaux à exporter en CSV.
- `supabase/migrations/20260925_assistant_sql.sql` : fonction SQL `assistant_sql`. Elle n'accepte que des lectures, avec les droits de la personne connectée.
- La clé API Claude est dans les secrets Supabase (`ANTHROPIC_API_KEY`), jamais dans le code.
- Une modification de ces fichiers ne s'applique pas toute seule : il faut redéployer la fonction dans Supabase.

Le dossier `supabase/` et ce fichier ne sont pas publiés avec le board (voir `.vercelignore`).

## Chiffres de contrôle (26/09/2026, après retrait des doublons ; 2024-2025 mis à jour le 28/09 après retrait des commandes de test)

| Exercice | CA HT total | dont CA produits | dont pros |
|---|---|---|---|
| 2024-2025 | 4 122 410 € | 4 049 152 € | 361 527 € |
| 2025-2026 (au 26/09) | 4 740 326 € | 4 707 682 € | 333 719 € |

L'exercice 2024-2025 est clos : son total ne doit plus bouger. 2025-2026 augmente chaque nuit avec les nouvelles factures.
Ces totaux ne doivent pas bouger quand on éclate des packs ou qu'on détaille EBP.
Doublons retirés : bascule du site pro (`supabase/migrations/20260925_doublons_bascule.sql`) et factures PrestaShop en double (`supabase/migrations/20260925_doublons_factures.sql`).
Commandes de test retirées (`supabase/migrations/20260928_commandes_test.sql`) : John Test (196,93 €, 2024-2025) et Société Test (27,96 €, 2025-2026).

## Compositions des packs et contenances (27/09/2026, Jérémy)

**Appliqué dans Supabase le 27/09/2026** (migrations `contenances_produits` et `packs_composition_site_et_ebp`, puis `rafraichir_agregats`) : 76 packs,
810 lignes. À ne pas refaire ni écraser : les compositions viennent des nomenclatures EBP (captures) et du site, validées par Jérémy.
Contrôle après application : CA 2024-2025 inchangé (4 122 607 €), CA éclaté = CA facturé sur 2025-2026 ; familles Pack et PLV
quasi vides (2 k€ et 0,5 k€ restants sur 2025-2026) ; seulement 90 unités de chimie sans contenance.

- `supabase/migrations/20260927_packs_composition_site.sql` : 24 packs du site (dont ACS48 = foam ACS47 + mousse active 750), dont les variantes HARD / SOFT / accessoires
  (ASPS07, ASPS03, ASPS02 remplacés fin juin 2026 par ASPS07-H, ASPS07-S…, chaque variante a sa composition).
- `supabase/migrations/20260927_packs_composition_ebp.sql` : 34 packs EBP (colis Norauto, box et offres d'implantation,
  offres de réappro, packs cadeaux et Noël, Starfobar). Lignes « Non inclus » (PLV, présentoirs) exclues.
- `supabase/migrations/20260927_contenances_produits.sql` : contenances manquantes (MDD, MyClear, petits formats, aérosols en volume net).
- Ignorés exprès : packs MyClear, PACK-HALLOWEEN, PACK-STD (peu ou pas de ventes). Reste PACK-KDO-GBH (2 produits sur 4 connus).
- Le brouillon `outils/packs/compositions_a_valider.csv` (texte du site) est remplacé par ces scripts ; les écarts sont listés
  dans le message du commit qui ajoute cette section.
- Après application : `select rafraichir_agregats();`. Le CA total ne doit pas bouger (voir chiffres de contrôle).

## Data Center (board particuliers, marketing)

- `data-center.html` : le board Data Center (même connexion que le board Ventes). On passe d'un board à l'autre par le bouton en grille sous les onglets du menu latéral.
- Périmètre : **particuliers uniquement** (PrestaShop shine-group.fr, groupes Client, Invité, Visiteur via `groupes_segments`). PrestaShop est la source de vérité des commandes et du CA.
- Accès : colonne `acces_board.boards` (ex. `{"data_center":"lecteur"}`) ; un `admin` global voit tout. Seuls les admins du Data Center changent le statut des préconisations.
- Données : schéma Supabase `marketing` (non exposé à l'API), lu uniquement par `dc_donnees(du, au)` ; le comparateur (N-1, période précédente, dates choisies) appelle la fonction deux fois.
- Chargement : Edge Function `supabase/functions/dc-ingestion` (Windsor → Supabase), chaque nuit à 04:30 (heure de Paris) sur les 30 derniers jours, puis contrôles automatiques (`dc_controler`). Secret `CLE_API_WINDSOR` dans Supabase, jamais dans le code.
- Règle GA4 : uniquement des dimensions `session_*` (jamais `campaign` ni `source_medium` sans préfixe, qui sont des champs d'attribution des conversions et faussent les sessions).
- Migrations appliquées dans Supabase : `data_center_01` à `data_center_08` (à exporter dans `supabase/migrations/` avec `supabase db pull`).

## Boards Achats et Charges

Ouverts par le bouton « Changer de board » (même page : `./#achats`, `./#charges`).

- Source : plan de trésorerie Google Sheet « SHINE_pilotage_tresorerie » (onglets ACHATS, SALAIRES, TRANSPORT, FRAIS GÉNÉRAUX, MARKETING, IMPÔTS ET TAXES, LOYERS, VÉHICULES, AUTRES, SPACE UP).
- Relu chaque lundi à 7h par le workflow n8n « IMPORT — Plan de trésorerie (achats et charges) vers le board », qui charge la table `tresorerie_mensuel` (fonction `charger_tresorerie`). Il refuse de charger si un onglet ne retombe pas sur sa ligne TOTAL.
- Montants **payés en banque** (TTC quand il y a de la TVA), **mois réels seulement** (ceux où des encaissements sont constatés dans FLUX MENSUELS). Comparaison N-1 sur les mêmes mois.
- Salaires en deux totaux (salaires, charges sociales), jamais le détail par personne. Space Up : seulement les prestations payées par SHINE. La TVA reversée est affichée à part, hors charges.

## Board Transport (coûts des colis DPD et Colissimo)

- `transport.html` : le board (même connexion que les autres, ouvert à tous les associés), par le bouton « Changer de board ».
  Onglets : tableau de bord, régions, profil de fret (comparaison à poids égal, barème constaté, économies possibles), frais annexes, fichiers et couverture, comptes rendus mensuels.
- Sources : exports Excel DPD (un par mois et par service : Relais, Predict, Classic + multi-colis) et factures PDF Colissimo, déposés dans l'onglet Fichiers.
  Le même fichier (ou la même facture Colissimo sous un autre nom) n'est jamais compté deux fois. Les factures DPD en PDF ne sont pas lues (pas de détail par colis).
- Lecture des fichiers : `transport-lecteurs.js` (dans le navigateur au dépôt, et `outils/transport/charger.mjs` pour charger un dossier entier).
- Base : `transport_fichiers` (fichiers lus, statut intégré / doublon / retiré), `transport_colis` (une ligne par colis, sans nom ni adresse), `transport_comptes_rendus`.
  Le board lit `transport_donnees(du, au)` (agrégats). Migrations `20260929_board_transport.sql` et `20260929_transport_tranche_multicolis.sql`.
- Règles de coût : coût HT = transport + gasoil + taxes + annexes.
  - DPD : « Prix cumulé » ne contient que le transport ; on ajoute l'indexation gasoil, la participation sûreté et la contribution logistique (taxes), et les colonnes « Fact. … » (annexes).
    Une ligne à 0 colis = frais ajoutés après coup sur un colis déjà facturé (retour, SMS, relais non retiré…). Plusieurs colis sur une ligne = multi-colis (depuis juillet 2025).
  - Colissimo : transport = port net, gasoil = CAE, taxes = décarbonation + SMIC, annexes = suppléments. Ce que le détail par colis n'explique pas (suppléments non rattachés, arrondis)
    devient une ligne « ajustement de facture » : chaque facture retombe au centime sur son récapitulatif. Avoirs, indemnisations et prestations complémentaires restent au niveau de la facture.
  - Colissimo nouveau format (depuis août 2026) : récapitulatif par service et par tarif, sans poids ni code postal (région « inconnue », poids « inconnu »).
- Chargement initial (29/09/2026) : 83 exports DPD (janv. 2024 → mai 2026, 58 191 colis, 481 124 € HT) et 20 factures Colissimo (févr. 2025 → août 2026, 55 643 colis, 456 309 € HT).
  Doublons écartés : « 2025-08 DPD RELAI.xlsx » (copie de juillet 2025), « 2026-01 DPD RELAI BIS », et 4 factures Colissimo en double.
  Fichiers manquants : DPD Relais août 2025 et mars 2026, DPD Predict mars 2026, tout DPD depuis juin 2026.

## Board Factures (rangeur de factures d'achat V5)

- `factures.html` : board **réservé** (pas ouvert à tous les associés). Accès : rôle admin, ou `acces_board.boards.factures` = `lecture` / `valideur` / `admin`.
  Ajouter quelqu'un : `update acces_board set boards = coalesce(boards, '{}') || '{"factures": "valideur"}' where email = '…';`
  Onglets : à vérifier (la file que Robin vide chaque semaine), factures traitées (60 jours), règles fournisseurs.
- Chaîne : dépôt d'un PDF dans le dossier Drive « Factures SHINE / 1 - A DEPOSER » (Drive de robin.l@shine-group.fr, partagé avec Jérémy)
  → flux n8n « Rangeur de factures SHINE » (toutes les 10 min) → fonction `lire-facture` → renommé et rangé dans « 2 - CLASSEES » ou « 3 - A VERIFIER ».
- Principe (spécification de Jérémy du 28/09/2026) : Claude (Sonnet 5.5) **lit** la facture, les **règles décident** du compte
  (fournisseur → territoire FR / INTRA / IMPORT → nature → compte) ; 12 contrôles d'anomalie (devise, TVA sur import/intra, proforma, acompte,
  destinataire ≠ SHINE, doublon, scan…). Rien de douteux n'est tranché : « à vérifier » avec le motif. Environ 3 centimes par facture.
- Base : `factures_fournisseurs` (181 fournisseurs issus des 349 clés du grand livre, `outils/factures/fournisseurs-regroupement.mjs`),
  `factures_dictionnaire` (natures des lignes pour les 7 fournisseurs éclatés), `factures_cles_ecartees`, `factures_achats` (lecture, ventilation, contrôles).
  Fonctions : `factures_a_verifier_liste`, `factures_fournisseurs_liste`, `traiter_facture` (valider / écarter / annuler ; « Retenir » ajoute la règle au fournisseur), `acces_factures`.
- Code : `supabase/functions/lire-facture/` (`index.ts` lecture, `moteur.ts` règles, testable hors ligne) ; `{ reclasser: id }` rejoue les règles sans rappeler Claude.
- Questions ouvertes : comptes 61324000 / 61327000 de SCI CMD, polish Scholl (produit fini chimique ?), 13 comptes « à créer » par le comptable.
