# Collecte de nuit : ce qu'il faut ajouter pour l'export comptable mensuel

**Pour** : Robin (et sa conversation Claude). **De** : Jérémy (conversation Claude du 01/10/2026).
**But** : un bouton « Export mensuel » dans le board Ventes qui fabrique tout seul le fichier envoyé chaque mois au cabinet comptable, sans déposer de fichiers à la main.

## Pourquoi il manque des données

Le fichier envoyé au cabinet (`SHINE_export_comptable_ventes_segmente_2025-10_a_2026-08_v7.xlsx`) a été fabriqué à partir des **exports comptables** déposés à la main chaque mois, pas à partir de la base. La base du board ne garde que le HT : elle n'a ni la TVA, ni les comptes, ni le mode de paiement, ni le statut des commandes, ni les factures EBP une par une.

Le bouton ne peut exporter que ce que la base contient. Il faut donc que la collecte de nuit ramène, en plus de ce qu'elle fait déjà, les quatre blocs ci-dessous. **Rien de ce qui existe n'est modifié** : ce sont des tables en plus, que le board Ventes actuel ne lit pas.

## Bloc 1 — Écritures comptables des ventes PrestaShop (les deux sites)

Source : le module d'export comptable de PrestaShop, celui qui produit aujourd'hui `export_comptable_AAAA-MM-JJ_AAAA-MM-JJ.txt` (site particuliers) et `export_comptable_… - Professionnels.txt` (site pro). Une ligne du fichier = une ligne de la table, **sans rien recalculer**.

Table proposée : `compta_ventes_ecritures`

| Colonne | Type | Contenu (colonne de l'export) |
|---|---|---|
| `source` | text | `prestashop_b2c`, `prestashop_pro`, `ebp` (bloc 3) |
| `date_piece` | date | `Date` |
| `journal` | text | `Journal` |
| `id_commande` | text | `ID Commande` |
| `ref_commande` | text | `Ref Commande` (c'est la clé de rapprochement avec `ventes_pieces.num_commande`) |
| `pays` | text | `Pays` |
| `id_client` | text | `ID Client` |
| `client` | text | `Client` |
| `societe` | text | `Société` |
| `compte` | text | `Compte` (CLIENT, 7071100, 445710, 708500, 709700, 70715, 46715, 70716, 46716, 7071200, 7085100, 709710…) |
| `num_piece` | text | `Facture` (ex. `#FA26033054`, `#FP26117459`, `A000179` pour un avoir) |
| `libelle` | text | `Libelle` |
| `type_paiement` | text | `Type de paiement` |
| `montant` | numeric | `Montant` |
| `debit` | numeric | `Debit` |
| `credit` | numeric | `Credit` |
| `id_transaction` | text | `ID de transaction` (vide si aucun) |
| `ligne_no` | int | rang de la ligne dans la pièce (pour garder l'ordre et éviter les doublons) |
| `importe_le` | timestamptz | date du chargement |

Clé unique : (`source`, `num_piece`, `ligne_no`). Rechargement : chaque nuit, **le mois en cours et le mois précédent** sont remplacés en entier (une facture peut être modifiée ou annulée après coup).

Points à respecter, constatés sur les 11 mois déjà traités :
- l'export d'octobre 2025 était séparé par des tabulations, les autres par des points-virgules ;
- en avril 2026, les factures du site pro étaient dans l'export du site particuliers (pas de fichier pro séparé) ;
- les montants ont une virgule décimale ;
- certaines pièces ne sont pas équilibrées au centime (arrondis de TVA) : on ne corrige pas.

## Bloc 2 — Statut des commandes PrestaShop (les deux sites)

Sert à savoir quelles factures doivent être annulées par un avoir. Aujourd'hui Jérémy exporte à la main la liste des commandes « Annulé » et « Remboursé » de chaque back-office.

Table proposée : `compta_commandes_etats`

| Colonne | Type | Contenu |
|---|---|---|
| `source` | text | `prestashop_b2c`, `prestashop_pro` |
| `id_commande` | text | ID PrestaShop de la commande |
| `ref_commande` | text | Référence (ex. `TGSEGBULH`) |
| `etat` | text | Statut actuel, tel qu'affiché : `Annulé`, `Remboursé`, `Erreur de paiement`, `Livré`… |
| `date_commande` | timestamptz | Date de la commande |
| `date_etat` | timestamptz | Date du passage dans ce statut (**c'est l'information qui manque aujourd'hui** : elle donne la vraie date de l'annulation ou du remboursement) |
| `total_ttc` | numeric | Total de la commande |
| `montant_rembourse` | numeric | Montant réellement remboursé, si PrestaShop le donne (permet de traiter les remboursements partiels) |
| `mode_paiement` | text | Mode de paiement |
| `maj_le` | timestamptz | date du chargement |

Clé unique : (`source`, `id_commande`). Il suffit de charger les commandes dont le statut est Annulé, Remboursé ou Erreur de paiement, sur les 13 derniers mois.

## Bloc 3 — Factures EBP une par une

Aujourd'hui la base a un total par client et par mois (`EBP-AAAAMM-CLxxxxx`). Le cabinet a besoin de chaque facture avec son vrai numéro (`FA00003240`, `AV00000252`).

Source : l'export comptable d'EBP, fichier `Shine Group.txt` (largeur fixe).
- Lignes `M` : expression `^M(.{8})(.{2})(.{3})(\d{6})(.{21})([DC])([+-]\d{12})` → compte, journal, date (JJMMAA), libellé, sens, montant en centimes ; le numéro de pièce est le dernier mot de la ligne.
- Le compte qui commence par `0` est le compte client (`0CL00199` → client `CL00199`).
- Lignes `C0` : nom du client (colonnes 10 à 39).

Destination : la même table `compta_ventes_ecritures`, `source = 'ebp'`, `id_client` = code client EBP, `compte` = `CLIENT CL00199` pour la ligne client, `num_piece` = numéro de facture EBP.

## Bloc 4 — TikTok et AutoDoc

- **TikTok** : aucune vente TikTok dans la base en septembre 2026, alors qu'il y en a 8 200 € TTC en août. Charger l'export « Toutes les commandes » du Seller Center : `Order ID`, `Order Status`, `Cancelation/Return Type`, `Seller SKU`, `Quantity`, `SKU Subtotal Before Discount`, `SKU Seller Discount`, `SKU Platform Discount`, `Original Shipping Fee`, `Shipping Fee Seller Discount`, `Order Refund Amount`, `Created Time`, `Paid Time`, `Shipped Time`, `Country`, `Recipient`. Table proposée : `compta_tiktok_commandes` (une ligne par article de commande).
- **AutoDoc** : un relevé tous les 10 jours (PDF). Moins prioritaire : 400 € par mois. Peut rester un dépôt manuel au début.

## Ce que fera le bouton une fois ces tables remplies

Pour le mois choisi, le board reprend les règles déjà validées avec Jérémy et le cabinet :
1. chaque facture garde ses écritures d'origine et va dans l'onglet de la famille de son client (`clients.segment`, via `ventes_pieces.num_commande` ou le code client EBP) ;
2. commandes de test ou annulées → onglet « Annulées » ; commandes remboursées sans avoir → onglet « Remboursées » ;
3. onglet « Avoirs » : miroir de chaque facture concernée (mêmes comptes, débit et crédit inversés, numéro `AV-` + numéro de facture), avec la qualification de l'encaissement d'après `id_transaction` et `type_paiement` ;
4. onglets « Contrôle avoirs », « Contrôles » (débit = crédit par onglet, total par compte) et « Lisez-moi ».

## Questions pour Robin

1. La collecte PrestaShop passe-t-elle par l'API, par la base MySQL ou par des fichiers ? Selon la réponse, le bloc 1 se prend soit dans le module d'export comptable, soit directement dans les tables de factures et de taxes.
2. Les noms et colonnes des tables ci-dessus te conviennent-ils ? Dès ton accord, la migration est écrite dans `supabase/migrations/` et poussée avant d'être appliquée (règle du dépôt).
3. Qui crée les tables : toi dans ton flux, ou la conversation de Jérémy ? À décider pour ne pas le faire en double.
