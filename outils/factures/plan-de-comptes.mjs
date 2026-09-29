// Plan de comptes du rangeur (29/09/2026) : un dossier Drive par livre de compte, « 60262000_CARTON ».
// Les libellés viennent du grand livre, tels que Jérémy les a notés dans regles.xlsx (V5) :
//   - onglet Fournisseurs, colonne Note « - | LIBELLÉ DU COMPTE | n lignes | … » (charges) ;
//   - onglet Fournisseurs à éclater, colonne « Libellé du compte » (matières et marchandises) ;
//   - onglet Dictionnaire produit : à défaut, le nom de la nature (CARTON, PALETTE…).
// Un compte utilisé par une règle mais sans libellé connu est écrit sans libellé : son dossier sera « <numéro>_A-LIBELLER ».
// Usage : node plan-de-comptes.mjs regles.json propose.json sortie.sql
import { readFileSync, writeFileSync } from 'node:fs';

const [, , fRegles, fPropose, fSql] = process.argv;
const R = JSON.parse(readFileSync(fRegles, 'utf8'));
const P = JSON.parse(readFileSync(fPropose, 'utf8'));
const estCompte = c => /^\d{8}$/.test(String(c || '').trim());
const lib = new Map(), source = new Map();
const poser = (c, l, s) => { c = String(c).trim(); l = String(l || '').replace(/\s+/g, ' ').trim(); if (!estCompte(c) || !l || lib.has(c)) return; lib.set(c, l); source.set(c, s); };

// 1. Fournisseurs à éclater : libellés propres des comptes de matières et marchandises
for (const r of R['Fournisseurs à éclater'].slice(1)) poser(r[3], r[4], 'grand livre (fournisseurs à éclater)');
// 2. Notes des fournisseurs : « - | LIBELLÉ | n lignes »
const [ent, ...fo] = R['Fournisseurs']; const iC = ent.indexOf('Compte'), iN = ent.indexOf('Note');
for (const r of fo) {
  const p = String(r[iN] || '').split('|').map(s => s.trim());
  // « - » en tête = compte de charge, suivi de son libellé ; « FR / INTRA / IMPORT » = une nature, pas un libellé
  if (p[0] === '-' && p[1]) poser(r[iC], p[1], 'grand livre (note fournisseur)');
}
// 3. Dictionnaire produit : nom de la nature, par territoire
const TERR = { 2: 'FR', 3: 'INTRA', 4: 'IMPORT' };
for (const r of R['Dictionnaire produit'].slice(1)) for (const i of [2, 3, 4]) if (estCompte(r[i])) poser(r[i], `${String(r[0]).replace(/_/g, ' ')}${r[0].startsWith('MP_') || r[0].startsWith('PF_') ? ' ' + TERR[i] : ''}`, 'dictionnaire produit');
// 4. Comptes des décisions de Robin (Space Up éclaté)
poser('62421000', 'TRANSP. / VENTES DPD', 'document 39 de Jérémy (62421000_TRANSP-VENTES-DPD)');
poser('61110000', 'REMUNERATION PRESIDENCE', 'décision Robin 29/09'); poser('61120000', 'PRESTATIONS GESTION PRESIDENCE', 'décision Robin 29/09');

// Tous les comptes utilisés par une règle
const utilises = new Set();
for (const f of P.fournisseurs) { if (estCompte(f.compte)) utilises.add(f.compte); (f.eclatement || []).forEach(e => utilises.add(e.compte)); }
for (const r of R['Dictionnaire produit'].slice(1)) for (const i of [2, 3, 4]) if (estCompte(r[i])) utilises.add(String(r[i]).trim());
for (const c of lib.keys()) utilises.add(c);

const q = v => v == null ? 'null' : `'${String(v).replace(/'/g, "''")}'`;
const lignes = [...utilises].sort().map(c => `  (${q(c)}, ${q(lib.get(c) || null)}, ${q(source.get(c) || 'aucun libellé connu')})`);
writeFileSync(fSql, `-- Plan de comptes du rangeur : généré par outils/factures/plan-de-comptes.mjs le ${new Date().toISOString().slice(0, 10)}.
insert into factures_comptes (compte, libelle, source) values
${lignes.join(',\n')}
on conflict (compte) do update set libelle = excluded.libelle, source = excluded.source where factures_comptes.modifie_par is null;
`);
const sans = [...utilises].filter(c => !lib.has(c));
console.log(`${utilises.size} comptes, ${utilises.size - sans.length} avec libellé, ${sans.length} sans : ${sans.join(', ')}`);
