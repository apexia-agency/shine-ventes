// Rapprochement bancaire des factures d'achat (rangeur V7, 07/10/2026).
// 1. Lecture des relevés : Crédit Agricole (CSV, libellés sur plusieurs lignes), CIC (CSV), PayPal (CSV activité).
// 2. Classement de chaque mouvement avec les règles du plan de trésorerie (« Règles banque » de regles.xlsx, table banque_regles) :
//    les paiements de fournisseurs doivent avoir une facture ; salaires, emprunts, impôts, recharges Pleo, virements internes, non.
// 3. Rapprochement facture ↔ paiement : même montant TTC, nom du fournisseur ou n° de facture dans le libellé, date proche ;
//    puis acomptes (2 ou 3 virements pour une facture) et paiements groupés (un virement pour 2 ou 3 factures du même fournisseur).
// Aucune dépendance réseau : testable en local (node), utilisé par la fonction livre-achats.

export type Operation = { banque: string; date: string; libelle: string; debit: number; credit: number; categorie?: string; ligne?: string };
export type RegleBanque = { ordre: number; sens: string; motif: string; onglet: string; ligne: string };
export type FactureBanque = { id: number; fournisseur: string | null; alias?: string[]; num_facture: string | null; date_facture: string | null; montant_ttc: number | null; statut: string };
export type Paiement = { facture: number; operations: Operation[]; mode: "exact" | "acomptes" | "groupe" | "montant seul" };

const r2 = (n: number) => Math.round(n * 100) / 100;
const compact = (s: string | null | undefined) => String(s ?? "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z0-9]/g, "");
const jour = (iso: string) => Date.parse(iso + "T00:00:00Z") / 864e5;
const num = (s: string | undefined) => (s && s.trim() ? Math.abs(+s.replace(/[\s\u00a0]/g, "").replace(",", ".")) : 0);
const isoFr = (s: string) => s.split("/").reverse().join("-");

// ---------- Lecture des relevés ----------
export function lireCA(texte: string): Operation[] {
  const ops: Operation[] = [];
  const re = /(\d{2}\/\d{2}\/\d{4});(?:\d{2}\/\d{2}\/\d{4};)?"([\s\S]*?)";([^;\r\n]*);([^;\r\n]*);/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(texte))) ops.push({ banque: "CA", date: isoFr(m[1]), libelle: m[2].replace(/\s+/g, " ").trim(), debit: num(m[3]), credit: num(m[4]) });
  return ops;
}
export function lireCIC(texte: string): Operation[] {
  return texte.split(/\r?\n/).map((l) => l.split(";")).filter((c) => /^\d{2}\/\d{2}\/\d{4}$/.test(c[0]) && c.length >= 5)
    .map((c) => ({ banque: "CIC", date: isoFr(c[0]), libelle: c[4].trim(), debit: num(c[2]), credit: num(c[3]) }));
}
// PayPal : seules les sorties (Net négatif) qui ne sont pas des virements vers la banque ni des remboursements clients
export function lirePayPal(texte: string): Operation[] {
  const lignes = texte.replace(/^\ufeff/, "").split(/\r?\n/).filter(Boolean);
  const champs = (l: string) => (l.match(/("([^"]|"")*"|[^,]*)(,|$)/g) || []).map((x) => x.replace(/,$/, "").replace(/^"|"$/g, "").replace(/""/g, '"'));
  const t = champs(lignes[0]); const i = (n: string) => t.indexOf(n);
  const out: Operation[] = [];
  for (const l of lignes.slice(1)) {
    const c = champs(l); const net = +String(c[i("Net")] || "0").replace(/[\s\u00a0]/g, "").replace(",", ".");
    const type = c[i("Type")] || "";
    if (!(net < 0) || /virement|remboursement|retrait|conversion|blocage|r[ée]serve/i.test(type)) continue;
    out.push({ banque: "PayPal", date: isoFr(c[i("Date")]), libelle: `${c[i("Nom")]} — ${type}`.trim(), debit: Math.abs(net), credit: 0 });
  }
  return out;
}
export function lireReleve(nom: string, texte: string): Operation[] {
  if (/paypal/i.test(nom) || /^\ufeff?"Date","Heure"/.test(texte)) return lirePayPal(texte);
  if (/Date;Date de valeur;D[ée]bit;Cr[ée]dit;Libell[ée]/i.test(texte)) return lireCIC(texte);
  return lireCA(texte);
}
export function dedoublonner(ops: Operation[]): Operation[] {
  const vus = new Set<string>();
  return ops.filter((o) => { const k = [o.banque, o.date, compact(o.libelle), o.debit, o.credit].join("|"); if (vus.has(k)) return false; vus.add(k); return true; });
}

// ---------- Classement avec les règles du plan de trésorerie ----------
// Catégories du plan dont un paiement doit correspondre à une facture d'achat
export const AVEC_FACTURE = ["ACHATS", "FRAIS GÉNÉRAUX", "LOYERS", "MARKETING", "TRANSPORT", "VÉHICULES", "SPACE UP", "AUTRES"];
export function classer(o: Operation, regles: RegleBanque[]): Operation {
  const lib = compact(o.libelle); const sens = o.debit > 0 ? "D" : "C";
  const r = [...regles].sort((a, b) => a.ordre - b.ordre).find((g) => (g.sens === "X" || g.sens === sens) && g.motif && lib.includes(compact(g.motif)));
  return { ...o, categorie: r?.onglet ?? (sens === "D" ? "À CLASSER" : "ENCAISSEMENTS"), ligne: r?.ligne ?? "" };
}
// Mouvements qui n'ont jamais de facture d'achat : compte courant avec Space Up (prêts, remboursements), prêts bancaires,
// frais de banque, impôts, remboursements de clients. Ils sortent du rapprochement (ils restent visibles dans le plan de trésorerie).
const SANS_FACTURE: [RegExp, string][] = [
  [/pr[eê]tdetr[eé]so|rbsmtcompte|remboursem?n?tcc|remboursementcc|comptecourant/, "Compte courant Space Up"],
  [/remboursementdepret|echpret|capin\d|^pr[eê]t/, "Emprunt"],
  [/^comcb|^commission|^frais|^cotisation|prelevementpostal|abonnementventeadistance|commissionventeadistance|commdechange|commdetransfert|offrecompte|factsgt/, "Banque"],
  [/directiongeneraledesfinan|tresorpublic|dgfip|impots/, "Impôts"],
  [/av0\d{6,}|rembours/, "Remboursement client"],
];
export function sansFacture(o: Operation): string | null {
  const l = compact(o.libelle).replace(/^(prelevement|virementemis|paiementparcarte)/, "");
  const s = SANS_FACTURE.find(([re]) => re.test(l) || re.test(compact(o.libelle)));
  return s ? s[1] : null;
}
// Lignes du grand livre des mois déjà envoyés au cabinet (montants HT) : un paiement peut régler une facture d'un mois précédent
export type LigneLivre = { date: string; libelle: string; debit: number };
// Nom à la banque → nom dans le livre (table banque_correspondances), ex. « Lola Poireau » → « Meemo », « Scapauto » → « Leclerc »
export type Correspondance = { banque: string; livre: string };

// Noms de fournisseurs de 3 lettres (sinon, seuls les mots de 4 lettres et plus servent à reconnaître un fournisseur)
const MARQUES = ["xpo", "dpd", "ups", "mtm", "edf", "ovh", "sfr", "gls", "tnt", "cds", "amm", "gan"];
const VIDES = ["france", "group", "groupe", "shine", "solutions", "sarl", "sasu", "services", "societe", "leasing", "finance", "bank", "succursale",
  "limited", "industrial", "agents", "generaux", "carburant", "vehicules", "societes", "reception", "logiciel", "maintenance", "frais", "postaux",
  "cabinet", "banque", "station", "utilitaire", "tourisme", "entretien", "change", "transfert", "client", "facture", "location", "loyer", "prestations", "solde", "paypal"];
// Mots d'un nom (4 lettres et plus, ou marque de 3 lettres), plus le nom collé (« PLAST'EMBAL » → « plastembal »)
const mots = (s: string | null | undefined) => {
  const colle = compact(String(s || "").split(/[|(]/)[0].split(/ - /)[0]);
  return String(s || "").replace(/\(.*?\)/g, " ").split(/[\s\-\/,.'|*]+/).map(compact)
    .filter((w) => /[a-z]/.test(w) && (w.length >= 4 || MARQUES.includes(w)) && !VIDES.includes(w))
    .concat(colle.length >= 7 && colle.length <= 24 && /[a-z]/.test(colle) ? [colle] : []);
};

// Les mots d'un même libellé ne sont calculés qu'une fois (le grand livre compte des milliers de lignes)
const cacheMots = new Map<string, string[]>();
const motsDe = (s: string | null | undefined) => { const k = String(s || ""); let v = cacheMots.get(k); if (!v) { v = mots(k); cacheMots.set(k, v); } return v; };

// Un mot du fournisseur se retrouve dans le libellé : mot entier, ou morceau d'au moins 6 lettres (« chimierecherche » dans un libellé collé)
const trouveMot = (texteCompact: string, motsLibelle: Set<string>, w: string) => motsLibelle.has(w) || (w.length >= 7 && texteCompact.includes(w));

export type SansFacture = Operation & { raison: string };
export type MoisPrecedent = { operation: Operation; lignes: LigneLivre[]; approche: boolean };

// ---------- Rapprochement ----------
export function rapprocher(factures: FactureBanque[], operations: Operation[], livre: LigneLivre[] = [], correspondances: Correspondance[] = []):
  { paiements: Paiement[]; sansFacture: SansFacture[]; nonPayees: FactureBanque[]; moisPrecedents: MoisPrecedent[] } {
  const debits = operations.filter((o) => o.debit > 0 && (o.categorie === undefined || AVEC_FACTURE.includes(o.categorie) || o.categorie === "À CLASSER") && !sansFacture(o));
  const libres = new Set(debits);
  const livreP = livre.filter((g) => g.debit > 0).map((g) => ({ g, j: jour(g.date), m: motsDe(g.libelle) }));
  const cacheOp = new Map<Operation, { l: string; m: Set<string>; j: number }>();
  // Texte du libellé bancaire, complété des noms du livre qui lui correspondent
  const corresp = (o: Operation) => { const l = compact(o.libelle); return correspondances.filter((c) => compact(c.banque) && l.includes(compact(c.banque))).map((c) => c.livre); };
  const texte = (o: Operation) => compact(o.libelle) + " " + corresp(o).map(compact).join(" ");
  const motsOp = (o: Operation) => new Set([...motsDe(o.libelle), ...corresp(o).flatMap(motsDe), ...corresp(o).map(compact)]);
  const prep = (o: Operation) => { let v = cacheOp.get(o); if (!v) { v = { l: texte(o), m: motsOp(o), j: jour(o.date) }; cacheOp.set(o, v); } return v; };
  const cacheF = new Map<FactureBanque, string[]>();
  const motsFournisseur = (f: FactureBanque) => { let v = cacheF.get(f); if (!v) { v = [f.fournisseur, ...(f.alias || [])].flatMap(motsDe).concat((f.alias || []).map(compact).filter((a) => a.length >= 4)); cacheF.set(f, v); } return v; };
  const nomOk = (f: FactureBanque, o: Operation) => { const { l, m } = prep(o); const num = compact(f.num_facture).replace(/^0+/, "");
    return motsFournisseur(f).some((w) => trouveMot(l, m, w)) || (num.length >= 4 && l.includes(num)); };
  const dans = (f: FactureBanque, o: Operation, avant = 20, apres = 120) => { if (!f.date_facture) return true; const d = jour(o.date) - jour(f.date_facture); return d >= -avant && d <= apres; };
  const paiements: Paiement[] = [];
  const aTraiter = factures.filter((f) => (f.montant_ttc ?? 0) > 0 && f.statut !== "ecartee");
  const prend = (f: FactureBanque, ops: Operation[], mode: Paiement["mode"]) => { ops.forEach((o) => libres.delete(o)); paiements.push({ facture: f.id, operations: ops, mode }); };
  // 1. Un virement, même montant, nom ou n° de facture dans le libellé ; le plus proche de la date de facture
  for (const f of aTraiter) {
    const c = [...libres].filter((o) => Math.abs(o.debit - f.montant_ttc!) < 0.011 && nomOk(f, o) && dans(f, o))
      .sort((a, b) => Math.abs(jour(a.date) - jour(f.date_facture || a.date)) - Math.abs(jour(b.date) - jour(f.date_facture || b.date)));
    if (c[0]) prend(f, [c[0]], "exact");
  }
  const payees = () => new Set(paiements.flatMap((p) => p.facture));
  // 2. Acomptes : 2 ou 3 virements au nom du fournisseur dont la somme fait le TTC
  for (const f of aTraiter.filter((x) => !payees().has(x.id))) {
    const c = [...libres].filter((o) => nomOk(f, o) && dans(f, o) && o.debit < f.montant_ttc!);
    let trouve: Operation[] | null = null;
    for (let i = 0; i < c.length && !trouve; i++) for (let j = i + 1; j < c.length && !trouve; j++) {
      if (Math.abs(c[i].debit + c[j].debit - f.montant_ttc!) < 0.011) trouve = [c[i], c[j]];
      for (let k = j + 1; k < c.length && !trouve; k++) if (Math.abs(c[i].debit + c[j].debit + c[k].debit - f.montant_ttc!) < 0.011) trouve = [c[i], c[j], c[k]];
    }
    if (trouve) prend(f, trouve, "acomptes");
  }
  // 3. Paiement groupé : un virement au nom du fournisseur = somme de 2 ou 3 factures de ce fournisseur
  const parFournisseur = new Map<string, FactureBanque[]>();
  for (const f of aTraiter.filter((x) => !payees().has(x.id))) { const k = compact(f.fournisseur); parFournisseur.set(k, [...(parFournisseur.get(k) || []), f]); }
  for (const fs of parFournisseur.values()) {
    if (fs.length < 2) continue;
    for (const o of [...libres].filter((o) => nomOk(fs[0], o))) {
      let groupe: FactureBanque[] | null = null;
      for (let i = 0; i < fs.length && !groupe; i++) for (let j = i + 1; j < fs.length && !groupe; j++) {
        if (Math.abs(fs[i].montant_ttc! + fs[j].montant_ttc! - o.debit) < 0.011) groupe = [fs[i], fs[j]];
        for (let k = j + 1; k < fs.length && !groupe; k++) if (Math.abs(fs[i].montant_ttc! + fs[j].montant_ttc! + fs[k].montant_ttc! - o.debit) < 0.011) groupe = [fs[i], fs[j], fs[k]];
      }
      if (groupe && !groupe.some((g) => payees().has(g.id))) { libres.delete(o); for (const g of groupe) paiements.push({ facture: g.id, operations: [o], mode: "groupe" }); }
    }
  }
  // 4. Montant seul : un seul virement de ce montant dans la période, sans nom reconnu (prélèvements au libellé abrégé)
  for (const f of aTraiter.filter((x) => !payees().has(x.id))) {
    const c = [...libres].filter((o) => Math.abs(o.debit - f.montant_ttc!) < 0.011 && dans(f, o, 5, 60));
    const memeMontant = aTraiter.filter((x) => !payees().has(x.id) && Math.abs((x.montant_ttc ?? 0) - f.montant_ttc!) < 0.011);
    if (c.length === 1 && memeMontant.length === 1) prend(f, c, "montant seul");
  }
  // 5. Factures des mois déjà envoyés au cabinet (grand livre, HT) : même fournisseur, TTC = HT x 1,2 (ou 1,1 / 1,055 / sans TVA),
  //    une ligne (jusqu'à 12 mois avant : factures payées très en retard), ou la somme d'un même jour ou d'un même mois
  //    (paiement d'un lot, prélèvement mensuel ; à 0,5 % près pour un mois entier, marqué « approché »)
  const moisPrecedents: MoisPrecedent[] = [];
  for (const o of [...libres]) {
    const { l, m, j } = prep(o);
    const c = livreP.filter((x) => j - x.j >= -5 && j - x.j <= 370 && x.m.some((w) => trouveMot(l, m, w))).map((x) => x.g);
    const egal = (ht: number, tol = 0.0005) => [1, 1.2, 1.1, 1.055].some((k) => Math.abs(ht * k - o.debit) <= Math.max(0.05, o.debit * tol));
    const recents = c.filter((g) => jour(o.date) - jour(g.date) <= 100);
    let lignes: LigneLivre[] | null = null, approche = false;
    const une = c.filter((g) => egal(g.debit)).sort((a, b) => b.date.localeCompare(a.date))[0];
    if (une) lignes = [une];
    const groupes = (cle: (g: LigneLivre) => string) => { const m = new Map<string, LigneLivre[]>(); for (const g of recents) m.set(cle(g), [...(m.get(cle(g)) || []), g]); return [...m.values()].filter((gs) => gs.length > 1); };
    if (!lignes) lignes = groupes((g) => g.date + "|" + compact(g.libelle).slice(0, 8)).find((gs) => egal(gs.reduce((s, g) => s + g.debit, 0))) || null;
    if (!lignes) lignes = groupes((g) => g.date.slice(0, 7) + "|" + compact(g.libelle).slice(0, 8)).find((gs) => egal(gs.reduce((s, g) => s + g.debit, 0))) || null;
    if (!lignes) { lignes = groupes((g) => g.date.slice(0, 7) + "|" + compact(g.libelle).slice(0, 8)).find((gs) => egal(gs.reduce((s, g) => s + g.debit, 0), 0.005)) || null; approche = !!lignes; }
    if (lignes) { libres.delete(o); moisPrecedents.push({ operation: o, lignes, approche }); }
  }
  // 6. Ce qui reste : fournisseur habituel (dans le livre des 4 derniers mois) → facture du mois à récupérer ; sinon fournisseur inconnu
  const sans: SansFacture[] = [...libres].sort((a, b) => a.date.localeCompare(b.date)).map((o) => {
    const { l, m, j } = prep(o);
    if (/^chequeemis/.test(compact(o.libelle))) return { ...o, raison: "chèque : retrouver le bénéficiaire et la facture" };
    const connus = livreP.filter((x) => j - x.j <= 125 && j - x.j >= -5 && x.m.some((w) => trouveMot(l, m, w))).map((x) => x.g);
    if (!connus.length) return { ...o, raison: "fournisseur absent du livre des 4 derniers mois : facture à récupérer (ou pas un achat)" };
    const ms = [...new Set(connus.map((g) => g.date.slice(0, 7)))].sort().map((m) => m.slice(5) + "/" + m.slice(2, 4));
    return { ...o, raison: `fournisseur habituel (« ${connus[0].libelle.slice(0, 30)} » dans le livre : ${ms.join(", ")}) : facture du mois à récupérer` };
  });
  const p = payees();
  return { paiements, sansFacture: sans, nonPayees: aTraiter.filter((f) => !p.has(f.id)), moisPrecedents };
}
export { r2 };
