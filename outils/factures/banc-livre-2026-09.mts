// Banc d'essai du rangeur V6 : les factures de septembre 2026 passent dans le moteur, comparées au livre des achats validé par Jérémy (v13).
// Les données (lectures des PDF, livre attendu, grand livre) sont des fichiers locaux, jamais dans le dépôt.
// Usage : node banc.mts <moteur.ts> <regles.json> [detail]
import fs from 'node:fs';
const [, , MOTEUR = './moteur_actuel.ts', REGLES = './regles_actuelles.json', DETAIL] = process.argv;
const { classer } = await import(MOTEUR);
const R = JSON.parse(fs.readFileSync(REGLES, 'utf8'));
const DOCS = JSON.parse(fs.readFileSync('C:/Users/jeremy/AppData/Local/Temp/claude/C--Users-jeremy-Documents-shine-ventes/44b185ea-7ee5-4fef-8b84-b08f0fd75e1e/scratchpad/achats/tous.json', 'utf8'));
const GL = JSON.parse(fs.readFileSync('./grand_livre.json', 'utf8'));
const A = JSON.parse(fs.readFileSync('./attendu.json', 'utf8'));
// Mêmes regroupements que le livre (Boutique du Store fusionnée)
const BDS1 = 'HA-FG-BOUTIQUE DU STORE-260914-fin de bail électricité et loyer juin-31.46 €TTC réglés.pdf', BDS2 = 'HA-FG-BOUTIQUE DU STORE-260917-refact Taxe Foncière BDS42-26-09-966-516.90 €TTC.pdf';
const docs = DOCS.filter(o => !(/BOUTIQUE DU STORE/i.test(o.fichier) && /JUSTIFICATIF|règlement réel/i.test(o.fichier))).map(o => ({ ...o, fichier: o.numero === 'BDS42-26-09-966' ? BDS2 : ['BDS42-26-09-942', 'BDS42-26-09-943'].includes(o.numero) ? BDS1 : o.fichier }));
const iso = d => { const [j, m, a] = (d || '').split('/'); return a ? `${a}-${m}-${j}` : null; };
const lecture = o => ({
  type_doc: o.type === 'avoir' ? 'avoir' : ['facture', 'solde'].includes(o.type) ? 'facture' : /ticket/.test(o.type) || (o.type === 'justificatif' && !/FINANCES PUBLIQUES/i.test(o.fournisseur)) ? 'ticket' : /ch.ancier/.test(o.type) ? 'echeancier' : 'autre',
  fournisseur_nom: o.fournisseur, fournisseur_tva: null, fournisseur_siren: null,
  destinataire_nom: o.destinataire || 'SHINE', destinataire_tva: null,
  num_facture: o.numero, date_facture: iso(o.date), devise: o.devise || 'EUR',
  montant_ht: o.ht_total, montant_tva: o.tva_total, montant_ttc: o.ttc_total,
  lignes: (o.lignes_tva || []).map(l => ({ designation: l.nature || o.nature || '', montant_ht: l.ht })),
  confiance: o.lisible === false ? 0.5 : 0.95, suggestion: o.nature, remarque: null,
  immatriculation: o.immatriculation || null, periode: o.periode || null, nature: o.nature || null,
});
// Attendu par fichier
const att = new Map();
for (const l of A.lignes) { const a = att.get(l.fichier) || { comptes: [], ecart: null }; a.comptes.push({ compte: l.compte, ht: l.avoir ? -l.ht : l.ht }); att.set(l.fichier, a); }
for (const [fic, , , , motif] of A.ecartees) { const a = att.get(fic) || { comptes: [], ecart: null }; a.ecart = motif; att.set(fic, a); }
const res = { identique: 0, bon_mais_a_verifier: 0, mauvais_compte: 0, ecartee_ok: 0, ecartee_rangee: 0, a_verifier_a_tort: 0 };
const lignes = [];
const vus = new Set();
for (const o of docs) {
  if (vus.has(o.fichier + o.numero)) continue; vus.add(o.fichier + o.numero);
  const a = att.get(o.fichier); if (!a) { lignes.push(['?? sans attendu', o.fichier]); continue; }
  const l = lecture(o);
  const r = classer(l, { fichier: o.fichier, texte: `${o.fournisseur} ${o.nature} ${o.remarques || ''} `.repeat(3), fournisseurs: R.fournisseurs, dictionnaire: R.dictionnaire, historique: () => [], grandLivre: GL, aujourdhui: new Date('2026-10-07') });
  const sig = v => { const m = new Map(); for (const x of v) m.set(x.compte, (m.get(x.compte) || 0) + x.ht); return [...m].map(([c, h]) => `${c}:${Math.round(h * 100) / 100}`).sort().join(' + '); };
  const sigA = sig(a.comptes.filter(x => !(o.type === 'avoir') || true)), sigR = sig((r.ventilation || []).map(v => ({ compte: v.sous_rubrique ? v.compte + ' / ' + v.sous_rubrique : v.compte, ht: (o.type === 'avoir' || v.avoir ? -1 : 1) * v.montant_ht })));
  const ecarteR = r.statut === 'ecartee';
  let cas;
  if (a.ecart && !a.comptes.length) cas = ecarteR ? 'ecartee_ok' : r.statut === 'classee' ? 'ecartee_rangee' : 'bon_mais_a_verifier';
  else if (r.statut === 'classee') cas = sigA === sigR ? 'identique' : 'mauvais_compte';
  else cas = sigA === sigR ? 'bon_mais_a_verifier' : (r.ventilation || []).length ? 'mauvais_compte' : 'a_verifier_a_tort';
  res[cas]++;
  lignes.push([cas, o.fournisseur.slice(0, 32), o.numero, 'attendu: ' + (a.comptes.length ? sigA : 'ÉCARTÉE ' + (a.ecart || '').slice(0, 60)), 'rangeur: ' + r.statut + ' ' + sigR, (r.motif || '').slice(0, 140)]);
}
console.log(JSON.stringify(res), 'sur', lignes.length);
if (DETAIL) for (const x of lignes.sort((p, q) => p[0].localeCompare(q[0]))) if (x[0] !== 'identique' && x[0] !== 'ecartee_ok') console.log(x.join(' | '));
