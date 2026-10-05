// MyClear : frais TikTok Shop par mois, à partir de l'export Finance → Relevés (onglet « Order details »).
// Usage : node outils/myclear/frais_tiktok.mjs <dossier du .xlsx dézippé>  → affiche le SQL à exécuter dans Supabase.
// Le fichier ne contient aucune donnée client ; seuls des totaux par mois sortent d'ici.
// Mois = date de commande (comme les ventes du board) ; pour les recharges de pub, date du relevé.
// Un mois de relevé n'est remplacé que si le nouvel export le couvre au moins autant que l'ancien (table myclear_releves_mois) ;
// s'il en couvre moins il est ignoré, si les deux se chevauchent sans s'inclure le chargement s'arrête.
import fs from 'fs';
import path from 'path';

const dir = process.argv[2];
const rd = p => fs.readFileSync(path.join(dir, p), 'utf8');
const dec = s => s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, '&');
const ss = [...rd('xl/sharedStrings.xml').matchAll(/<si>([\s\S]*?)<\/si>/g)]
  .map(m => dec([...m[1].matchAll(/<t[^>]*>([\s\S]*?)<\/t>/g)].map(x => x[1]).join('')));
const wb = rd('xl/workbook.xml'), rels = rd('xl/_rels/workbook.xml.rels');
const rid = wb.match(/<sheet [^>]*name="Order details"[^>]*r:id="([^"]+)"/)[1];
const cible = (rels.match(new RegExp('Id="' + rid + '"[^>]*Target="([^"]+)"')) || rels.match(new RegExp('Target="([^"]+)"[^>]*Id="' + rid + '"')))[1];
const xml = rd('xl/' + cible.replace(/^\/?xl\//, ''));
const rows = [...xml.matchAll(/<row[^>]*>([\s\S]*?)<\/row>/g)].map(r => {
  const row = [];
  for (const c of r[1].matchAll(/<c r="([A-Z]+)\d+"([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g)) {
    const ci = [...c[1]].reduce((a, ch) => a * 26 + ch.charCodeAt(0) - 64, 0) - 1;
    const t = (c[2].match(/t="(\w+)"/) || [])[1];
    let v = ((c[3] || '').match(/<v>([\s\S]*?)<\/v>/) || [])[1];
    if (t === 's') v = ss[+v]; else if (t === 'inlineStr') v = dec(((c[3] || '').match(/<t[^>]*>([\s\S]*?)<\/t>/) || [])[1] || '');
    row[ci] = v;
  }
  return row;
});
const h = rows.shift().map(x => (x || '').trim());
const v = (r, nom) => { const i = h.indexOf(nom); const x = i < 0 ? undefined : r[i]; return x === undefined || x === '/' || x === '' ? 0 : +x; };
const s = (r, nom) => r[h.indexOf(nom)] || '';

// Postes (montants signés : négatif = payé par MyClear)
const POSTES = {
  commission_tiktok: ['TikTok Shop commission fee'],
  commission_affilies: ['Affiliate Commission', 'Affiliate partner commission', 'Affiliate Shop Ads commission',
    'Affiliate Partner shop ads commission', 'Affiliate commission deposit', 'Affiliate commission refund'],
  promotions_tiktok: ['Smart Promotion fee', 'Smart Promotion fee tax', 'Co-funded promotion (seller-funded)',
    'Campaign resource fee', 'Campaign service fee'],
  frais_epr: ['EPR Pay on Behalf service fee'],
  pub_gmv_max: ['GMV Max ad fee'],
};
const tous = Object.values(POSTES).flat();
const agg = {};
let releve; const jours = [];
const ajoute = (mois, poste, x) => { if (!x) return; const k = releve + '|' + mois; agg[k] ??= {}; agg[k][poste] = (agg[k][poste] || 0) + x; };
const ignores = {};
for (const r of rows) {
  const type = s(r, 'Type');
  const d = (s(r, 'Order created date') !== '/' && s(r, 'Order created date')) || s(r, 'Statement date');
  const mois = d.slice(0, 7).replace('/', '-') + '-01';
  const jour = s(r, 'Statement date').replace(/\//g, '-');
  releve = jour.slice(0, 8) + '01'; jours.push(jour);
  if (type === 'Order') {
    for (const [p, cols] of Object.entries(POSTES)) for (const c of cols) ajoute(mois, p, v(r, c));
    // Le reste de la colonne « Fees » qui n'est dans aucun poste connu
    ajoute(mois, 'autres_frais_tiktok', v(r, 'Fees') - tous.filter(c => c !== 'GMV Max ad fee').reduce((a, c) => a + v(r, c), 0) - v(r, 'GMV Max ad fee'));
    // Port : TikTok paie une partie du port du client (le board ne voit que la part payée par le client)
    const retour = v(r, 'Actual return shipping fee') + v(r, 'Return shipping fee reimbursement') + v(r, 'Return shipping label fee');
    ajoute(mois, 'port_retours', retour);
    ajoute(mois, 'aide_port_tiktok', v(r, 'Shipping') - v(r, 'Customer shipping fee') - v(r, 'Refunded customer shipping fee') - retour);
  } else if (/Top up ads balance/i.test(type)) {
    ajoute(mois, 'pub_gmv_max', v(r, 'Adjustment amount'));
  } else {
    ignores[type] = (ignores[type] || 0) + v(r, 'Total settlement amount');
  }
}
const lignes = [];
for (const k of Object.keys(agg).sort()) for (const [poste, x] of Object.entries(agg[k])) {
  const montant = Math.round(x * 100) / 100;
  const [mois_releve, mois] = k.split('|');
  if (montant) lignes.push({ mois_releve, mois, poste, montant });
}
jours.sort();
console.log(`-- Relevés du ${jours[0]} au ${jours.at(-1)} ; lignes ignorées (soldes, virements) : ${JSON.stringify(ignores)}`);
console.log(`select myclear_charger_frais_tiktok('${jours[0]}', '${jours.at(-1)}', '${JSON.stringify(lignes)}'::jsonb);`);
