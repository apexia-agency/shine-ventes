// Règles du rangeur de factures calées sur le livre des achats de septembre 2026 validé par Jérémy (07/10/2026).
// Chaque entrée modifie un fournisseur existant (même « nom » que dans factures_fournisseurs) ou en crée un nouveau.
// « regles » : règles de contenu du moteur V6 (supabase/functions/lire-facture/moteur.ts) ; la première qui s'applique décide.
//   si : mots cherchés (mots entiers, sans accents ; plaque sans tirets acceptée) ; ligne : true = ligne par ligne, sinon toute la facture
//   compte / sous_rubrique : imputation ; tva_deductible : taux propre (NON, 80%) ; ecarter : hors achats SHINE ; verifier : question
// Usage : node regles-livre-2026-09.mjs <regles_actuelles.json> <regles_nouvelles.json> <migration.sql>
import { readFileSync, writeFileSync } from 'node:fs';

const NEXUS_MP = { compte: '60110000', sous_rubrique: 'MP CHIMIE POUR NEXUS' };
const SPACE_UP = 'véhicule de SPACE UP (Jérémy, 07/10/2026) : pas un achat de SHINE';

export const CHANGEMENTS = [
  // Loyers, énergie, bâtiments
  { nom: 'Boutique Store (loyer Veauche)', alias: ['ANGEL STORES', 'BOUTIQUE DU STORE', 'LA BOUTIQUE DU STORE'], compte: '61323000',
    regles: [{ si: ['taxe fonciere', 'taxes foncieres'], ligne: true, compte: '61410000', note: 'taxe foncière refacturée par le bailleur : charges locatives' },
      { si: ['electricite'], ligne: true, compte: '60610000' }] },
  { nom: 'SCI CMD Immobilier', alias: ['IMMO COMUNICA', 'SCI IMMO COMUNICA'], compte: '61327000', regime_tva: 'FR', tva_deductible: 'OUI', statut: 'ok', motifs: [],
    note: 'Loyer des locaux 348 rue François Durafour (Jérémy, livre de septembre 2026).' },
  { nom: 'Direction générale des Finances publiques', nouveau: true, alias: ['DIRECTION GENERALE DES FINANCES PUBLIQUES', 'FINANCES PUBLIQUES', 'DGFIP'], famille: 15, regime_tva: 'SANS_TVA',
    regles: [{ si: ['taxe fonciere', 'taxes foncieres'], ecarter: 'avis de taxe foncière du propriétaire : justificatif d\'une refacturation, pas à saisir' }],
    note: 'Impôts : seuls les avis de taxe foncière du propriétaire sont écartés ; le reste est à vérifier.' },
  { nom: 'La Banque Postale (leasing visseuse)', tva_deductible: 'OUI', note: 'Loyer de la visseuse passé HT par le cabinet (livre de septembre 2026).' },
  // Véhicules : un compte par plaque ; voitures de tourisme TVA non déductible ; véhicules de Space Up écartés
  { nom: 'Capitole Finance', statut: 'ok', motifs: [], compte: null, regime_tva: 'FR', tva_deductible: 'OUI',
    regles: [{ si: ['FN 425 QX', '308'], compte: '61221110', note: 'Peugeot 308 : voiture de société, loyer HT (Jérémy, 07/10/2026)' },
      { si: ['FG 937 ME', 'GOLF'], compte: '61221100', note: 'Golf : voiture de société, loyer HT (Jérémy, 07/10/2026)' },
      { si: ['DX 934 GV', 'IVECO'], compte: '61229000' },
      { si: ['CHARIOT'], compte: '61351600' }],
    note: 'Un compte par véhicule ; véhicule inconnu → à vérifier.' },
  { nom: 'Volkswagen Bank', alias: ['VOLKSWAGEN BANK', 'VOLKSWAGEN FINANCIAL SERVICES'], statut: 'ok', motifs: [], compte: null, regime_tva: 'FR', tva_deductible: 'NON',
    regles: [{ si: ['GZ 505 XD', 'ATECA'], ecarter: SPACE_UP }, { si: ['GT 479 WH'], ecarter: SPACE_UP },
      { si: ['GR 171 EW'], compte: '61225000' }, { si: ['GR 172 EW'], compte: '61228000' }, { si: ['GR 197 AH'], compte: '61226000' }],
    note: 'Voitures de tourisme : loyer TTC (TVA non déductible). Ateca et Cupra GT479WH : véhicules de Space Up, écartés.' },
  { nom: 'HDV Automobiles', nouveau: true, alias: ['HDV AUTOMOBILES', 'HDV'], compte: '61520000', famille: 13, tva_deductible: 'NON',
    note: 'Carrosserie : réparations des voitures de tourisme (TVA non déductible).' },
  { nom: 'Carrefour Market Veauche (Veauch Distri)', nouveau: true, alias: ['VEAUCH DISTRI', 'CARREFOUR MARKET VEAUCHE', 'CARREFOUR MARKET'], compte: '62570000', famille: 16,
    regles: [{ si: ['GZ 505 XD'], ecarter: 'carburant de la Seat Ateca, ' + SPACE_UP },
      { si: ['gazole', 'gasoil', 'diesel', 'essence', 'carburant', 'SP95', 'SP98', 'E10'], compte: '60614000', tva_deductible: '80%' }],
    note: 'Tickets : carburant (80 % de la TVA déductible) ou café et fournitures du bureau.' },
  { nom: 'Intermarché (carburant) ?', alias: ['INTERMARCHE'], statut: 'ok', motifs: [], note: 'Carburant : 80 % de la TVA déductible.' },
  { nom: 'Ulys (péages)', alias: ['ASF', 'VINCI AUTOROUTES'] },
  // Assurance
  { nom: 'Gan Assurances', alias: ['GAN ASSURANCES', 'GAN'], statut: 'ok', motifs: [], compte: '61611000', regime_tva: 'SANS_TVA',
    regles: [{ si: ['indemnite', 'indemnisation', 'sinistre'], ecarter: 'indemnité d\'assurance : un produit (export des ventes, onglet « Hors ventes »), pas un achat' },
      { si: ['responsabilite civile', 'RC PRO', 'RC professionnelle'], ecarter: 'échéancier RC Pro 2026-2027 : 680,83 € par mois d\'octobre 2026 à septembre 2027, passés chaque mois avec la même pièce' }],
    note: 'Multirisque en 61611000 ; indemnités et échéancier RC Pro écartés (Jérémy, 07/10/2026).' },
  // Personnel
  { nom: 'Edenred', nouveau: true, alias: ['EDENRED', 'EDENRED FRANCE'], compte: '62700000', famille: 14,
    regles: [{ si: ['commission'], ligne: true, compte: '62700000' },
      { si: ['valeur faciale', 'titres restaurant', 'titre restaurant', 'ticket restaurant'], ligne: true, ecarter: 'valeur des titres-restaurant : paie (part SHINE 60 % en 6475, part des salariés retenue sur la paie)' }],
    note: 'Seule la commission est un achat (Jérémy, 07/10/2026).' },
  // Nexus : achats pour Nexus en sous-rubriques du livre
  { nom: 'Univar', ...NEXUS_MP }, { nom: 'Vidara', ...NEXUS_MP }, { nom: 'Quimidroga', ...NEXUS_MP },
  { nom: 'Interchimie', ...NEXUS_MP }, { nom: 'Stockmeier', ...NEXUS_MP }, { nom: 'Keyser', ...NEXUS_MP },
  { nom: 'Spiess', compte: '60130000', sous_rubrique: 'MP CHIMIE INTRA POUR NEXUS', statut: 'ok', motifs: [] },
  { nom: 'Chemipol', compte: '60130000', sous_rubrique: 'MP CHIMIE INTRA POUR NEXUS', statut: 'ok', motifs: [] },
  { nom: 'Labbox', nouveau: true, alias: ['LABBOX', 'LABBOX FRANCE'], compte: '60130000', sous_rubrique: 'AMENAGEMENT POUR NEXUS', famille: 17 },
  { nom: 'Labomat', compte: '60130000', sous_rubrique: 'AMENAGEMENT POUR NEXUS', statut: 'ok', motifs: [] },
  { nom: 'Mecalux', compte: '60130000', sous_rubrique: 'AMENAGEMENT POUR NEXUS', statut: 'ok', motifs: [] },
  { nom: 'RS Développement', nouveau: true, alias: ['RS DEVELOPPEMENT'], compte: '60400000', famille: 12,
    regles: [{ si: ['NEXUS', 'point eclair', 'points eclair'], ...NEXUS_MP, note: 'factures marquées Nexus et points éclair : MP chimie pour Nexus (Jérémy, 07/10/2026)' }] },
  // Emballages, étiquettes, matières
  { nom: "Plast'Embal", compte: '60263000', sous_rubrique: 'CALAGE ET SCOTCH + BTC',
    regles: [{ si: ['film', 'banderole', 'stretch', 'etirable'], ligne: true, compte: '60263000', sous_rubrique: 'FILM + BTB' }] },
  { nom: 'Napack', compte: '60112000', statut: 'ok', motifs: [], note: 'MP étiquetage, comme dans le livre (Jérémy).' },
  { nom: 'Plastic Billat', compte: '60711200', statut: 'ok', motifs: [] },
  { nom: 'TNM (VPK) Les Échets', alias: ['TNM EMBALLAGES', 'TNM'] },
  { nom: 'AB Packaging', nouveau: true, alias: ['AB PACKAGING'], compte: '60261000', famille: 3 },
  { nom: 'F2MI', nouveau: true, alias: ['F2MI'], compte: '60711100', famille: 2 },
  // Services
  { nom: 'Cabinet comptable (RG Conseils ?)', alias: ['RG CONSEILS', 'EMENIS'], statut: 'ok', motifs: [] },
  { nom: 'Cylium', alias: ['CYLIUMDEV', 'CYLIUM DEV'], note: 'Contrat arrêté en juillet 2026 (Jérémy, 07/10/2026).' },
  { nom: 'Kheminos', nouveau: true, alias: ['KHEMINOS'], compte: '60400000', famille: 12 },
  { nom: 'L.A. Autoclean', nouveau: true, alias: ['AUTOCLEAN', 'L A AUTOCLEAN'], compte: '61530000', famille: 10, note: 'Réparations prises en charge pour des litiges clients.' },
  { nom: 'UPS', regles: [{ si: ['droits', 'douane', 'dedouanement', 'import', 'TVA import'], compte: '62380000', sous_rubrique: 'TRANSPORT SUR ACHATS IMPORT' }] },
  { nom: 'Channable', alias: ['PRODUCTIMPULSE'], regime_tva: 'AUTOLIQ_UE_SERVICES', territoire: 'INTRA' },
  { nom: 'Shopify', regime_tva: 'AUTOLIQ_UE_SERVICES', territoire: 'INTRA' },
  { nom: 'TikTok', regime_tva: 'AUTOLIQ_IMPORT', territoire: 'IMPORT', note: 'Factures émises depuis le Royaume-Uni : TVA à autoliquider.' },
];

const CHAMPS = ['alias', 'compte', 'sous_rubrique', 'regime_tva', 'territoire', 'tva_deductible', 'statut', 'motifs', 'regles', 'note', 'famille'];
export function appliquer(fournisseurs) {
  const F = fournisseurs.map((f) => ({ ...f }));
  for (const c of CHANGEMENTS) {
    let f = F.find((x) => x.nom === c.nom);
    if (!f && !c.nouveau) throw new Error('Fournisseur absent : ' + c.nom);
    if (!f) { f = { id: F.length + 1, nom: c.nom, alias: [], tva_intracom: [], siren: [], compte: null, regime_tva: 'FR', territoire: 'FR', nature: null, tva_deductible: 'OUI', mode: 'mono', eclatement: null, statut: 'ok', motifs: [], note: null }; F.push(f); }
    for (const k of CHAMPS) if (k in c) f[k] = k === 'alias' ? [...new Set([...(f.alias || []), ...c.alias])] : c[k];
  }
  return F;
}

const lit = (v) => v == null ? 'null' : typeof v === 'number' ? String(v) : `'${String(v).replace(/'/g, "''")}'`;
const tab = (a) => `array[${(a || []).map(lit).join(', ')}]::text[]`;
export function sql(F) {
  const lignes = CHANGEMENTS.map((c) => {
    const f = F.find((x) => x.nom === c.nom);
    if (c.nouveau) return `insert into factures_fournisseurs (nom, alias, compte, sous_rubrique, famille, regime_tva, territoire, tva_deductible, mode, regles, statut, motifs, note, origine)\n  values (${lit(f.nom)}, ${tab(f.alias)}, ${lit(f.compte)}, ${lit(f.sous_rubrique)}, ${lit(f.famille)}, ${lit(f.regime_tva)}, ${lit(f.territoire)}, ${lit(f.tva_deductible)}, 'mono', ${f.regles ? lit(JSON.stringify(f.regles)) + '::jsonb' : 'null'}, 'ok', array[]::text[], ${lit(f.note)}, 'livre de septembre 2026 (Jérémy, 07/10/2026)')\n  on conflict (nom) do nothing;`;
    const sets = CHAMPS.filter((k) => k in c).map((k) => k === 'alias' ? `alias = ${tab(f.alias)}` : k === 'motifs' ? `motifs = ${tab(c.motifs)}` : k === 'regles' ? `regles = ${lit(JSON.stringify(c.regles))}::jsonb` : `${k} = ${lit(c[k])}`);
    return `update factures_fournisseurs set ${sets.join(', ')}, modifie_par = 'livre 2026-09', modifie_le = now() where nom = ${lit(c.nom)};`;
  });
  return lignes.join('\n');
}

if (process.argv[1] && process.argv[1].endsWith('regles-livre-2026-09.mjs') && process.argv[2]) {
  const R = JSON.parse(readFileSync(process.argv[2], 'utf8'));
  const F = appliquer(R.fournisseurs);
  writeFileSync(process.argv[3], JSON.stringify({ ...R, fournisseurs: F }, null, 1));
  if (process.argv[4]) writeFileSync(process.argv[4], sql(F) + '\n');
  console.log(CHANGEMENTS.length, 'changements ;', F.length, 'fournisseurs');
}
