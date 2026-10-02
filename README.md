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

## Chiffres de contrôle (02/10/2026, après ajout des ventes TikTok Shop et de la fin septembre EBP)

| Exercice | CA HT total | dont CA produits | dont pros |
|---|---|---|---|
| 2024-2025 | 4 124 022 € | 4 050 764 € | 360 969 € |
| 2025-2026 (exercice complet) | 5 024 948 € | 4 801 692 € | 357 881 € |

Le total 2025-2026 comprend 190 509 € de refacturation Nexus (Intragroupe, hors produits : montrée à part dans « Autres facturations », pas dans le CA des ventes).
L'exercice 2024-2025 est clos : son total ne doit plus bouger (4 122 410 € avant TikTok + 1 612 € de ventes TikTok d'août et septembre 2025). 2025-2026 augmente chaque nuit avec les nouvelles factures.
Ces totaux ne doivent pas bouger quand on éclate des packs ou qu'on détaille EBP.
Doublons retirés : bascule du site pro (`supabase/migrations/20260925_doublons_bascule.sql`) et factures PrestaShop en double (`supabase/migrations/20260925_doublons_factures.sql`).
Commandes de test retirées (`supabase/migrations/20260928_commandes_test.sql`) : John Test (196,93 €, 2024-2025) et Société Test (27,96 €, 2025-2026).

## Ventes TikTok Shop (02/10/2026, Jérémy)

Les ventes TikTok Shop SHINE sont dans le board : canal `tiktok_b2c`, famille Particuliers, sous-famille « TikTok Shop ». 1 520 commandes du 23/07/2025 au 01/10/2026, 29 053 € HT de produits (1 612 € sur 2024-2025, 27 251 € sur 2025-2026) et 4 733 € HT de port.
- Source : exports « Toutes les commandes » du Seller Center, préparés par `outils/tiktok/tiktok_vers_base.js` puis chargés par la fonction `charger_tiktok` (`supabase/migrations/20261002_tiktok_shop.sql`), suivie de `finaliser_collecte()`. **Chargement à la main** tant que la collecte de nuit ne ramène pas TikTok (codes API à obtenir, côté Robin) : les ventes après le 01/10/2026 ne sont pas dans le board.
- Règles (les mêmes que l'export comptable) : commandes annulées, pas encore expédiées ou remboursées en entier écartées ; date = expédition ; HT = TTC / 1,2 ; remise TikTok non déduite (TikTok la reverse), remise vendeur déduite ; remboursement partiel déduit.
- Articles sans référence dans TikTok rattachés par le libellé (`20261002_tiktok_references.sql`). La « Microfibre de séchage ONE PASS XXL » est l'ACS77 (confirmé par Jérémy le 02/10 ; produit désactivé pour rupture), `20261002_tiktok_one_pass_acs77.sql`.
- Camembert des volumes en mode CA : une part « Frais de port facturés » s'ajoute aux formats (le CA des produits ne contient pas le port).

## Nexus : famille Intragroupe (02/10/2026, Jérémy)

Le client EBP Nexus (`CL00803`) est rangé dans la famille **Intragroupe**, segment validé (`supabase/migrations/20261002_nexus_intragroupe.sql`). Sa facture FA00004605 du 30/09/2026 (190 508,51 € HT de refacturations) est dans la base depuis le 02/10 : hors produits, elle n'entre pas dans le CA des ventes.

## EBP : fin septembre 2026 rechargée (02/10/2026, Jérémy)

Septembre EBP a été rechargé en entier à partir des exports EBP du 02/10 (la base s'arrêtait au 24/09) : 119 clients, 281 928 € HT net, dont 91 420 € hors Nexus (54 869 € avant). Marche à suivre et précautions dans `supabase/migrations/20261002_ebp_fin_septembre.sql`, préparation des fichiers par `outils/ebp/ebp_mois_vers_base.js`.
- **Attention pour un prochain rechargement EBP** : `appliquer_ebp_detail` repart de la sauvegarde `bak_ebp_lignes_20260925`. Si on recharge les montants d'un mois sans aligner cette sauvegarde, l'ancien total du mois s'ajoute au nouveau.
- Quatre nouveaux clients : Nexus (Intragroupe, validé), Bourbon Bikes (MDD, proposé), Dam's Garage et Alti'Cars (Revendeurs indépendants, proposés).

## Préco de vente (board Achats, 02/10/2026, Jérémy)

Onglet « Préco de vente » du board Achats (`#preco`), sous-onglets Chimie et Accessoires (accessoires : à venir). **Environnement à part** : tables `preco_*`, agrégat `agg_preco_chimie`, fonction `rafraichir_preco()` lancée chaque nuit par sa propre tâche (`preco-nuit`, 5 h 40 UTC). Rien n'est modifié dans la collecte ni dans `rafraichir_agregats` (`supabase/migrations/20261002_preco_ventes.sql`).
- **Méthode chimie** : ventes du même mois de l'exercice précédent (packs éclatés) − opérations exceptionnelles (`preco_exclusions`) + correction des ruptures probables chez les particuliers, × évolution visée par famille de clients (objectif ÷ réalisé, `preco_objectifs`).
- **Objectifs 2026-2027** (Jérémy) : particuliers 3 000 000 € (site, réalisé 2 910 472 €, +3,1 %), revendeurs avec Jokeriders 1 550 000 € (réalisé 1 504 321 €, +3,0 %), pros 350 000 € (réalisé 341 011 €, +2,6 %). Pour changer un objectif : `update preco_objectifs set objectif_ca = … where groupe = '…'; select rafraichir_preco();`.
- **Opération retirée** : implantation Norauto d'octobre 2025 (colis `COL…-IMPLANT` de Mobivia). L'opération de mai 2026 est gardée.
- **Rupture probable** : mois où les particuliers achètent moins de 40 % de la moyenne des deux mois voisins (moyenne d'au moins 40 unités) ; ajout plafonné à 30 % de l'année. À remplacer par les jours d'indisponibilité du tableau de Laurent quand il sera lu chaque nuit.
- **Tableau de Laurent** : copie du 02/10/2026 dans `preco_laurent` (bidons et aérosols : flux, stock et en commande, en unités — onglets « Bidons Chimie » et « Aérosols et chimie spé. », colonnes D, E, H) et `preco_cuves` (onglet « Vrac Production », colonnes D et E, en **litres**). Étape suivante : lecture de nuit du Google Sheet, puis alertes de stock bas.
- **Tableau du board** (`supabase/migrations/20261002_preco_ventes_v2.sql`) : les formats d'un même produit sont regroupés sous une ligne produit (litres en cuve, vrac à commander). Pour chaque format : à conditionner, stock, prévu sur les trois prochains mois, flux, couverture, puis les trimestres suivants. La prévision est glissante (12 mois à partir du mois en cours). Stock visé au choix : 60, 75 ou 90 jours.
- **Produits arrêtés** (`preco_arrets`, liste de Jérémy du 02/10/2026) : un format sorti du catalogue n'a plus de préconisation et ne compte pas dans le besoin en vrac ; le board montre son stock restant. Sous-onglet « Chimie PF » : produits sans cuve (achetés finis), préco « à commander ».
- **Objectifs modifiables dans le board** (stylo sur chaque objectif, valideurs et administrateurs) : fonction `preco_definir_objectif`, qui recalcule la préco.

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
  Onglets : tableau de bord (camembert comparatif DPD / Colissimo : découpage par transporteur, livraison, mode ou poids ; pastilles pour retirer des données), régions (carte de France par région), profil de fret (comparaison à poids égal, barème constaté, économies possibles), frais annexes, fichiers et couverture, comptes rendus mensuels.
- Sources : exports Excel DPD (un par mois et par service : Relais, Predict, Classic + multi-colis) et factures PDF Colissimo, déposés dans l'onglet Fichiers.
  Le même fichier (ou la même facture Colissimo sous un autre nom) n'est jamais compté deux fois. Les factures DPD en PDF ne sont pas lues (pas de détail par colis).
- Lecture des fichiers : `transport-lecteurs.js` (dans le navigateur au dépôt, et `outils/transport/charger.mjs` pour charger un dossier entier).
- Base : `transport_fichiers` (fichiers lus, statut intégré / doublon / retiré), `transport_colis` (une ligne par colis, sans nom ni adresse), `transport_comptes_rendus`.
  Le board lit `transport_donnees(du, au)` (agrégats). Migrations `20260929_board_transport.sql` et `20260929_transport_tranche_multicolis.sql`.
- Règles de coût : coût HT = transport + gasoil + taxes + annexes.
  - DPD : « Prix cumulé » ne contient que le transport ; on ajoute l'indexation gasoil, la participation sûreté et la contribution logistique (taxes), et les colonnes « Fact. … » (annexes).
    Une ligne à 0 colis = frais ajoutés après coup sur un colis déjà facturé (retour, SMS, relais non retiré…) : ce n'est pas un colis (l'ancien board les comptait en 0 à 1 kg, d'où plus de colis légers et un coût moyen plus bas, ex. DPD Relais 0-1 kg oct.–déc. 2025 : 3,56 € ancien, 5,08 € réel). Plusieurs colis sur une ligne = multi-colis (depuis juillet 2025), rangé dans la tranche du poids moyen d'un colis.
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
- Rangement : `2 - CLASSEES / <exercice> / <mois> / <compte>_<LIBELLÉ>` (plan de comptes `factures_comptes`, fonction `factures_chemin_rangement`, sous-flux n8n « trouver ou créer un dossier »).
- Export comptable : chaque nuit à 5 h 30 (flux n8n « export comptable mensuel »), pour le mois précédent et le mois en cours, `AAAA-MM_SHINE_ecritures_achats.csv`
  (import du cabinet : Journal ; Date ; Société ; Pièce ; Tiers ; N° facture ; Compte ; Libellé ; Débit ; Crédit ; Fichier) et `AAAA-MM_SHINE_journal_achats.csv`
  (30 colonnes, une ligne par facture) dans le dossier du mois. Fonction `factures_export_mois(mois)` ; pièces `AC-<exercice>-0001` attribuées au premier export.
  TVA : FR déductible (44566, 44562 pour les immobilisations), non déductible (ajoutée à la charge), autoliquidation (445662 / 4452), sans TVA. Avoir : sens inversé.

## Trieur de mails de Jérémy

- But : trier la boîte `shinegroupfr@gmail.com` (les adresses `jeremy@` et `jeremy.b@shine-group.fr` y arrivent déjà), mettre de côté
  ce qui ne sert à rien, préparer un brouillon quand une réponse est attendue. **Rien n'est envoyé, rien n'est supprimé** : Jérémy envoie et vide lui-même.
- **Indépendant de l'agent mail de Robin** (flux n8n « Boîte pro », app FRIDAY, autre base) : aucun flux, table ni fonction en commun. Ne pas les relier sans l'accord des deux.
- Chaîne : flux n8n « Boîte Jérémy · tri et brouillons » → fonction `trier-mail` → libellé Gmail (`TRI/À supprimer`, `TRI/À répondre`, ou un libellé existant) et brouillon dans le fil.
- Ordre de décision : mail d'un collègue SHINE → gardé ; règle de `mails_regles` (adresse exacte, puis domaine) ; sinon Claude (Opus 5.5) lit le mail.
  Garde-fous : jamais « inutile » pour SHINE, pour un client connu ou pour une règle « garder » ; « inutile » seulement si Claude en est sûr à 80 % au moins.
- Accès à la base : la seule lecture ouverte est `mail_contexte(empreinte)` (fiche client, chiffre par exercice, 5 dernières factures avec suivi). Pas de SQL libre : un mail est écrit par un inconnu.
- Confidentialité : ni le texte des mails ni les adresses des correspondants ne sont gardés. `mails_traites` garde le domaine, l'empreinte SHA-256 de l'adresse, la décision et son motif.
- Corrections de Jérémy dans Gmail : libellé `TRI/Toujours inutile` ou `TRI/Toujours garder` posé sur un mail. Le flux n8n « Boîte Jérémy · apprendre des corrections »
  (toutes les 30 min) en fait une règle (`mail_regle_apprendre`), range le mail en conséquence et retire le libellé. « Toujours garder » est gardé par empreinte de l'adresse (portée `empreinte`), pas par l'adresse.
- Ajouter une règle : `insert into mails_regles (portee, cle, decision, libelle) values ('domaine', 'exemple.com', 'inutile', null);` (`origine = 'claude'` : règle proposée, à confirmer par Jérémy).
- Code : `supabase/functions/trier-mail/index.ts` ; `{ essai: true }` décide sans rien écrire. Appel avec la clé service (connexion n8n « Supabase SHINE ventes »).
- n8n, dossier « JEREMY » : « Boîte Jérémy · tri et brouillons » (toutes les 5 min, nouveaux mails seulement) et « Boîte Jérémy · essai de la fonction trier-mail » (faux mail, sans écriture, à ne pas publier).
- État au 02/10/2026 : fonction en ligne et essayée (4 faux mails : règle, demande d'une acheteuse, publicité piégée, facture Google Ads). Flux **publié le 02/10 à 18 h 30**
  avec la connexion n8n « Gmail account 3 » (boîte `shinegroupfr@gmail.com`, vérifiée par ses libellés ; « Gmail account » et « Gmail account 2 » sont à Robin). Libellés `TRI/À supprimer` et `TRI/À répondre` créés.
- Boîte pro : c'est `jeremy.b@shine-group.fr` (serveur poste.io, webmail.shine-group.fr). Un filtre du webmail copie tout vers Gmail, mais seuls les mails internes `@shine-group.fr` y arrivent ;
  les mails externes transférés n'arrivent pas (cause non vérifiée, sans doute refusés par Gmail). Gmail ne relève plus les boîtes externes ; l'envoi « en tant que » `jeremy.b@` est déjà réglé dans Gmail. À régler côté serveur de messagerie.
- Pas encore fait : rattrapage des anciens mails non lus, factures en pièce jointe vers le rangeur, fiche fournisseur.
