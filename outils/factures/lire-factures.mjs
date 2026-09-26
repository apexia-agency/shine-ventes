#!/usr/bin/env node
// Envoie les factures d'achat PDF du serveur SHINE à la fonction Supabase « lire-facture »,
// qui les fait lire par Claude et les range dans la table factures_achats.
//
// Usage (Node 18 ou plus, aucune dépendance) :
//   node lire-factures.mjs --essai                 liste ce qui serait envoyé, n'envoie rien
//   node lire-factures.mjs --liste test-20.txt     envoie seulement les fichiers de la liste (chemins relatifs à la racine)
//   node lire-factures.mjs --limite 50             envoie au plus 50 nouveaux PDF
//   node lire-factures.mjs                         envoie tous les nouveaux PDF (tâche planifiée de la nuit)
//
// Variable d'environnement obligatoire : FACTURES_TOKEN (le même jeton que le secret Supabase du même nom).
// Options : --racine "<dossier>" (par défaut P:\Comptabilité\01 - Factures\Achat-Vente), --dossiers "BILAN 2024-2025,BILAN 2025-2026".
// Le journal lire-factures.journal.json (à côté du script) retient les fichiers déjà lus : on peut arrêter et relancer.

import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import { join, relative, dirname, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const args = process.argv.slice(2);
const opt = (nom, def) => { const i = args.indexOf('--' + nom); return i >= 0 ? (args[i + 1] ?? true) : def; };
const RACINE = opt('racine', 'P:\\Comptabilité\\01 - Factures\\Achat-Vente');
const DOSSIERS = String(opt('dossiers', 'BILAN 2024-2025,BILAN 2025-2026')).split(',').map(s => s.trim()).filter(Boolean);
const ESSAI = args.includes('--essai');
const LIMITE = parseInt(opt('limite', '0'), 10) || Infinity;
const LISTE = opt('liste', null);
const URL_FONCTION = process.env.FACTURES_URL || 'https://dfolpanugctzebwpfhze.supabase.co/functions/v1/lire-facture';
const JETON = process.env.FACTURES_TOKEN;
const EN_PARALLELE = 2;
const ICI = dirname(fileURLToPath(import.meta.url));
const JOURNAL = join(ICI, 'lire-factures.journal.json');

// Les ventes et les fichiers techniques ne sont pas des factures d'achat
const ignorer = chemin => /(^|[\\/])(0 - )?VENTES?([\\/]|$)|VENTE AUTO/i.test(chemin);

function parcourir(dossier, out = []) {
  for (const nom of readdirSync(dossier)) {
    const p = join(dossier, nom);
    let st; try { st = statSync(p); } catch { continue; }
    if (st.isDirectory()) { if (!ignorer(p)) parcourir(p, out); }
    else if (/\.pdf$/i.test(nom) && !ignorer(p)) out.push(p);
  }
  return out;
}

const journal = existsSync(JOURNAL) ? JSON.parse(readFileSync(JOURNAL, 'utf8')) : {};
const sauver = () => writeFileSync(JOURNAL, JSON.stringify(journal, null, 1));
const relatif = p => relative(RACINE, p).split(sep).join('/');

let fichiers;
if (LISTE) fichiers = readFileSync(LISTE, 'utf8').split(/\r?\n/).map(s => s.trim()).filter(Boolean).map(r => join(RACINE, ...r.split('/')));
else fichiers = DOSSIERS.flatMap(d => parcourir(join(RACINE, d))).sort();

// Empreinte SHA-256 : un fichier déjà lu (même contenu) n'est jamais renvoyé
const aFaire = [];
for (const p of fichiers) {
  if (aFaire.length >= LIMITE) break;
  let buf; try { buf = readFileSync(p); } catch (e) { console.error('Illisible :', relatif(p), e.message); continue; }
  const empreinte = createHash('sha256').update(buf).digest('hex');
  if (journal[empreinte]?.statut === 'lu') continue;
  aFaire.push({ p, empreinte, taille: buf.length });
}
console.log(`${fichiers.length} PDF trouvés, ${aFaire.length} à lire${ESSAI ? ' (essai : rien n\'est envoyé)' : ''}.`);
if (ESSAI) { aFaire.slice(0, 30).forEach(f => console.log(' -', relatif(f.p))); process.exit(0); }
if (!JETON) { console.error('Variable FACTURES_TOKEN absente : rien n\'est envoyé.'); process.exit(1); }

const pause = ms => new Promise(r => setTimeout(r, ms));
async function envoyer(f) {
  const corps = JSON.stringify({ fichier: relatif(f.p), empreinte: f.empreinte, pdf: readFileSync(f.p).toString('base64') });
  for (let essai = 1; essai <= 4; essai++) {
    const r = await fetch(URL_FONCTION, { method: 'POST', headers: { 'content-type': 'application/json', 'x-jeton-factures': JETON }, body: corps });
    const rep = await r.json().catch(() => ({ error: 'réponse illisible (' + r.status + ')' }));
    if (r.ok) return rep;
    if ([429, 500, 502, 503, 504].includes(r.status) && essai < 4) { await pause(5000 * essai); continue; }
    throw new Error(rep.error || ('HTTP ' + r.status));
  }
}

let n = 0, cout = 0, aVerifier = 0, erreurs = 0;
const file = [...aFaire];
async function ouvrier() {
  while (file.length) {
    const f = file.shift();
    try {
      const rep = await envoyer(f);
      n++;
      if (rep.deja) { journal[f.empreinte] = { fichier: relatif(f.p), statut: 'lu', le: new Date().toISOString() }; sauver(); continue; }
      cout += rep.cout_usd || 0; if (rep.a_verifier) aVerifier++;
      journal[f.empreinte] = { fichier: relatif(f.p), statut: 'lu', id: rep.id, le: new Date().toISOString() }; sauver();
      const m = v => v == null ? '—' : v.toFixed(2);
      console.log(`${n}/${aFaire.length} ${rep.a_verifier ? '⚠' : '✓'} ${rep.fournisseur} · ${rep.date_facture || '?'} · HT ${m(rep.montant_ht)} · TTC ${m(rep.montant_ttc)} ${rep.devise} · ${rep.poste} > ${rep.categorie}${rep.motif ? ' · ' + rep.motif : ''}`);
    } catch (e) {
      erreurs++; journal[f.empreinte] = { fichier: relatif(f.p), statut: 'erreur', erreur: e.message, le: new Date().toISOString() }; sauver();
      console.error(`✗ ${relatif(f.p)} : ${e.message}`);
    }
  }
}
await Promise.all(Array.from({ length: EN_PARALLELE }, ouvrier));
console.log(`\nTerminé : ${n} lus, ${aVerifier} à vérifier, ${erreurs} en erreur. Coût Claude : ${cout.toFixed(2)} $.`);
