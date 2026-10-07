# Clôture mensuelle des achats — procédure

Pour qui : la personne qui tient la comptabilité de SHINE (aujourd'hui Jérémy). Elle se suit **sans IA**.
Claude peut faire les mêmes étapes plus vite : dans une conversation ouverte sur ce dépôt, taper `/cloture-achats 2026-10`.

Exercice comptable : du 1er octobre au 30 septembre. Le livre d'un mois est envoyé au cabinet après cette procédure.

## Ce qui tourne tout seul

| Quand | Quoi | Où regarder |
|---|---|---|
| Chaque minute | Une facture (PDF) déposée dans le Drive « Factures SHINE / 1 - A DEPOSER » est lue, rangée et renommée `date_compte_fournisseur_n°_HT_TTC.pdf` | « 2 - CLASSEES / exercice / mois / compte » ou « 3 - A VERIFIER » |
| Chaque nuit, 5 h 30 | Pour le mois précédent et le mois en cours : écritures (CSV pour le cabinet), journal (CSV) et **livre des achats Excel** | Dossier du mois dans « 2 - CLASSEES » |

Le rangeur ne devine jamais : ce qui n'est pas sûr part « à vérifier » avec la raison écrite (fournisseur inconnu, document annuel, doublon, devise, montants qui ne tombent pas juste…).
Il écarte seul ce qui n'est pas un achat SHINE (véhicules de Space Up, indemnités, avis d'impôt du propriétaire, valeur des titres-restaurant) et les factures déjà passées dans le grand livre.

## Pendant le mois

1. Déposer chaque facture d'achat (PDF) dans « 1 - A DEPOSER ». Un PDF par facture ; si une facture va avec un justificatif (mail, avis de paiement), les fusionner en un seul PDF.
2. Mettre le mot **litige** dans le nom du fichier pour une facture prise en charge pour un litige client (compte 61530000).

## Entre le 1er et le 5 du mois suivant

1. **Relevés bancaires** : exporter le mois en CSV (Crédit Agricole, CIC, PayPal) et l'export Pleo, les déposer dans le dossier prévu du Drive.
2. **Board Factures** (`factures.html`, onglet « à vérifier ») : traiter chaque facture.
   - Bon compte proposé → **Valider**.
   - Autre compte → choisir le compte, cocher **Retenir** si la règle vaut pour la suite (le rangeur ne redemandera plus).
   - Pas un achat de SHINE, doublon, proforma → **Écarter**.
   - Document annuel (assurance, honoraires annuels, échéancier) : passer la part du mois, noter le reste en charge constatée d'avance.
   - Facture en devise : montant en euros pris sur le relevé bancaire, au mois du paiement.
3. **Livre du mois** (Excel dans le dossier du mois, refait chaque nuit) : vérifier la première page.
   - Plus aucune facture « à vérifier » (sinon le livre est incomplet).
   - Onglet « À vérifier et écartées » : chaque écart a une raison qui tient.
   - Onglet « Charges constatées d'avance » : les loyers et abonnements à cheval sur le mois suivant.
4. **Contrôles de bon sens** :
   - Factures habituelles présentes : loyers (SCI CMD, Boutique du Store…), leasings (Volkswagen, Capitole, Mutualease, La Banque Postale), Space Up, abonnements (Shopify, Channable, Shippingbo…), assurances, énergie.
   - Chaque gros paiement du relevé a sa facture ; chaque facture du livre a son paiement (ou est encore due).
   - Total du mois comparable aux mois précédents ; un écart de plus de 20 % s'explique.
5. **Envoi au cabinet** : le livre Excel et le CSV des écritures du mois.
6. **Marquer le mois comme envoyé** : charger le livre du mois dans la base (table `factures_grand_livre`). Les factures de ce mois qui arriveraient plus tard seront reconnues (déjà passées) ou rattachées au mois suivant.

## Règles comptables retenues (détail : `outils/factures/regles-livre-2026-09.mjs`)

- Montant en charge : HT ; plus la TVA non déductible pour les voitures de tourisme (loyers Volkswagen, réparations) ; 80 % de TVA déductible sur le carburant ; TTC pour les factures sans TVA (assurances) ; autoliquidation pour Meta, TikTok, Shopify, Channable, Guala, Lautus (TVA indiquée, non payée au fournisseur).
- Capitole : 308 et Golf = voitures de société (HT). Ateca GZ-505-XD et Cupra GT479WH = véhicules de Space Up, pas chez SHINE.
- Nexus : Univar, Vidara, Quimidroga, Interchimie, Stockmeier, Keyser → 60110000 « MP chimie pour Nexus » ; Labbox, Labomat, Mecalux → 60130000 « Aménagement pour Nexus » ; RS Développement : factures marquées Nexus et points éclair → MP chimie pour Nexus, le reste en 60400000.
- Plast'Embal : film → 60263000 « Film + BTB » ; calage et scotch → « Calage et scotch + BTC ».
- Titres-restaurant (Edenred) : seule la commission est un achat (62700000) ; la valeur des titres passe en paie (part SHINE 60 %).
- RC Pro (Gan) : 680,83 € par mois d'octobre 2026 à septembre 2027.
- Indemnité d'assurance : un produit (ventes, « Hors ventes »), pas un achat.

## En cas de doute

Ne pas forcer un compte : laisser « à vérifier » et noter la question. Une décision prise devient une règle (case **Retenir** dans le board, ou ajout dans `regles-livre-*.mjs`), pour que la même question ne revienne pas.
