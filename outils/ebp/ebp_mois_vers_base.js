// Prépare un mois d'EBP pour la base du board à partir de trois exports EBP (listes « Factures », « Avoirs » en .xls,
// « Lignes de documents de vente » en .csv, séparateur « ; »).
// Usage : node ebp_mois_vers_base.js AAAA-MM factures.xls avoirs.xls lignes.csv sortie.json   (module xlsx nécessaire)
// Sortie (hors du dépôt, aucune donnée client ici) :
//   montants : [code client, mois, total HT net du mois]  → importer_montants_ebp
//   detail   : { c: code client, m: mois, a: code article, l: libellé, q: quantité, h: montant HT, n: nb de lignes } → charger_ebp_detail
// Règles (vérifiées le 02/10/2026 : redonne au centime 88 des 89 pièces de septembre chargées le 25/09) :
//   - montant d'une facture = son « Total Net HT » (remise de pied comprise), pas la somme de ses lignes ;
//   - montant d'un avoir = somme de ses lignes, ou TTC / 1,2 quand l'avoir porte une remise de pied ;
//   - les avoirs sont négatifs et se déduisent ; ligne sans code article = « SANS_CODE ».
const fs = require('fs'), X = require('xlsx');
const [mois, fFact, fAv, fLignes, sortie] = process.argv.slice(2);
const num = s => parseFloat(String(s).replace(/[^0-9,.\-]/g, '').replace(',', '.')) || 0, r2 = v => Math.round(v * 100) / 100;
const mmaaaa = mois.slice(5) + '/' + mois.slice(0, 4);
const L = fs.readFileSync(fLignes, 'latin1').split(/\r?\n/).slice(1).filter(Boolean).map(l => l.split(';'))
  .filter(c => /^(FA|AV)/.test(c[1]) && c[0].slice(3) === mmaaaa);
const doc = new Map(), det = new Map();
for (const c of L) {
  const d = doc.get(c[1]) || { cl: c[2], lignes: 0 }; d.lignes += num(c[9]); doc.set(c[1], d);
  const a = c[4] || 'SANS_CODE', k = c[2] + '|' + a, o = det.get(k) || { c: c[2], m: mois + '-01', a, l: c[5], q: 0, h: 0, n: 0 };
  o.q += num(c[10]); o.h += num(c[9]); o.n++; det.set(k, o);
}
const feuille = f => { const wb = X.readFile(f); return X.utils.sheet_to_json(wb.Sheets[wb.SheetNames[0]], { header: 1 }).slice(1); };
for (const r of feuille(fFact)) { const d = doc.get(r[0]); if (d) d.tot = +r[3]; }
for (const r of feuille(fAv)) { const d = doc.get(r[0]); if (!d) continue; const ttc = +r[3];
  d.tot = Math.abs(d.lignes * 1.2 - ttc) < 0.03 || Math.abs(d.lignes - ttc) < 0.03 ? r2(d.lignes) : r2(ttc / 1.2); }
const sans = [...doc].filter(([, d]) => d.tot == null).map(([k]) => k);
if (sans.length) throw new Error('documents sans total : ' + sans.join(', '));
const cli = new Map(); for (const d of doc.values()) cli.set(d.cl, (cli.get(d.cl) || 0) + d.tot);
const montants = [...cli].map(([c, v]) => [c, mois, r2(v)]), detail = [...det.values()].map(o => ({ ...o, q: r2(o.q), h: r2(o.h) }));
fs.writeFileSync(sortie, JSON.stringify({ montants, detail }));
console.log(`${mois} : ${doc.size} documents, ${montants.length} clients, ${r2(montants.reduce((a, m) => a + m[2], 0))} € HT net ; détail ${detail.length} lignes, ${r2(detail.reduce((a, d) => a + d.h, 0))} € avant remises de pied`);
