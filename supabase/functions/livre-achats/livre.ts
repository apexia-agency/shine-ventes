// Livre des achats du mois (comptes 60 à 62), même présentation que l'onglet « ALL LIVRES 600-620 » envoyé au cabinet
// et que le livre de septembre 2026 validé par Jérémy (07/10/2026). Construit à partir des factures du rangeur.
// Aucune dépendance réseau : ExcelJS est passé en paramètre (npm:exceljs dans la fonction, node_modules pour les essais).

export type Ventil = { compte: string; sous_rubrique?: string; montant_ht: number };
export type Facture = {
  id: number; statut: string; type_doc: string | null; date_facture: string | null; mois_comptable: string | null;
  fournisseur: string | null; num_facture: string | null; montant_ht: number | null; montant_tva: number | null; montant_ttc: number | null;
  devise: string | null; ventilation: Ventil[] | null; compte: string | null; controles: { effet: string; detail: string; n?: number }[] | null;
  motif: string | null; drive_url: string | null; fichier: string | null; regime: string | null; deductible: string | null;
  periode_debut?: string | null; periode_fin?: string | null;
};
export type Ligne = { compte: string; sous?: string; date: string; piece: string; libelle: string; debit: number; credit: number; remarque: string; fichier: string; lien: string | null };

const r2 = (n: number) => Math.round(n * 100) / 100;
const MOIS = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"];

// Charge de chaque ligne de la ventilation : mêmes règles que l'export du cabinet (factures_export_mois)
// FR : HT + part non déductible de la TVA ; autoliquidation : HT ; sans TVA : TTC ; ventilée au prorata, l'arrondi sur la plus grosse ligne.
export function charges(f: Facture): { compte: string; sous?: string; montant: number; tvaNonDed: number }[] {
  const ttc = f.montant_ttc ?? 0, ht = f.montant_ht ?? ttc - (f.montant_tva ?? 0), tva = f.montant_tva ?? 0;
  const d = (f.deductible || "OUI").toUpperCase();
  const ded = d === "NON" ? 0 : /^\d+ ?%$/.test(d) ? parseFloat(d) / 100 : 1;
  const regime = f.regime || "FR";
  const tvaNon = regime === "FR" ? r2(tva * (1 - ded)) : 0;
  const base = regime === "SANS_TVA" ? ttc : regime.startsWith("AUTOLIQ") ? ht : r2(ht + tvaNon);
  let v = (f.ventilation || []).filter((x) => x && x.compte);
  if (!v.length && f.compte) v = [{ compte: f.compte, montant_ht: ht }];
  if (!v.length) return [];
  const somme = v.reduce((s, x) => s + (+x.montant_ht || 0), 0) || 1;
  const gros = v.reduce((g, x, i) => Math.abs(+x.montant_ht) > Math.abs(+v[g].montant_ht) ? i : g, 0);
  // Une partie des lignes peut être écartée (ex. valeur des titres-restaurant) : la charge ne porte que sur la ventilation
  const part = Math.abs(somme - ht) > 0.01 && ht ? somme / ht : 1;
  const total = r2(base * part);
  let reste = total;
  const out = v.map((x, i) => { if (i === gros) return null; const m = r2((+x.montant_ht) * total / somme); reste = r2(reste - m); return { compte: x.compte, sous: x.sous_rubrique, montant: m, tvaNonDed: 0 }; });
  out[gros] = { compte: v[gros].compte, sous: v[gros].sous_rubrique, montant: r2(reste), tvaNonDed: r2(tvaNon * part) };
  return out as { compte: string; sous?: string; montant: number; tvaNonDed: number }[];
}

const jj = (iso: string | null) => iso ? `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}` : "";
const court = (s: string | null) => String(s || "").replace(/\s*\(.*$/, "").toUpperCase();

// Résultat du rapprochement bancaire (banque.ts) ; null si aucun relevé du mois n'est chargé
export type Rapprochement = {
  operations: { banque: string; date: string; libelle: string; debit: number; credit: number; categorie?: string }[];
  paiements: { facture: number; operations: { banque: string; date: string; libelle: string; debit: number }[]; mode: string }[];
  sansFacture: { banque: string; date: string; libelle: string; debit: number; categorie?: string; raison: string }[];
  nonPayees: { id: number }[];
  moisPrecedents: { operation: { banque: string; date: string; libelle: string; debit: number }; lignes: { date: string; libelle: string; debit: number }[]; approche: boolean }[];
};
type FactureRappro = { id: number; fournisseur: string | null; num_facture: string | null; date_facture: string | null; montant_ttc: number | null };

export async function construireLivre(ExcelJS: any, mois: string, factures: Facture[], libelles: Record<string, string>,
  banque: Rapprochement | null = null, facturesRappro: FactureRappro[] = []): Promise<{ nom: string; octets: Uint8Array; resume: Record<string, unknown> }> {
  const [a, m] = mois.split("-").map(Number);
  const nomMois = `${MOIS[m - 1]} ${a}`;
  const finMois = new Date(Date.UTC(a, m, 0)).toISOString().slice(0, 10);
  const rangees = factures.filter((f) => f.statut === "classee" || f.statut === "validee");
  const lignes: Ligne[] = [];
  for (const f of rangees) {
    const sens = f.type_doc === "avoir" ? -1 : 1;
    const signaux = (f.controles || []).filter((c) => c.effet === "signal").map((c) => c.detail);
    for (const c of charges(f)) {
      const rem = [c.tvaNonDed ? `dont ${c.tvaNonDed.toFixed(2).replace(".", ",")} € de TVA non déductible` : "", f.regime?.startsWith("AUTOLIQ") ? `TVA à autoliquider (${r2((f.montant_ht ?? 0) * 0.2).toFixed(2).replace(".", ",")} € à 20 %)` : "",
        f.statut === "validee" ? "validée à la main" : "", ...signaux].filter(Boolean).join(" ; ");
      lignes.push({ compte: c.compte, sous: c.sous, date: f.date_facture || "", piece: f.num_facture || "", libelle: court(f.fournisseur), debit: sens > 0 ? c.montant : 0, credit: sens < 0 ? c.montant : 0,
        remarque: rem, fichier: f.fichier || "", lien: f.drive_url });
    }
  }
  const wb = new ExcelJS.Workbook();
  const F = { name: "Arial", size: 10 }, B = { ...F, bold: true }, ENTETE = { type: "pattern", pattern: "solid", fgColor: { argb: "FF1F3A5F" } };
  const blanc = { ...B, color: { argb: "FFFFFFFF" } };
  const lm = wb.addWorksheet("Lisez-moi"); lm.getColumn(1).width = 130;

  // Livre au format du cabinet : un bloc par compte, sous-rubriques « Créer nouveau compte » sous leur compte
  const gl = wb.addWorksheet(`ALL LIVRES 600-620 ${MOIS[m - 1].toUpperCase().slice(0, 4)}`);
  gl.columns = [{ width: 12 }, { width: 20 }, { width: 8 }, { width: 34 }, { width: 13 }, { width: 9 }, { width: 13 }, { width: 13 }, { width: 70 }, { width: 70 }];
  gl.addRow([`Edition des Grands-Livres — ${nomMois} (achats, comptes 60 à 62)`]).font = { ...B, size: 12 };
  gl.addRow(["Date", "Pièce", "Journal", "Libellé", "Débit", "Lettrage", "Crédit", "Solde", "Remarque", "Fichier"]).eachCell((c: any) => { c.font = blanc; c.fill = ENTETE; });
  gl.addRow([]);
  const cle = (l: Ligne) => l.compte + (l.sous ? " / " + l.sous : "");
  const groupes = new Map<string, Ligne[]>();
  for (const l of lignes) { const k = cle(l); groupes.set(k, [...(groupes.get(k) || []), l]); }
  let totD = 0, totC = 0, parent = "";
  for (const k of [...groupes.keys()].sort()) {
    const [p, sous] = k.split(" / ");
    if (p !== parent) { gl.addRow([`Compte n°  ${p}`, libelles[p] || "(compte à libeller)"]).eachCell((c: any) => { c.font = B; }); parent = p; }
    if (sous) gl.addRow(["Créer nouveau compte", sous]).eachCell((c: any) => { c.font = B; });
    let solde = 0, d = 0, cr = 0;
    for (const l of groupes.get(k)!.sort((x, y) => x.date.localeCompare(y.date))) {
      solde = r2(solde + l.debit - l.credit); d += l.debit; cr += l.credit;
      const row = gl.addRow([l.date ? new Date(l.date + "T00:00:00Z") : "", l.piece, "ACH", l.libelle, l.debit || 0, "", l.credit || 0, solde, l.remarque, l.lien ? { text: l.fichier, hyperlink: l.lien } : l.fichier]);
      row.eachCell((c: any) => { c.font = F; });
    }
    gl.addRow(["Total ", "", "", "", r2(d), "", r2(cr), r2(d - cr)]).eachCell((c: any) => { c.font = B; });
    totD += d; totC += cr;
  }
  gl.addRow([]);
  gl.addRow([`TOTAL ${nomMois.toUpperCase()}`, "", "", "", r2(totD), "", r2(totC), r2(totD - totC)]).eachCell((c: any) => { c.font = B; });
  gl.getColumn(1).numFmt = "dd/mm/yyyy"; ["E", "G", "H"].forEach((k) => { gl.getColumn(k).numFmt = "#,##0.00"; });
  gl.views = [{ state: "frozen", ySplit: 2 }];

  // Détail par facture
  const det = wb.addWorksheet("Détail par facture");
  det.columns = [["Date", 11], ["Fournisseur", 28], ["Pièce", 20], ["Compte", 10], ["Sous-rubrique", 22], ["Libellé du compte", 32], ["HT", 11], ["TVA", 10], ["TTC", 11], ["Montant passé en charge", 13], ["Statut", 12], ["Remarque", 70], ["Fichier", 60]]
    .map(([header, width]) => ({ header, width }));
  det.getRow(1).eachCell((c: any) => { c.font = blanc; c.fill = ENTETE; c.alignment = { wrapText: true }; });
  for (const f of rangees) {
    const s = f.type_doc === "avoir" ? -1 : 1;
    const ch = charges(f);
    det.addRow([jj(f.date_facture), f.fournisseur, f.num_facture, ch.map((c) => c.compte).join(" + "), ch.map((c) => c.sous || "").filter(Boolean).join(" + "), ch.map((c) => libelles[c.compte] || "").join(" + "),
      s * (f.montant_ht ?? 0), s * (f.montant_tva ?? 0), s * (f.montant_ttc ?? 0), r2(s * ch.reduce((t, c) => t + c.montant, 0)), f.statut === "validee" ? "validée" : "classée",
      (f.controles || []).filter((c) => c.effet === "signal").map((c) => c.detail).join(" ; "), f.drive_url ? { text: f.fichier || "PDF", hyperlink: f.drive_url } : f.fichier]).eachCell((c: any) => { c.font = F; });
  }
  ["G", "H", "I", "J"].forEach((k) => { det.getColumn(k).numFmt = "#,##0.00"; }); det.views = [{ state: "frozen", ySplit: 1 }];

  // À vérifier et écartées : ce qui n'est pas dans le livre, et pourquoi
  const autres = factures.filter((f) => f.statut === "a_verifier" || f.statut === "ecartee");
  const ec = wb.addWorksheet("À vérifier et écartées");
  ec.columns = [["Statut", 14], ["Date", 11], ["Fournisseur", 28], ["Pièce", 20], ["TTC", 11], ["Motif", 100], ["Fichier", 60]].map(([header, width]) => ({ header, width }));
  ec.getRow(1).eachCell((c: any) => { c.font = blanc; c.fill = ENTETE; });
  for (const f of autres.sort((x, y) => x.statut.localeCompare(y.statut)))
    ec.addRow([f.statut === "a_verifier" ? "À vérifier" : "Écartée", jj(f.date_facture), f.fournisseur, f.num_facture, f.montant_ttc, f.motif, f.drive_url ? { text: f.fichier || "PDF", hyperlink: f.drive_url } : f.fichier]).eachCell((c: any) => { c.font = F; });
  ec.getColumn("E").numFmt = "#,##0.00";

  // Charges constatées d'avance : part de la période facturée après la fin du mois, au prorata des jours
  const cca = wb.addWorksheet("Charges constatées d'avance");
  cca.columns = [["Date", 11], ["Fournisseur", 28], ["Pièce", 20], ["Compte", 12], ["Période facturée", 24], ["Jours", 7], ["Jours après le mois", 10], ["Montant en charge", 13], ["Charge constatée d'avance", 14]].map(([header, width]) => ({ header, width }));
  cca.getRow(1).eachCell((c: any) => { c.font = blanc; c.fill = ENTETE; c.alignment = { wrapText: true }; });
  let totCca = 0;
  const jour = (s: string) => Date.parse(s + "T00:00:00Z") / 864e5;
  for (const f of rangees) {
    if (!f.periode_debut || !f.periode_fin || f.periode_fin <= finMois) continue;
    const n = jour(f.periode_fin) - jour(f.periode_debut) + 1; if (n <= 0) continue;
    const apres = Math.min(n, jour(f.periode_fin) - Math.max(jour(finMois), jour(f.periode_debut) - 1));
    const ch = charges(f), mt = r2(ch.reduce((t, c) => t + c.montant, 0)), v = r2(mt * apres / n); totCca += v;
    cca.addRow([jj(f.date_facture), f.fournisseur, f.num_facture, ch.map((c) => c.compte).join(" + "), `${jj(f.periode_debut)} au ${jj(f.periode_fin)}`, n, apres, mt, v]).eachCell((c: any) => { c.font = F; });
  }
  cca.addRow(["TOTAL", "", "", "", "", "", "", "", r2(totCca)]).eachCell((c: any) => { c.font = B; });
  ["H", "I"].forEach((k) => { cca.getColumn(k).numFmt = "#,##0.00"; });

  // Rapprochement banque : les paiements du mois face aux factures (rangeur) et au grand livre des mois précédents
  let resumeBanque: Record<string, number> | null = null;
  if (banque) {
    const rb = wb.addWorksheet("Rapprochement banque");
    rb.columns = [{ width: 24 }, { width: 11 }, { width: 7 }, { width: 13 }, { width: 60 }, { width: 80 }];
    const titre = (t: string) => { rb.addRow([]); const r = rb.addRow([t]); r.font = { ...B, size: 11 }; };
    const entete = (cols: string[]) => rb.addRow(cols).eachCell((c: any) => { c.font = blanc; c.fill = ENTETE; c.alignment = { wrapText: true }; });
    const ligne = (v: unknown[]) => rb.addRow(v).eachCell((c: any) => { c.font = F; c.alignment = { wrapText: true, vertical: "top" }; });
    const parId = new Map(facturesRappro.map((f) => [f.id, f]));
    const somme = (a: { debit: number }[]) => r2(a.reduce((s, o) => s + o.debit, 0));
    // Débits qui ne sont dans aucune des quatre premières parties : ceux qui n'ont pas de facture d'achat
    const cle = (o: { date: string; libelle: string; debit: number }) => `${o.date}|${o.libelle}|${o.debit}`;
    const vus = new Set([...banque.sansFacture.map(cle), ...banque.paiements.flatMap((p) => p.operations.map(cle)), ...banque.moisPrecedents.map((m) => cle(m.operation))]);
    const hors = banque.operations.filter((o) => o.debit > 0 && !vus.has(cle(o)));
    rb.addRow([`Rapprochement bancaire — ${nomMois}`]).font = { ...B, size: 13 };
    rb.addRow([`${banque.sansFacture.length} paiements sans facture trouvée (${somme(banque.sansFacture).toLocaleString("fr-FR", { minimumFractionDigits: 2 })} € TTC) : factures à récupérer avant d'envoyer le mois au cabinet.`]).font = { ...B, color: { argb: "FFC0392B" } };
    titre("1. Paiements sans facture (à récupérer)");
    entete(["Catégorie du plan", "Date", "Banque", "Montant TTC", "Libellé de la banque", "Piste"]);
    for (const o of banque.sansFacture) ligne([o.categorie || "", jj(o.date), o.banque, o.debit, o.libelle, o.raison]);
    titre("2. Factures payées ce mois-ci");
    entete(["Fournisseur", "Facture du", "Banque", "Montant TTC", "Libellé de la banque", "Comment"]);
    const MODE: Record<string, string> = { exact: "même montant", acomptes: "acomptes", groupe: "paiement groupé", "montant seul": "montant seul (à confirmer)" };
    for (const p of banque.paiements) { const f = parId.get(p.facture); ligne([f?.fournisseur || "", jj(f?.date_facture || null), p.operations[0].banque, f?.montant_ttc ?? null, p.operations.map((o) => `${jj(o.date)} ${o.libelle}`).join(" | "), MODE[p.mode] || p.mode]); }
    titre("3. Paiements de factures déjà passées (mois précédents)");
    entete(["Ligne(s) du livre", "Payé le", "Banque", "Montant TTC", "Libellé de la banque", "Remarque"]);
    for (const m of banque.moisPrecedents) ligne([m.lignes.map((g) => `${jj(g.date)} ${g.libelle} ${g.debit.toFixed(2)} HT`).join(" + "), jj(m.operation.date), m.operation.banque, m.operation.debit, m.operation.libelle, m.approche ? "montant à 0,5 % près" : ""]);
    titre("4. Factures du rangeur pas encore payées");
    entete(["Fournisseur", "Facture du", "", "Montant TTC", "N° de facture", ""]);
    for (const n of banque.nonPayees) { const f = parId.get(n.id); if (f) ligne([f.fournisseur, jj(f.date_facture), "", f.montant_ttc, f.num_facture, ""]); }
    titre("5. Mouvements sans facture d'achat (salaires, prêts, impôts, banque, Pleo, virements internes, compte courant Space Up)");
    entete(["Catégorie du plan", "Date", "Banque", "Montant", "Libellé de la banque", ""]);
    for (const o of hors) ligne([o.categorie || "", jj(o.date), o.banque, o.debit, o.libelle, ""]);
    rb.getColumn(4).numFmt = "#,##0.00";
    resumeBanque = { paiements_sans_facture: banque.sansFacture.length, montant_sans_facture: somme(banque.sansFacture), factures_payees: new Set(banque.paiements.map((p) => p.facture)).size, mois_precedents: banque.moisPrecedents.length };
  }

  const aVerif = autres.filter((f) => f.statut === "a_verifier").length;
  [[`SHINE · Livre des achats de ${nomMois}, comptes 60 à 62`, { ...B, size: 14 }],
   [`Fabriqué par le rangeur de factures le ${new Date().toLocaleDateString("fr-FR", { timeZone: "Europe/Paris" })}. ${rangees.length} factures, ${lignes.length} lignes, ${r2(totD - totC).toLocaleString("fr-FR", { minimumFractionDigits: 2 })} € net passés en charge.`, F],
   [aVerif ? `ATTENTION : ${aVerif} facture(s) du mois encore « à vérifier » dans le board Factures, pas comprises dans ce livre (onglet « À vérifier et écartées »).` : "Aucune facture du mois en attente de vérification.", aVerif ? { ...B, color: { argb: "FFC0392B" } } : F],
   [resumeBanque ? (resumeBanque.paiements_sans_facture ? `ATTENTION : ${resumeBanque.paiements_sans_facture} paiement(s) du mois sans facture trouvée (${resumeBanque.montant_sans_facture.toLocaleString("fr-FR", { minimumFractionDigits: 2 })} € TTC) : onglet « Rapprochement banque ».` : "Rapprochement banque : chaque paiement fournisseur du mois a sa facture.")
     : "Rapprochement banque : aucun relevé du mois chargé (déposer les CSV dans « 4 - BANQUE A DEPOSER »).", resumeBanque?.paiements_sans_facture ? { ...B, color: { argb: "FFC0392B" } } : F],
   ["", F], ["Règles", B],
   ["• Même présentation que l'onglet « ALL LIVRES 600-620 » du cabinet : un bloc par compte, sous-rubriques « Créer nouveau compte » sous leur compte parent.", F],
   ["• Montant passé en charge : HT, plus la TVA non déductible (voitures de tourisme ; 20 % de la TVA du carburant) ; TTC pour les factures sans TVA (assurances) ; HT pour l'autoliquidation (TVA indiquée en remarque).", F],
   ["• Mois du livre : mois de la facture ; une facture d'un mois déjà envoyé au cabinet et absente de son grand livre est rattachée au premier mois ouvert (remarque sur la ligne).", F],
   ["• Écartées : hors achats SHINE (véhicules de Space Up, indemnités, avis d'impôt du propriétaire, valeur des titres-restaurant) ou déjà passées par le cabinet.", F],
   ["• Charges constatées d'avance : part de la période facturée (loyers, abonnements) qui dépasse la fin du mois.", F],
  ].forEach(([t, f], i) => { const c = lm.getCell(i + 1, 1); c.value = t; c.font = f; c.alignment = { wrapText: true }; });

  const nom = `${mois}_SHINE_livre_achats_600-620.xlsx`;
  const octets = new Uint8Array(await wb.xlsx.writeBuffer());
  return { nom, octets, resume: { factures: rangees.length, lignes: lignes.length, debit: r2(totD), credit: r2(totC), a_verifier: aVerif, cca: r2(totCca), banque: resumeBanque } };
}
