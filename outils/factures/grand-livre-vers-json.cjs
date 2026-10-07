// Extrait les lignes au débit de l'onglet « ALL LIVRES 600-620 » du grand livre de Jérémy (fichier local) en JSON, pour factures_grand_livre et le banc d'essai.
const X = require(process.env.TEMP + '/packsheet/node_modules/xlsx');
const GL = X.utils.sheet_to_json(X.readFile('C:/Users/jeremy/Documents/SHINE-DIAGNOSTIC/Fichier comptable/Grand compte COMPTA 01-10-25 _ 31-08-2026.xlsx').Sheets['ALL LIVRES 600-620'], { header: 1, defval: '' });
const out = []; let cpt = null; const iso = j => new Date(Date.UTC(1899, 11, 30) + j * 864e5).toISOString().slice(0, 10);
for (const r of GL) { const m = String(r[0]).match(/Compte n°\s+(\d+)/); if (m) { cpt = m[1]; continue; } if (cpt && typeof r[0] === 'number' && +r[4]) out.push({ compte: cpt, date: iso(r[0]), piece: String(r[1] || ''), libelle: String(r[3]), debit: +r[4] }); }
require('fs').writeFileSync('grand_livre.json', JSON.stringify(out)); console.log(out.length, 'lignes', out[0]);
