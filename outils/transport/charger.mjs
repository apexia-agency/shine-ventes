// Chargement des fichiers transporteurs d'un dossier dans Supabase (board Transport).
// Même lecteur que le glisser-déposer du board : transport-lecteurs.js à la racine du dépôt.
//
//   node charger.mjs "<dossier>"                  → lit tout et affiche le contrôle, sans rien envoyer
//   node charger.mjs "<dossier>" --envoyer        → envoie chaque fichier à transport_importer
//
// Pour --envoyer : variable TRANSPORT_JETON (jeton à usage unique créé dans Supabase pour le chargement initial,
// jamais écrit dans le dépôt). Le board, lui, envoie avec la session de la personne connectée.
// Installer une fois : npm install (xlsx, pdfjs-dist).
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
const XLSX = require('xlsx');
const L = require('../../transport-lecteurs.js');
const pdfjs = await import('pdfjs-dist/legacy/build/pdf.mjs');

const SUPABASE_URL = 'https://dfolpanugctzebwpfhze.supabase.co';
const SUPABASE_KEY = 'sb_publishable_k4fwRYCWpfxHvljJgQDiiw_wLCnxu3n';
const dossier = process.argv[2];
const envoyer = process.argv.includes('--envoyer');
if (!dossier) { console.error('Usage : node charger.mjs "<dossier>" [--envoyer]'); process.exit(1); }

function fichiers(d) {
  const out = [];
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) { if (!/^TARIFS$/i.test(e.name)) out.push(...fichiers(p)); }
    else if (!e.name.startsWith('~$') && /\.(xlsx|xls|pdf)$/i.test(e.name)) out.push(p);
  }
  return out.sort();
}

async function textePages(buf) {
  const doc = await pdfjs.getDocument({ data: new Uint8Array(buf), verbosity: 0 }).promise;
  const pages = [];
  for (let p = 1; p <= doc.numPages; p++) {
    const tc = await (await doc.getPage(p)).getTextContent();
    pages.push(tc.items.map(i => i.str + (i.hasEOL ? '\n' : ' ')).join(''));
  }
  await doc.destroy();
  return pages;
}

export async function lire(fp) {
  const buf = fs.readFileSync(fp);
  const nom = path.basename(fp);
  const res = /\.pdf$/i.test(fp)
    ? L.lireColissimo(await textePages(buf), nom)
    : L.lireDPD(XLSX.utils.sheet_to_json((wb => wb.Sheets[wb.SheetNames[0]])(XLSX.read(buf, { type: 'buffer' })), { header: 1, raw: true, defval: null }), nom);
  if (res.fichier) res.fichier.empreinte = crypto.createHash('sha256').update(buf).digest('hex');
  return res;
}

async function rpc(fn, body) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });
  const t = await r.text();
  if (!r.ok) throw new Error(`${r.status} ${t.slice(0, 300)}`);
  return JSON.parse(t);
}

const eur = v => (v ?? 0).toLocaleString('fr-FR', { maximumFractionDigits: 2, minimumFractionDigits: 2 });
const liste = fichiers(dossier);
const bilan = {};
for (const fp of liste) {
  const rel = path.relative(dossier, fp);
  let res;
  try { res = await lire(fp); } catch (e) { res = { erreur: 'illisible : ' + e.message }; }
  if (res.erreur) { console.log(`✗ ${rel} — ${res.erreur}`); continue; }
  const f = res.fichier;
  let ctl = '';
  if (f.total_facture_ht != null) {
    const rc = f.details.recap;
    const attendu = (rc.port_net || 0) + (rc.cae || 0) + (rc.supplements || 0) + (rc.smic || 0);
    ctl = ` | facture : port net + CAE + suppléments = ${eur(attendu)} (écart ${eur(f.montant_ht - attendu)}) ; prestations ${eur(f.prestations_ht)} ; indemnités ${eur(f.indemnites_ht)} ; total HT ${eur(f.total_facture_ht)}`;
  }
  console.log(`✓ ${rel} — ${f.transporteur} ${f.format} ${f.mois} ${f.service || ''} : ${f.colis} colis, ${f.nb_lignes} lignes, ${eur(f.montant_ht)} € HT${ctl}`);
  const b = bilan[f.transporteur] ||= { colis: 0, ht: 0, fichiers: 0 };
  b.colis += f.colis; b.ht += f.montant_ht; b.fichiers++;
  if (envoyer) {
    const jeton = process.env.TRANSPORT_JETON;
    if (!jeton) { console.error('TRANSPORT_JETON manquant'); process.exit(1); }
    const LOT = 3000;
    let r = await rpc('transport_importer', { p_fichier: f, p_lignes: res.lignes.slice(0, LOT), p_jeton: jeton });
    for (let i = LOT; i < res.lignes.length && !r.termine; i += LOT)
      r = await rpc('transport_importer', { p_fichier: f, p_lignes: res.lignes.slice(i, i + LOT), p_jeton: jeton, p_suite: r.fichier_id });
    console.log(`   → ${r.statut}${r.doublon_de ? ' (déjà dans ' + r.doublon_de + ')' : ''} : ${r.lignes_ajoutees ?? 0} lignes ajoutées`);
  }
}
console.log('\nBilan (avant retrait des doublons) :', Object.entries(bilan).map(([k, b]) => `${k} ${b.fichiers} fichiers, ${b.colis} colis, ${eur(b.ht)} € HT`).join(' ; '));
