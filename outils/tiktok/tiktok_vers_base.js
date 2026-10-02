// Prépare les exports de commandes TikTok Shop (« Toutes les commandes », CSV ou XLSX dézippé) pour la base du board.
// Usage : node tiktok_vers_base.js sortie.txt fichier1.csv fichier2.xml ...   (les derniers fichiers l'emportent sur les premiers)
// Sortie : une ligne par article de commande, séparée par « | », à passer à la fonction SQL charger_tiktok(texte).
//   id_commande | date d'expédition (AAAA-MM-JJ) | acheteur | pays | code postal | port HT | n° de ligne | SKU vendeur | libellé | quantité | PU HT | remise HT | total HT
// Règles (validées avec Jérémy, les mêmes que l'export comptable) :
//   - commandes annulées ou pas encore expédiées : écartées ; date de la vente = date d'expédition ;
//   - prix = prix avant remise TikTok (TikTok la reverse au vendeur), moins la remise du vendeur ; HT = TTC / 1,2 ;
//   - remboursement : déduit des produits (au prorata des lignes), puis du port ; commande remboursée en entier : écartée.
// Aucune donnée n'est écrite dans le dépôt : la sortie reste hors du dépôt.
const fs = require('fs');
const dec = s => String(s ?? '').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&#(\d+);/g, (m, n) => String.fromCharCode(+n));
function lireXml(f) {
  const x = fs.readFileSync(f, 'utf8'), par = new Map();
  for (const cm of x.matchAll(/<c r="([A-Z]+)(\d+)"[^>]*?(?:\/>|>([\s\S]*?)<\/c>)/g)) {
    const col = cm[1].split('').reduce((a, ch) => a * 26 + ch.charCodeAt(0) - 64, 0) - 1, ln = +cm[2];
    const v = (cm[3] || '').match(/<v>([\s\S]*?)<\/v>/) || (cm[3] || '').match(/<t[^>]*>([\s\S]*?)<\/t>/);
    if (!par.has(ln)) par.set(ln, []); par.get(ln)[col] = v ? dec(v[1]) : '';
  }
  return [...par.keys()].sort((a, b) => a - b).map(k => par.get(k));
}
function lireCsv(f) {
  const t = fs.readFileSync(f, 'utf8').replace(/^﻿/, ''); const rows = []; let r = [], c = '', q = false;
  for (let i = 0; i < t.length; i++) {
    const ch = t[i];
    if (q) { if (ch === '"' && t[i + 1] === '"') { c += '"'; i++; } else if (ch === '"') q = false; else c += ch; }
    else if (ch === '"') q = true; else if (ch === ',') { r.push(c); c = ''; } else if (ch === '\n') { r.push(c.replace(/\r$/, '')); rows.push(r); r = []; c = ''; } else c += ch;
  }
  if (c || r.length) { r.push(c); rows.push(r); }
  return rows;
}
const eur = s => { const n = parseFloat(String(s ?? '').replace(/EUR|€|\s/g, '').replace(',', '.')); return isFinite(n) ? n : 0; };
const iso = s => { const m = String(s || '').trim().match(/^(\d{2})\/(\d{2})\/(\d{4})/); return m ? `${m[3]}-${m[1]}-${m[2]}` : ''; }; // MM/JJ/AAAA
const net = s => String(s ?? '').replace(/[|\r\n\t]/g, ' ').trim();
const r2 = v => Math.round(v * 100) / 100;

const [sortie, ...fichiers] = process.argv.slice(2);
const cmd = new Map();
for (const f of fichiers) {
  const rows = /\.xml$/i.test(f) ? lireXml(f) : lireCsv(f);
  const h = rows[0].map(x => String(x || '').trim()), I = n => h.indexOf(n);
  const vus = new Set();
  for (const r of rows.slice(1)) {
    const id = net(r[I('Order ID')]); if (!/^\d{10,}$/.test(id)) continue;
    if (!vus.has(id)) { cmd.delete(id); vus.add(id); } // une commande présente dans un fichier plus récent le remplace en entier
    const o = cmd.get(id) || { id, statut: r[I('Order Status')] || '', date: iso(r[I('Shipped Time')]), acheteur: net(r[I('Buyer Username')]) || 'acheteur-' + id, pays: net(r[I('Country')]), cp: net(r[I('Zipcode')]),
      port: eur(r[I('Original Shipping Fee')]) - eur(r[I('Shipping Fee Seller Discount')]), rembourse: eur(r[I('Order Refund Amount')]), lignes: [] };
    o.lignes.push({ sku: net(r[I('Seller SKU')]), lib: net(r[I('Product Name')]).slice(0, 120), q: +String(r[I('Quantity')] || '0').trim() || 0, pu: eur(r[I('SKU Unit Original Price')]), brut: eur(r[I('SKU Subtotal Before Discount')]), remise: eur(r[I('SKU Seller Discount')]) });
    cmd.set(id, o);
  }
}
const out = []; const st = { gardees: 0, annulees: 0, nonExpediees: 0, remboursees: 0, partielles: 0, ht: 0, port: 0 };
for (const o of cmd.values()) {
  if (/annul/i.test(o.statut)) { st.annulees++; continue; }
  if (!o.date) { st.nonExpediees++; continue; }
  const prod = o.lignes.reduce((a, l) => a + l.brut - l.remise, 0);
  if (o.rembourse >= prod + o.port - 0.01 && o.rembourse > 0) { st.remboursees++; continue; }
  const rembP = Math.min(o.rembourse, prod), coef = prod > 0 ? 1 - rembP / prod : 1; if (o.rembourse > 0) st.partielles++;
  const portHT = r2(Math.max(0, o.port - (o.rembourse - rembP)) / 1.2);
  o.lignes.forEach((l, i) => {
    const tot = r2((l.brut - l.remise) * coef / 1.2);
    out.push([o.id, o.date, o.acheteur, o.pays === 'France' ? 'FR' : o.pays, o.cp, portHT, i + 1, l.sku, l.lib, l.q, r2(l.pu / 1.2), r2(l.remise / 1.2), tot].join('|'));
    st.ht += tot;
  });
  st.gardees++; st.port += portHT;
}
fs.writeFileSync(sortie, out.join('\n'));
const dates = [...new Set(out.map(l => l.split('|')[1]))].sort();
console.log(`${cmd.size} commandes lues ; gardées ${st.gardees} (du ${dates[0]} au ${dates[dates.length - 1]}), ${out.length} lignes, ${Math.round(st.ht)} € HT produits, ${Math.round(st.port)} € HT de port`);
console.log(`écartées : ${st.annulees} annulées, ${st.nonExpediees} pas encore expédiées, ${st.remboursees} remboursées en entier ; ${st.partielles} remboursées en partie (montant déduit)`);
