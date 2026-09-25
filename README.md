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

## Chiffres de contrôle (25/09/2026, après retrait des doublons de la bascule du site pro)

| Exercice | CA HT total | dont CA produits | dont pros |
|---|---|---|---|
| 2024-2025 | 4 123 165 € | 4 049 907 € | 361 527 € |
| 2025-2026 | 4 734 925 € | 4 702 320 € | 333 498 € |

Ces totaux ne doivent pas bouger quand on éclate des packs ou qu'on détaille EBP.
Doublons de la bascule du site pro : voir `supabase/migrations/20260925_doublons_bascule.sql`.

## Data Center (board particuliers, marketing)

- `data-center.html` : le board Data Center (même connexion que le board Ventes). On passe d'un board à l'autre par le bouton en grille sous les onglets du menu latéral.
- Périmètre : **particuliers uniquement** (PrestaShop shine-group.fr, groupes Client, Invité, Visiteur via `groupes_segments`). PrestaShop est la source de vérité des commandes et du CA.
- Accès : colonne `acces_board.boards` (ex. `{"data_center":"lecteur"}`) ; un `admin` global voit tout. Seuls les admins du Data Center changent le statut des préconisations.
- Données : schéma Supabase `marketing` (non exposé à l'API), lu uniquement par `dc_donnees(du, au)` ; le comparateur (N-1, période précédente, dates choisies) appelle la fonction deux fois.
- Chargement : Edge Function `supabase/functions/dc-ingestion` (Windsor → Supabase), chaque nuit à 04:30 (heure de Paris) sur les 30 derniers jours, puis contrôles automatiques (`dc_controler`). Secret `CLE_API_WINDSOR` dans Supabase, jamais dans le code.
- Règle GA4 : uniquement des dimensions `session_*` (jamais `campaign` ni `source_medium` sans préfixe, qui sont des champs d'attribution des conversions et faussent les sessions).
- Migrations appliquées dans Supabase : `data_center_01` à `data_center_08` (à exporter dans `supabase/migrations/` avec `supabase db pull`).
