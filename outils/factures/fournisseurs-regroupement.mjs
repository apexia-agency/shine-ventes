// Nettoyage de l'onglet « Fournisseurs » de regles.xlsx (V5 de Jérémy, 29/09/2026).
// Les 349 clés sont des mots extraits des libellés du grand livre, pas des raisons sociales.
// Ce fichier dit, clé par clé, à quel fournisseur réel elle appartient, ou pourquoi elle est écartée.
// Usage : node fournisseurs-regroupement.mjs regles.json sortie.json   (regles.json = regles.xlsx converti)
// Le résultat n'est qu'une PROPOSITION : les groupes douteux vont dans « À valider » du board.
import { readFileSync, writeFileSync } from 'node:fs';

// Fournisseur réel → clés du grand livre qui le désignent.  note : précision pour le valideur.
const GROUPES = [
  ['DPD France', ['DPD']],
  ['Colissimo (La Poste)', ['COLISSIMO', 'COLISSIMO SAPCE']],
  ['Meta (Facebook, Instagram)', ['META', 'FACEBK FDE PJR', 'FACEBK LECBD']],
  ['Google Ads', ['GOOGLE-ADS', 'GOOGLE']],
  ['Space Up', ['SPACEUP', 'SPACE', 'SPACE PRESTATIONS GESTION', 'SPACE REMUNERATION PRESIDENCE'], 'Holding : prestation de gestion et rémunération de la présidence sur la même facture'],
  ['Nexus Lab', ['NEXUS']],
  ['CREE', ['CREE']],
  ['Lautus Equipment (De Witte)', ['LAUTUS EQUIPMENT', 'LAUTUS EQUIPMENT SOUFFLEUR']],
  ['Hebei Loupai', ['HEBEI LOUPAI', 'HEBEI LOUPAI ACOMPTE']],
  ['Guala Dispensing', ['GUALA DISPENSING TETE', 'GUALA DISPENSING']],
  ['Caps Packaging', ['CAPS PACKAGING', 'CAPS']],
  ['4B Distrib', ['DISTRIB', 'DISTRIB MICROFIBRE']],
  ['Découpe Stéphanoise', ['DECOUPE STEPHANOISE']],
  ['XPO Logistics', ['XPO LOGISTICS']],
  ['Shenzhen Kasi Teng', ['SHENZHEN KASI TENG', 'SHENZHEN ACOMPTE']],
  ["Plast'Embal", ['PLAST EMBAL', 'PLAST EMBAL FORFAIT']],
  ['Cylium', ['CYLIUM DEV', 'CYLIUM']],
  ['Tanguy FPV', ['TANGUY FPV', 'TANGUY FPV SHOOTING']],
  ['Fidel Fillaud', ['FIDEL FILLAUD']],
  ['Aérochem', ['AEROCHEM']],
  ['Cabinet comptable (RG Conseils ?)', ['CONSEILS'], 'Clé « CONSEILS » seule : raison sociale exacte à confirmer'],
  ['Imprimeur catalogues (?)', ['CATALOGUES IMPRIMES BROCHURES'], 'Libellé de nature, pas un fournisseur : lequel ?'],
  ['Lixxbail', ['LIXXBAIL', 'LIXXBAIL SHINE']],
  ['Dachser', ['DACHSER']],
  ['Citeo', ['CITEO']],
  ['Chadli (loyer Marly)', ['CHADLI', 'CAP LOYER CHADLI', 'CHADLI LOYER']],
  ['Fatton', ['FATTON']],
  ['Meemo', ['MEEMO']],
  ['Muriel Chassagneux', ['MURIEL CHASSAGNEUX']],
  ['CHT France', ['CHT FRANCE']],
  ['Leclerc (réseau)', ['LECLERC FRAIS GESTION', 'LECLERC PUB', 'LECLERC PRESTA PUB', 'LECLERC LOC ESPACE', 'LECLERC LOCATION ESPACE', 'LECLERC'], 'Commissions, publicité et location d’espace : plusieurs comptes selon la facture'],
  ['Carmona Liliane (loyer stock)', ['CARMONA LILIANE LOYER']],
  ['Univar', ['UNIVAR']],
  ['DLC Junior (location Andrézieux)', ['DLC JUNIOR']],
  ['Interchimie', ['INTERCHIMIE']],
  ['Ulys (péages)', ['ULYS']],
  ['Rubberex', ['RUBBEREX GANTS']],
  ['Pixartprint', ['PIXARTPRINT PRESENTOIR']],
  ['Spiess', ['SPIESS']],
  ['BPCE Lease', ['BPCE LEASE', 'BPCE LEASE SHINE']],
  ['Engie', ['ENGIE']],
  ['TikTok', ['TIKTOK']],
  ['Omnisend', ['OMNISEND', 'OMNISEND SUBSCRIPTIO']],
  ['Aérolub', ['AEROLUB']],
  ['Jiangsu Lanceurs', ['JIANGSU LANCEURS MOUSSE']],
  ['Véra Chimie', ['VERA CHIMIE PRODUCTION']],
  ['Entretien des locaux (« PLAN » ?)', ['PLAN'], 'Clé « PLAN » seule, 11 factures d’entretien immobilier : raison sociale ?'],
  ['La Banque Postale (leasing visseuse)', ['BANQUE POSTALE']],
  ['La Poste (frais postaux)', ['POSTE'], 'La Banque Postale = leasing visseuse, La Poste = frais postaux : deux fournisseurs'],
  ['Ambrosol', ['AMBRO SOL NETTOYANTS', 'AMBRO', 'AMBROSOL NETTOYANT']],
  ['Dorothée Lemaire', ['DOROTHEE LEMAIRE', 'LEMAIRE DOROTHEE']],
  ['Facilecomm', ['FACILECOMM FORFAIT ABONNEMENT', 'FACILECOMM', 'FACILE COMM', 'FACILECOMM ABONNEMENT MENSUEL']],
  ['Vidara', ['VIDARA']],
  ['GIT (loyer rue Auriol)', ['GIT', 'GIT LOYER', 'GIT LOYER FAC', 'GIT DEGRADATION LOT', 'GIT DEGRADATIONS LOT', 'GIT REEDITIONS CHARGES'], 'Loyer, charges locatives et dégradations : plusieurs comptes selon la facture'],
  ['Communik', ['COMUNIK AGENCE', 'COMMUNIK']],
  ['Sermaco', ['SERMACO', 'SERMACO FILET CARTON']],
  ['Cindy Cledere', ['CLEDERE CINDY', 'CLEDER CINDY']],
  ['OVH Cloud', ['OVH CLOUD']],
  ['Garage Peyroche', ['GARAGE PEYROCHE']],
  ['Bamapro', ['BAMAPRO RENCONTRE PARTENAIRE']],
  ['Plastic Billat', ['PLASTIC BILLAT POIGNEE', 'PLASTIC BILLAT', 'ACCESSOIRES BILLAT', 'PLASTIQUE BILLAT'], 'Accessoires revendus (60711200) sauf une facture en étiquetage (60112000)'],
  ['Seko', ['SEKO']],
  ['Flashcar', ['FLASHCAR']],
  ['Orange', ['ORANGE']],
  ['Padre Detailing', ['PADRE DETAILING']],
  ['TNM (VPK) Les Échets', ['TNM LES ECHETS']],
  ['Axeptio', ['AXEPTIO']],
  ['Volkswagen Bank', ['VOLKSWAGEN', 'VOLKSWAGEN CUPRA'], 'Un compte par véhicule : l’immatriculation sur la facture décide'],
  ['OQEMA', ['OQEMA', 'OQUEMA ALCOOL ISOPROPYLIQUE']],
  ['EDF', ['EDF GAZ', 'EDF', 'EDF FAC']],
  ['Keyser', ['KEYSER']],
  ['Forget About', ['FORGET ABOUT', 'FORGET ABOUT INFOGERANCE']],
  ['Eclipse (présentoir moto)', ['ECLIPSE PRESENTOIRE MOTO']],
  ['Team Jason Banet (sponsoring)', ['TEAM JASON BANET']],
  ['Saccof Packaging', ['SACCOF PACKAGING']],
  ['Mercedes-Benz', ['MERCEDES BENZ FRANCE', 'MERCEDES ENTRETIENS', 'MERCEDES'], 'Location (TVA non déductible) ou entretien : deux comptes'],
  ['SETM Eau', ['SETM EAU']],
  ['Ludovic Bouchet', ['BOUCHET LUDOVIC FAC', 'BOUCHET LUDOVIC']],
  ['Sébastien Lehmann', ['SEBASTIEN LEHMANN MANQUE']],
  ['Franfinance', ['FRANFINANCE LOCATION', 'FRANFINANCE LOCATION SHINE']],
  ['AMM (transport import)', ['AMM']],
  ['Azelis', ['AZELIS']],
  ['Quimidroga', ['QUIMIDROGA']],
  ['Klaviyo', ['KLAVIYO']],
  ['Mutualease', ['MUTUALEASE', 'MUTUALEASE GERBEUR TOYOTA', 'MUTUALEASE LOC GEBEUR', 'MUTUALEASE FORFAIT ANNUEL']],
  ['CJA Avocats', ['CJA AVOCATS AUGM', 'CJA AVOCATS']],
  ['Free', ['FREE']],
  ['Bio Sorelia', ['BIO SORELIA SHAMPOING']],
  ['Iveco', ['IVECO']],
  ['Stockmeier', ['STOCKMEIER']],
  ['Sequoia', ['SEQUOIA', 'SEQUOIA PALETTE LEGERE']],
  ['Point Forum', ['POINT FORUM']],
  ['Capitole Finance', ['CAPITOLE', 'CAPITOLE CHARIOT'], 'Le n° de contrat décide : 100093243 Golf, 100093237 Peugeot 308, 100084032 Iveco, chariot'],
  ['Banque Populaire (leasing compresseur)', ['BANQUE POPULAIRE RIVES']],
  ['Boutique Store (loyer Veauche)', ['BOUTIQUE STORE', 'BOUTIQUE STORE LOYER']],
  ['Kiliba', ['KILIBA']],
  ['Shopify', ['SHOPIFY']],
  ['Objet Rama', ['OBJET RAMA STYLO', 'OBJET RAMA'], 'Goodies (62350000) ou cadeaux clients (62340000)'],
  ['Agir Services', ['AGIR SERVICES']],
  ['Ipsilon', ['IPSILON']],
  ['Lamatex', ['LAMATEX']],
  ['Anthropic (Claude)', ['ANTHROPIC CLAUDE', 'CLAUDE']],
  ['Channable', ['CHANNABLE']],
  ['Brico Dépôt', ['BRICO DEPOT']],
  ['Creditsafe', ['CREDIT SAFE']],
  ['Amio', ['AMIO']],
  ['Brenntag', ['BRENNTAG']],
  ['Lucky Imprimerie', ['LUCKY IMPRIMERIE', 'LUCKY', 'LUCKY IMPRI', 'LUCKY IMPRIMERIE AMALGAME', 'LUCKY IMPRIMERIE BLISTERS'], 'Emballage produit (60261000) ou PLV (62350000) selon l’article'],
  ['ALVS (vêtements de travail)', ['ALVS HABIT TRAVAIL', 'ALVS TENUES']],
  ['Quatre-Vingt-Neuf (garage)', ['QUATTRE VINGT NEUF']],
  ['Bureau Vallée', ['BUREAU VALLEE', 'BUREAU']],
  ['Ambo Carrosserie', ['AMBO CARROSSERIE']],
  ['Rochette (rédaction bail)', ['ROCHETTE LOCATION REDACTION']],
  ['EcoMundo', ['ECO MUNDO LICENCE', 'ECO MUNDO']],
  ['AED (sécurité incendie)', ['AED', 'AED INCENDIE']],
  ['Flexible Pack', ['FLEXIBLE PACK']],
  ['Cleaneo (climatisation)', ['CLEANEO CLIM']],
  ['Siemens Lease', ['SIEMENS LEASE SERVICES']],
  ['CDS', ['CDS', 'CDS SECTEUR', 'CDS JOINT IMPULSEUR']],
  ['PrestaShop', ['PRESTASHOP']],
  ['Carrefour Location', ['CARREFOUR LOC VEHICULE']],
  ['Field Food', ['FIELD FOOD']],
  ['Viasso', ['VIASSO ROYALTIES']],
  ['Brico Leclerc', ['BRICO LECLERC ASPIRATEUR']],
  ['Saur (eau)', ['SAUR']],
  ['Sud Travail (médecine du travail)', ['SUD TRAVAIL']],
  ['Infini', ['INFINI']],
  ['Oélie (eau)', ['OELIE EAU']],
  ['Mobility LED', ['MOBILITY LED']],
  ['Fluidtech', ['FLUIDTECH']],
  ['Unal Palettes', ['UNAL PALETTE', 'UNAL']],
  ['Nexecur', ['NEXECUR PROTECTION', 'NEXECUR']],
  ['Vetassur', ['VETASSUR CHAUSSURE SECU']],
  ['SCO Carrosserie', ['SCO CARROSSERIE']],
  ['Carrosserie Yucel', ['CAROSSERIE YUCEL POLISSAGE']],
  ['Solufinance', ['SOLUFINANCE', 'SOLUFINANCE SERVICE PROT']],
  ['Auto Vap', ['AUTO VAP ESP']],
  ['AMS Pare-Brise', ['AMS PARE BRISE']],
  ['Autodoc', ['AUTODOC', 'AUTO DOC', 'AUTO DOC COMMISSION'], 'Pièces auto (61520000) ou commissions CB (62780000) : deux lignes du grand livre se contredisent'],
  ['GMJ Phoenix', ['GMJ PHOENIX']],
  ['SFR', ['SFR']],
  ['ACM Plomberie', ['ACM PLOMBERIE FUITE']],
  ['Décap Auto', ['DECAP AUTO']],
  ['Rent a Car', ['RENT CAR']],
  ['Norauto', ['NORAUTO', 'NORAUTO SPACE']],
  ['Centre de médiation de la consommation', ['CTRE MEDIAT CONSO']],
  ['Legal & Cie', ['LEGAL CIE']],
  ['Pasta Veloce', ['PASTA VELOCE']],
  ['Auchan (carburant)', ['AUCHAN CARB', 'AUCHAN ESSENCE']],
  ['Fulli (carburant)', ['FULLI ESSENCE']],
  ['TotalEnergies', ['TOTAL']],
  ['Carrefour Market (carburant)', ['DAC CARREFOUR MARKET']],
  ['Intermarché (carburant) ?', ['INTER'], 'Clé « INTER » seule : Intermarché ?'],
  ['Station de Veauche ?', ['VEAUCH'], 'Clé « VEAUCH » seule : quelle station ?'],
  ['Gan Assurances', ['GAN ASS MULTIRISQUE', 'GAN ASS ENC'], 'Le contrat décide : flotte de véhicules ou assurance générale'],
  ['Albingia (RC pro)', ['ALBINGIA', 'SHINE ALBINGIA']],
  ['Apave', ['APAVE', 'APAVE VERIF LEBAGE']],
  ['Innova Pesage', ['INNOVA', 'INNOVA PESAGE VERIF'], 'Petit matériel (60630000) ou vérification de balance (61552000)'],
  ['DHL (douane)', ['DHL DOUANE']],
  ['AliExpress', ['ALIEXPRESS CARTE PROXIMITE', 'ALIEXPRESS PATE THERMIQUE']],
  ['SGC Feurs', ['SGC FEURS']],
  ['BNP Paribas Lease', ['BNP LEAUSE TRIEUSE', 'BNPLEASE LOC DIVERSE']],
  ['UPS', ['UPS']],
  ['Napack', ['NAPACK', 'NAPACK AKYLUX', 'NAPACK MORCEAU PVC'], 'Étiquettes par défaut (60112000), PLV si c’est un support de mise en avant (62350000)'],
  ['Infogreffe', ['INFOGREFFE', 'INFFOGREFFE']],
  ['SCI CMD Immobilier', ['SCI CMD IMMOBILIER']],
  ['Prodhynet', ['PRODHYNET']],
  ['Qingdao', ['QINGDAO', 'QINGDAO ACOMPTE']],
  ['Qingdao Tonyin', ['QINGDAO TONYIN', 'QINGDAO TONYIN INDU'], 'Une ligne classée en « déchets et recyclage » (10 910 €) : sûrement une erreur de saisie'],
  ['Qingdao Sacs', ['QINGDAO SACS']],
  ['Scholl Concepts', ['SCHOLL']],
  ['MTM', ['MTM']],
  ['Laumacom', ['LAUMACOM']],
  ['Leroy Merlin', ['LEROY MERLIN']],
  ['Amazon', ['AMAZON']],
  ['Chimie Conseil', ['CHIMIE CONSEIL']],
  ['Labomat', ['LABOMAT VISCOSIMETRE DESSICCATEUR']],
  ['Mecalux', ['MECALUX']],
  ['Cedec', ['CEDEC DISJONTEUR']],
  ['Axess', ['AXESS AGITATEUR', 'AXESS']],
  ['Chemipol', ['CHEMIPOL']],
];

// Clés trop vagues pour reconnaître un fournisseur : la raison sociale est à retrouver
const VAGUES = ['SOLUTIONS', 'POINT', 'DEV', 'DEVELOPPEMENT', 'DIVERS', 'IDEE', 'GRAM', 'GRAM BALANCE', 'MGA', 'BTC', 'JANTES',
  'SYSTEME PERF', 'CONSEILS PRESTA', 'PREST LOGISTIQUE', 'MANUTENTION SERVICE', 'AUDIT ACCOMPAGNEMENT', 'DOSAGE SUBSTANCE',
  'INSTITUT FICHE SECU', 'FLACONS PLASTIQUES', 'MATERIEL BUREAU INFORMATIQUE', 'MON AUTO ENTREPRISE', 'ACM CAISSON',
  'BRICO DEPOT TRAVAUX', 'ADS JANTES DEVIS', 'PORSCHE'];

// Lignes du grand livre qui ne viennent pas d'une facture fournisseur : jamais de règle pour elles
const ECARTEES = {
  'écriture d’inventaire (variation de stock)': ['STOCK PRODUITS FINIS', 'STOCK MATIERES CONSOMMABLES', 'STOCKS MER', 'STOCKS MERS', 'STOCKS'],
  'correction comptable (doublon, annulation, charge constatée d’avance)': ['GOOGLE DOUBLON', 'GIT DOUBLON', 'PLAN DOUBLON', 'SERMACO DOUBLON',
    'BRICOMARCHE DOUBLON', 'CASTORAMA DOUBLON', 'FIGMA DOUBLON', 'PAYPAL ANULE', 'ANNULATION PAYPAL', 'LAUTUS EQUIPMENT ANNULATION',
    'PLAST EMBAL ANNULE', 'BETON ANNUL', 'CCA LIXXBAIL', 'CCA FACILECOM', 'CCA BPCE LEASE', 'CHARGES PERIODIQUES CONSTATEES',
    'VOLKSWAGEN ECART CONTRAT', 'POINT SOLDE FACT', 'JUST RAMBE', 'LECLERC REMISE RFA'],
  'frais bancaires ou assurance d’emprunt, lus sur le relevé (hors factures)': ['SOLDE PAYPAL', 'COMM TRANSFERT', 'COMM CHANGE TRANSFERT',
    'COMMISSION VENTE DISTANCE', 'COMM TRANSFERT FRAIS', 'COMM TRANSFERT PRE', 'COMCB TPE', 'OFFRE COMPTE COMPOSER', 'COMMIS PRET',
    'COM CARTE', 'FACT SGT DONT', 'FACT SGC', 'INTERET FRAIS', 'ABONNEMENT VENTE DISTANCE', 'PREL EURO INFORMATION', 'FRAIS GARANTIE',
    'MONETICO', 'FRAIS CARTE HORS', 'COMMISSION INTERVENTION', 'INT RETS BITEURS', 'COM', 'BPIFRANCE', 'SAISIE ADMINISTRATIVE',
    'ASSU CAAE PRET', 'BPIFRANCE ASSURANCE DECES'],
  'dépense au nom de Space Up (contrôle 9 : facture au nom d’une autre société)': ['COLISSIMO SPACE', 'POSTE SPACE'],
  'don, pas une facture': ['DON POMPIER'],
};

const [, , entree, sortie] = process.argv;
const R = JSON.parse(readFileSync(entree, 'utf8'));
const [ent, ...rows] = R['Fournisseurs'];
const col = n => ent.indexOf(n);
const lignes = new Map(rows.filter(r => r[0]).map(r => [String(r[0]).trim(), r]));
const eclater = new Set(R['Fournisseurs à éclater'].slice(1).map(r => r[0]));

const vu = new Map();
const marquer = (cle, ou) => {
  if (!lignes.has(cle)) throw new Error(`clé inconnue : ${cle} (${ou})`);
  if (vu.has(cle)) throw new Error(`clé en double : ${cle} (${vu.get(cle)} et ${ou})`);
  vu.set(cle, ou);
};
GROUPES.forEach(([nom, cles]) => cles.forEach(c => marquer(c, nom)));
VAGUES.forEach(c => marquer(c, 'vague'));
Object.entries(ECARTEES).forEach(([m, cles]) => cles.forEach(c => marquer(c, 'écartée')));
const oublies = [...lignes.keys()].filter(c => !vu.has(c));
if (oublies.length) throw new Error('clés non traitées : ' + oublies.join(', '));

// Montant de l'exercice, lu dans la note : « … | 12 345 EUR sur l'exercice » ou « >> 60110000 185038 EUR / 62410000 2620 EUR »
const montant = r => {
  const note = String(r[col('Note')] || '');
  const m = /(-?[\d ]+) EUR sur l'exercice/.exec(note);
  if (m) return +m[1].replace(/\s/g, '');
  return [...(note.split('>>')[1] || '').matchAll(/(-?\d+) EUR/g)].reduce((t, x) => t + +x[1], 0);
};
const territoire = regime => ({ FR: 'FR', AUTOLIQ_UE_BIENS: 'INTRA', AUTOLIQ_UE_SERVICES: 'INTRA', AUTOLIQ_IMPORT: 'IMPORT', SANS_TVA: 'FR' }[regime] || null);
const nature = r => { const p = String(r[col('Note')] || '').split('|').map(s => s.trim()); return /^[A-Z_]+$/.test(p[1] || '') ? p[1] : null; };
const uniques = a => [...new Set(a.filter(v => v != null && v !== ''))];

const fournisseurs = GROUPES.map(([nom, cles, note]) => {
  const rs = cles.map(c => lignes.get(c));
  const comptes = uniques(rs.map(r => String(r[col('Compte')] || '').trim()));
  const regimes = uniques(rs.map(r => r[col('Régime TVA')]));
  const familles = uniques(rs.map(r => r[col('Famille')]));
  const deductible = uniques(rs.map(r => r[col('TVA déductible')]));
  const natures = uniques(rs.map(nature));
  const aArbitrer = rs.some(r => r[col('Statut')] !== 'OK');
  const hors = rs.some(r => r[col('Statut')] === 'HORS PERIMETRE');
  const aCreer = comptes.some(c => /cr[ée]/i.test(c));
  const motifs = [];
  if (hors) motifs.push('hors périmètre SHINE');
  if (comptes.length > 1) motifs.push('plusieurs comptes : ' + comptes.join(', '));
  if (regimes.length > 1) motifs.push('régimes de TVA différents : ' + regimes.join(', '));
  if (deductible.length > 1) motifs.push('TVA déductible différente : ' + deductible.join(', '));
  if (aCreer) motifs.push('compte à créer par le comptable');
  if (aArbitrer && !motifs.length) motifs.push('marqué « à arbitrer » par Jérémy');
  if (/\?/.test(nom)) motifs.push('raison sociale à confirmer');
  return {
    nom, alias: cles, note: note || null,
    compte: comptes.length === 1 && !aCreer ? comptes[0] : null, comptes,
    famille: familles.length === 1 ? familles[0] : null,
    regime_tva: regimes.length === 1 ? regimes[0] : null,
    territoire: regimes.length === 1 ? territoire(regimes[0]) : null,
    nature: natures.length === 1 ? natures[0] : null,
    tva_deductible: deductible.length === 1 ? String(deductible[0]) : null,
    montant: rs.reduce((s, r) => s + montant(r), 0),
    // Les 6 fournisseurs multi-natures ont leur règle (dictionnaire produit) : ce n'est pas une question
    statut: hors ? 'hors' : cles.some(c => eclater.has(c)) ? 'eclater' : motifs.length ? 'a_valider' : 'ok', motifs,
    notes_jeremy: rs.map(r => `${r[0]} : ${String(r[col('Note')] || '').replace(/\s+/g, ' ')}`),
  };
});
const vagues = VAGUES.map(c => ({ cle: c, compte: String(lignes.get(c)[col('Compte')] || ''), montant: montant(lignes.get(c)), note: String(lignes.get(c)[col('Note')] || '').replace(/\s+/g, ' ') }));
const ecartees = Object.entries(ECARTEES).flatMap(([motif, cles]) => cles.map(c => ({ cle: c, motif, montant: montant(lignes.get(c)) })));

// Les 6 fournisseurs multi-natures de Jérémy : territoire lu dans l'onglet « Fournisseurs à éclater »
const REGIME_DU_TERRITOIRE = { FR: 'FR', INTRA: 'AUTOLIQ_UE_BIENS', IMPORT: 'AUTOLIQ_IMPORT' };
const terrEclater = new Map(R['Fournisseurs à éclater'].slice(1).map(r => [r[0], r[1]]));
for (const f of fournisseurs.filter(f => f.statut === 'eclater')) {
  const t = f.alias.map(c => terrEclater.get(c)).find(Boolean);
  Object.assign(f, { territoire: t, regime_tva: REGIME_DU_TERRITOIRE[t], mode: 'eclater', statut: 'ok', compte: null, nature: null, tva_deductible: 'OUI', motifs: [] });
}

// Décisions prises avec Robin (29/09/2026), appliquées par-dessus la proposition
const DECISIONS = {
  'Space Up': {
    statut: 'ok', mode: 'eclater', regime_tva: 'FR', territoire: 'FR', tva_deductible: 'OUI', compte: null, motifs: [],
    eclatement: [
      { mots: ['remuneration', 'presidence', 'president'], compte: '61110000', libelle: 'Rémunération de la présidence' },
      { mots: ['gestion', 'prestation', 'management'], compte: '61120000', libelle: 'Prestations de gestion' },
    ],
    note: 'Robin, 29/09 : la même facture porte la gestion et la rémunération de la présidence → deux lignes. FNP SPACE (60712000, 3 018 €) écarté : écriture, pas une facture.',
  },
  'Google Ads': {
    statut: 'ok', regime_tva: 'AUTOLIQ_UE_SERVICES', territoire: 'INTRA', compte: '62313000', tva_intracom: ['IE6388047V'], motifs: [],
    note: 'Robin, 29/09 : Google Ireland, autoliquidation (art. 196), DES. Le « FR » du grand livre venait des libellés de prélèvement.',
  },
  'Meta (Facebook, Instagram)': {
    statut: 'ok', regime_tva: 'AUTOLIQ_UE_SERVICES', territoire: 'INTRA', compte: '62312000', tva_intracom: ['IE9692928F'], motifs: [],
    note: 'Robin, 29/09 : Meta Platforms Ireland, autoliquidation (art. 196), DES. Le « FR » du grand livre venait des libellés de prélèvement.',
  },
  'SCI CMD Immobilier': {
    siren: ['487517104'], tva_intracom: ['FR68487517104'],
    motifs: ['61324000 ou 61327000 : critère inconnu (Robin, 29/09) — question pour Jérémy ou le comptable'],
    note: 'Factures scannées (pas de texte) : loyer bâtiment Cuzieu + taxe foncière, adressées à « SAS SHEIN ».',
  },
};
for (const f of fournisseurs) if (DECISIONS[f.nom]) Object.assign(f, DECISIONS[f.nom]);

writeFileSync(sortie, JSON.stringify({ fournisseurs, vagues, ecartees }, null, 1));
const n = s => fournisseurs.filter(f => f.statut === s).length;
console.log(`${lignes.size} clés → ${fournisseurs.length} fournisseurs (${n('ok')} sûrs dont ${fournisseurs.filter(f => f.mode === 'eclater').length} à éclater, ${n('a_valider')} à valider, ${n('hors')} hors périmètre), ${vagues.length} clés trop vagues, ${ecartees.length} écartées`);

// --sql <fichier> : migration de chargement (idempotente : on recharge tout depuis la proposition)
const iSql = process.argv.indexOf('--sql');
if (iSql > 0) {
  const q = v => v == null ? 'null' : `'${String(v).replace(/'/g, "''")}'`;
  const arr = a => `array[${(a || []).map(q).join(', ')}]::text[]`;
  const js = v => v == null ? 'null' : `${q(JSON.stringify(v))}::jsonb`;
  const dico = R['Dictionnaire produit'].slice(1).filter(r => r[0]);
  const ORDRE = ['TRANSPORT_ACHAT', 'PF_CHIMIE', 'EMBALLAGE', 'FILM_CALAGE', 'CARTON', 'PALETTE', 'MP_ETIQUETAGE', 'MP_CONTENANT', 'MP_CHIMIE', 'PF_ACCESSOIRE'];
  // Variantes d'orthographe vues sur les vraies factures (même nature, mot écrit autrement)
  const DICO_AJOUTS = { MP_CHIMIE: ['shampooing', 'container', 'conteneur'] };
  const compteOuNull = c => /^\d{6,8}$/.test(String(c || '').trim()) ? String(c).trim() : null;
  const sql = [
    `-- Chargement des règles du rangeur de factures (généré par outils/factures/fournisseurs-regroupement.mjs, ${new Date().toISOString().slice(0, 10)}).`,
    `-- Source : regles.xlsx V5 de Jérémy, nettoyé (349 clés → ${fournisseurs.length} fournisseurs) + décisions de Robin du 29/09/2026.`,
    `-- Idempotent : les règles sont rechargées ; une règle modifiée depuis le board (modifie_par non nul) est gardée.`,
    'begin;',
    'insert into factures_fournisseurs (nom, alias, tva_intracom, siren, compte, famille, regime_tva, territoire, nature, tva_deductible, mode, eclatement, statut, motifs, note, notes_jeremy, montant_exercice) values',
    fournisseurs.map(f => `  (${[q(f.nom), arr(f.alias), arr(f.tva_intracom), arr(f.siren), q(f.compte), f.famille ?? 'null', q(f.regime_tva), q(f.territoire), q(f.nature), q(f.tva_deductible), q(f.mode || 'mono'), js(f.eclatement), q(f.statut), arr(f.motifs), q(f.note), arr(f.statut === "ok" ? [] : f.notes_jeremy), Math.round(f.montant)].join(', ')})`).join(',\n'),
    `on conflict (nom) do update set alias = excluded.alias, tva_intracom = excluded.tva_intracom, siren = excluded.siren, compte = excluded.compte,
  famille = excluded.famille, regime_tva = excluded.regime_tva, territoire = excluded.territoire, nature = excluded.nature,
  tva_deductible = excluded.tva_deductible, mode = excluded.mode, eclatement = excluded.eclatement, statut = excluded.statut,
  motifs = excluded.motifs, note = excluded.note, notes_jeremy = excluded.notes_jeremy, montant_exercice = excluded.montant_exercice, modifie_le = now()
where factures_fournisseurs.modifie_par is null;`,
    '',
    'insert into factures_dictionnaire (nature, ordre, mots, compte_fr, compte_intra, compte_import, regle) values',
    dico.map(r => `  (${[q(r[0]), ORDRE.indexOf(r[0]) + 1, arr([...String(r[1]).split(';').map(s => s.trim()).filter(Boolean), ...(DICO_AJOUTS[r[0]] || [])]), q(compteOuNull(r[2])), q(compteOuNull(r[3])), q(compteOuNull(r[4])), q(r[5] || null)].join(', ')})`).join(',\n'),
    'on conflict (nature) do update set ordre = excluded.ordre, mots = excluded.mots, compte_fr = excluded.compte_fr, compte_intra = excluded.compte_intra, compte_import = excluded.compte_import, regle = excluded.regle;',
    '',
    'insert into factures_cles_ecartees (cle, type, motif, compte, montant, note) values',
    [...vagues.map(v => `  (${[q(v.cle), q('vague'), q('clé trop vague : raison sociale à retrouver'), q(v.compte || null), v.montant, q(v.note)].join(', ')})`),
     ...ecartees.map(e => `  (${[q(e.cle), q('ecartee'), q(e.motif), 'null', e.montant, 'null'].join(', ')})`)].join(',\n'),
    'on conflict (cle) do update set type = excluded.type, motif = excluded.motif, compte = excluded.compte, montant = excluded.montant, note = excluded.note;',
    'commit;', '',
  ].join('\n');
  writeFileSync(process.argv[iSql + 1], sql);
  console.log('migration écrite : ' + process.argv[iSql + 1]);
}
