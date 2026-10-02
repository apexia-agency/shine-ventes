# Note pour Robin : trieur de mails de Jérémy (02/10/2026)

Jérémy met en place son propre tri de mails. **Rien de ton travail n'est modifié** : ni tes flux n8n
(« Boîte pro — Tri, alertes et réponses suggérées », « FRIDAY Tools »…), ni l'app FRIDAY, ni sa base.

## Ce qui est ajouté

- Dans n8n (ton instance `robinshine`) : un dossier « JEREMY » et un flux « Boîte Jérémy · tri et brouillons ».
  Il utilise la connexion existante « Supabase SHINE ventes » (lecture seule de la connexion, rien n'y est changé)
  et une connexion Gmail propre à Jérémy.
- Dans la base du board : tables `mails_regles` et `mails_traites`, fonction `mail_contexte`, fonction Edge `trier-mail`.
  Détail dans le `README.md`, partie « Trieur de mails de Jérémy ».

Merci de ne pas modifier ce flux ni ce dossier ; de son côté, la conversation Claude de Jérémy ne touche pas aux tiens.

## Deux points vus en lisant tes flux (à toi de décider)

1. **Clés écrites en clair dans les nœuds.** Dans « Boîte pro — Tri, alertes et réponses suggérées » et « FRIDAY Tools »,
   les secrets de l'app FRIDAY (envoi de mail, archivage, boîte de réception, outils) sont dans le corps des requêtes
   ou dans une condition. Toute personne qui ouvre n8n peut les lire, et ils apparaissent dans les exports.
   À faire : les déplacer dans des connexions n8n (comme « Supabase agent-run ») et les renouveler.
2. **Grille tarifaire recopiée dans la consigne** de « Analyse IA » : elle deviendra fausse au premier changement de prix.

## Plus tard, si tu veux

La fonction `trier-mail` sait retrouver un client par l'empreinte de son adresse et donner ses dernières commandes
et son suivi de colis. Si ça t'intéresse pour ta boîte, on en parle avec Jérémy avant de brancher quoi que ce soit.
