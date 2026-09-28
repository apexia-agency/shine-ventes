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
