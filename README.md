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
