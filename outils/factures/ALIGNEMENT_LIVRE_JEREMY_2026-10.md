# Rangeur de factures : écarts avec la ventilation de Jérémy (05/10/2026, complété le 07/10/2026)

Référence : le livre ventilé par Jérémy et envoyé au comptable (`Grand compte COMPTA (3).xlsx`, onglet ALL LIVRES, octobre 2025 à août 2026),
et le livre des achats de septembre 2026 fait à partir des 85 PDF (`SHINE_livre_achats_600-620_2026-09_v12.xlsx`, **validé par Jérémy le 07/10/2026**).
Rien n'est encore modifié dans le rangeur : cette liste est la base des changements à faire, après accord de Robin.
Projet repris par Jérémy et Claude le 05/10/2026 ; Robin est prévenu avant toute modification des règles.

## 1. Sous-rubriques « Créer nouveau compte » absentes du plan de comptes du rangeur (`factures_comptes`)

| Compte parent | Sous-rubrique | Fournisseurs dans le livre |
|---|---|---|
| 60110000 | MP chimie pour Nexus | Univar, Vidara, Interchimie, Stockmeier, Keyser, Quimidroga, RS Développement |
| 60130000 | MP chimie intra pour Nexus | Spiess, Chemipol |
| 60130000 | MP contenants et fermants intra | flacons plastiques |
| 60130000 | Aménagement pour Nexus | Mecalux, Gram, Labomat, Brico Dépôt (travaux labo), ACM |
| 60263000 | Calage et scotch + BTC | Plast'Embal (calage) |
| 60263000 | Film + BTB | Plast'Embal (film) |
| 60711000 | PF chimie import | Qingdao |
| 61140000 | Prest. AE. SEA | Meemo |
| 61142000 | Compte presta pour Nexus | AG Conseils, MGA R&D |
| 61351600 | Frais de dossier et gestion des financements | Solufinance |
| 61610000 | Assur. flotte véhicules | (vide) |
| 62210000 | Médecine du travail | (vide) |
| 62380000 | Sponsoring | Team Jason Banet |
| 62380000 | Transport sur achats import | AMM, Qingdao (fret) |

## 2. Règles de fournisseurs à revoir (`factures_fournisseurs`)

- **Achats pour Nexus** (confirmé par Jérémy le 05/10/2026) : Univar, Vidara, Quimidroga, Interchimie, Stockmeier et Keyser achètent **toujours** pour Nexus → « 60110000 / MP chimie pour Nexus » ; Spiess et Chemipol → « 60130000 / MP chimie intra pour Nexus ». Règle par fournisseur, pas besoin de signal sur la facture. RS Développement : factures marquées Nexus et « points éclair » → « MP chimie pour Nexus », les autres → 60400000 (confirmé par Jérémy le 07/10/2026).
- **Plast'Embal** : un seul compte (60263000) ; à éclater ligne par ligne entre calage (BTC) et film (BTB).
- **Napack** : rangé en 62350000 PLV dans le rangeur, alors que le livre le met en 60112000 MP étiquetage (68 000 € sur l'exercice).
- **Volkswagen Bank, Capitole Finance** : un compte par véhicule (plaque → compte) ; TVA non déductible des voitures de tourisme (loyers
  Volkswagen TTC). Capitole 308 et Golf : voitures de société, loyers HT (Jérémy, 07/10/2026). Seat Ateca GZ-505-XD et Cupra GT479WH : véhicules de
  SPACE UP, loyers et carburant **hors SHINE** (Jérémy, 07/10/2026).
- **Sans compte aujourd'hui** (statut « à valider ») : Plastic Billat (→ 60711200), Prodhynet (→ 60110000, transport 62410000), Spiess, Chemipol, Mecalux,
  Labomat, Axess, Cedec, Meemo, AMM, Solufinance, Team Jason Banet, SCI CMD / Immo Comunica (loyer Durafour 61327000), Qingdao Tonyin.
- **TVA** : TikTok, Shopify, Channable sont en régime « FR » dans le rangeur ; leurs factures sont émises depuis le Royaume-Uni, l'Irlande et les Pays-Bas
  (autoliquidation). Iveco (utilitaire) est marqué TVA non déductible ; La Banque Postale aussi, alors que le cabinet passe la visseuse HT.
- **Gan** : 61610000 dans le rangeur, 61611000 (multirisque) dans le livre ; l'échéancier RC Pro relève de 61615000.

## 3. Contrôles à ajouter, vus sur les factures de septembre

- Facture datée d'un autre mois (juillet, août) : vérifier qu'elle n'est pas déjà saisie avant de la ranger.
- Document qui n'est pas une facture : ticket de caisse, avis de taxe foncière, échéancier, indemnité d'assurance.
- Facture adressée à une autre société du groupe (SPACE UP, NEXUS) ou à une ancienne adresse.
- Facture en devise sans taux (Tonyin en dollars) : montant en euros à prendre sur le relevé.
- Loyers payés d'avance (charge constatée d'avance à la clôture).

## 4. Litiges clients (Jérémy, 05/10/2026)

- Une facture de tiers que SHINE prend en charge pour régler un litige client (ex. L.A. Autoclean pour M. Boireau, garages et carrosseries
  Porsche, ADS Jantes, Yucel, Auto Vap, Ambo, SCO) va en **61530000 « Entretien litige client »**, compte du livre de Jérémy. Le rangeur ne peut pas
  le deviner : en interne, le mot « litige » sera mis dans le libellé ou le nom du fichier, et la règle le reconnaît.
- Attention : dans le livre, 61530000 porte deux comptes (« Entretien litige client » et « Entretien utilitaire ») ; un des deux doit changer de numéro.

## 5. Décisions du 07/10/2026 (livre de septembre)

- **RC Pro (Gan)** : payée par mois à partir d'octobre : 680,83 € par mois d'octobre 2026 à septembre 2027, la même facture rattachée chaque mois. Rien en septembre.
- **Indemnité d'assurance** (Gan, grêle) : pas un achat ; va dans l'export des ventes, onglet « Hors ventes » (791000), pas dans le chiffre d'affaires.
- **Titres-restaurant (Edenred)** : seule la commission en 62700000. La valeur des titres va dans la paie : part SHINE 60 % en 6475, part des salariés 40 % retenue sur la paie.
- **Tonyin (Chine, dollars)** : au mois du virement, montant en euros pris sur le relevé ; produits en 60121000 / 60712000, fret en « 62380000 / Transport sur achats import ».
- **Factures en double ou en plusieurs documents** (ex. La Boutique du Store) : un seul PDF par règlement (facture, justificatif, mail), compté une fois.
- **Avoir ou trop-payé déduit d'une facture** : passé au crédit du compte d'origine (loyer de juin de la Boutique du Store, 300 € HT).
- **Cylium** : contrat arrêté en juillet 2026, plus de facture attendue.
- **Charges constatées d'avance** : pour toute facture dont la période dépasse la fin du mois de clôture, calculer la part après la clôture au prorata des jours
  (loyers Banque Postale, Capitole, Mutualease ; abonnements Channable, Shippingbo, Shopify).
