// Moteur de classement du rangeur de factures V5 (spécification de Jérémy du 28/09/2026).
// Claude a LU la facture (Lecture) ; ici, seules les règles DÉCIDENT : fournisseur → territoire → nature → compte,
// puis les 12 contrôles d'anomalie. Règle d'or : on ne devine jamais, tout ce qui n'est pas sûr part « à vérifier ».
// Aucune dépendance ni accès réseau : testable tel quel (node --experimental-strip-types, ou Deno).

export type Ligne = { designation: string; montant_ht: number | null };
export type Lecture = {
  type_doc: "facture" | "avoir" | "proforma" | "devis" | "acompte" | "autre";
  fournisseur_nom: string; fournisseur_tva: string | null; fournisseur_siren: string | null;
  destinataire_nom: string | null; destinataire_tva: string | null;
  num_facture: string | null; date_facture: string | null; devise: string;
  montant_ht: number | null; montant_tva: number | null; montant_ttc: number | null;
  lignes: Ligne[]; confiance: number; suggestion: string | null; remarque: string | null;
};
export type Fournisseur = {
  id: number; nom: string; alias: string[]; tva_intracom: string[]; siren: string[];
  compte: string | null; regime_tva: string | null; territoire: "FR" | "INTRA" | "IMPORT" | null; nature: string | null;
  mode: "mono" | "eclater"; eclatement: { mots: string[]; compte: string; libelle: string }[] | null;
  statut: "ok" | "a_valider" | "hors"; motifs: string[];
};
export type Nature = { nature: string; ordre: number; mots: string[]; compte_fr: string | null; compte_intra: string | null; compte_import: string | null };
export type Contexte = {
  fichier: string;                 // nom (et dossier) du fichier déposé
  texte: string | null;            // couche texte du PDF ; null ou vide = scan
  fournisseurs: Fournisseur[];
  dictionnaire: Nature[];
  // factures déjà rangées du même fournisseur (pour les doublons et la règle des scans)
  historique: (f: Fournisseur) => { num_facture: string | null; montant_ttc: number | null; date_facture: string | null }[];
  aujourdhui?: Date;
};
export type Controle = { n: number; controle: string; effet: "bloquant" | "signal"; detail: string };
export type Imputation = { compte: string; libelle: string; montant_ht: number; lignes: string[] };
export type Resultat = {
  statut: "classee" | "a_verifier";
  fournisseur: Fournisseur | null;
  territoire: string | null; regime_tva: string | null;
  compte: string | null;           // compte unique (mono-nature), sinon null
  ventilation: Imputation[];
  controles: Controle[];
  motif: string | null;
  nom_range: string;               // AAAA-MM-JJ_FOURNISSEUR_NUMERO_TTC.pdf
  dossier: string;                 // « 2 - CLASSEES/2025-2026/2026-09 » ou « 3 - A VERIFIER »
};

// Texte comparable : majuscules, sans accents, ponctuation → espaces
export const norm = (s: string | null | undefined) =>
  ` ${String(s ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase().replace(/[^A-Z0-9]+/g, " ").trim()} `;
const ident = (s: string | null | undefined) => String(s ?? "").toUpperCase().replace(/[^A-Z0-9]/g, "");
// Mot entier ; un mot-clé avec un chiffre (« 1000 L ») se trouve aussi collé (« 1000L »)
const contientMot = (texte: string, mot: string) => {
  const m = norm(mot);
  if (!m.trim()) return false;
  if (texte.includes(m)) return true;
  return /\d/.test(m) && texte.replace(/(\d) (?=[A-Z])/g, "$1").includes(m.replace(/(\d) (?=[A-Z])/g, "$1"));
};
const r2 = (n: number) => Math.round(n * 100) / 100;

const SHINE = { siren: "888920071", tva: "FR44888920071", noms: ["SHINE", "SHEIN"] }; // « SAS SHEIN » : faute de la SCI CMD
const AUTRES_SOCIETES = [{ nom: "Space Up", siren: "915023501", tva: "FR03915023501", mots: ["SPACE UP", "SPACEUP"] },
  { nom: "Nexus Lab", siren: "", tva: "", mots: ["NEXUS LAB"] }];

// 1. Identifier le fournisseur : n° de TVA ou SIREN d'abord (sûrs), puis nom lu et nom du fichier
export function trouverFournisseur(l: Lecture, ctx: Contexte): { f: Fournisseur | null; comment: string } {
  const tva = ident(l.fournisseur_tva);
  const siren = ident(l.fournisseur_siren).slice(0, 9) || (tva.startsWith("FR") && tva.length === 13 ? tva.slice(4) : "");
  if (tva) { const f = ctx.fournisseurs.find((x) => x.tva_intracom.some((t) => ident(t) === tva)); if (f) return { f, comment: "n° de TVA" }; }
  if (siren) { const f = ctx.fournisseurs.find((x) => x.siren.includes(siren)); if (f) return { f, comment: "SIREN" }; }
  // Nom : l'alias le plus long trouvé en mots entiers dans le nom lu, sinon dans le nom du fichier
  const essais: [string, string][] = [[norm(l.fournisseur_nom), "nom sur la facture"], [norm(ctx.fichier.split("/").pop()), "nom du fichier"]];
  for (const [texte, comment] of essais) {
    let meilleur: { f: Fournisseur; long: number }[] = [];
    for (const f of ctx.fournisseurs) {
      const noms = [...f.alias, f.nom.replace(/\(.*?\)|\?/g, "")];
      for (const a of noms) {
        const m = norm(a); if (m.trim().length < 3 || !texte.includes(m)) continue;
        const long = m.trim().length;
        if (!meilleur.length || long > meilleur[0].long) meilleur = [{ f, long }];
        else if (long === meilleur[0].long && !meilleur.some((x) => x.f.id === f.id)) meilleur.push({ f, long });
      }
    }
    if (meilleur.length === 1) return { f: meilleur[0].f, comment };
    if (meilleur.length > 1) return { f: null, comment: `ambigu (${meilleur.map((x) => x.f.nom).join(" / ")})` };
  }
  return { f: null, comment: "inconnu" };
}

// Ligne de facture → nature et compte, selon les mots-clés propres au fournisseur ou le dictionnaire produit
export function naturerLigne(designation: string, f: Fournisseur, ctx: Contexte): { compte: string | null; libelle: string; motif?: string } | null {
  const t = norm(designation);
  if (f.eclatement?.length) {
    const e = f.eclatement.find((r) => r.mots.some((m) => contientMot(t, m)));
    return e ? { compte: e.compte, libelle: e.libelle } : null;
  }
  const n = [...ctx.dictionnaire].sort((a, b) => a.ordre - b.ordre).find((d) => d.mots.some((m) => contientMot(t, m)));
  if (!n) return null;
  const compte = f.territoire === "IMPORT" ? n.compte_import : f.territoire === "INTRA" ? n.compte_intra : n.compte_fr;
  // Une seule chimie est importée : la cire Express. Toute autre chimie sur une facture import est une anomalie.
  if (f.territoire === "IMPORT" && n.nature === "MP_CHIMIE") return { compte: null, libelle: n.nature, motif: "chimie importée qui n'est pas de la cire" };
  return { compte, libelle: n.nature, motif: compte ? undefined : `pas de compte ${n.nature} en ${f.territoire} (compte à créer)` };
}

const ttcDuNom = (fichier: string) => {
  const m = /(\d+(?:[.,]\d+)?)\s*€?\s*TTC/i.exec(fichier.split("/").pop() || "");
  return m ? parseFloat(m[1].replace(",", ".")) : null;
};
const exerciceDe = (iso: string) => { const [a, m] = iso.split("-").map(Number); return m >= 10 ? `${a}-${a + 1}` : `${a - 1}-${a}`; };
const slug = (s: string, max = 30) => norm(s).trim().replace(/ /g, "-").slice(0, max).replace(/-+$/, "") || "SANS";

export function classer(l: Lecture, ctx: Contexte): Resultat {
  const C: Controle[] = [];
  const bloque = (n: number, controle: string, detail: string) => C.push({ n, controle, effet: "bloquant", detail });
  const signale = (n: number, controle: string, detail: string) => C.push({ n, controle, effet: "signal", detail });
  const texte = norm(ctx.texte);
  const aTexte = (ctx.texte ?? "").trim().length > 50;
  const { montant_ht: ht, montant_tva: tva, montant_ttc: ttc } = l;

  // Lecture elle-même
  if (!l.date_facture || !/^\d{4}-\d{2}-\d{2}$/.test(l.date_facture)) bloque(0, "Lecture", "date illisible");
  if (ttc == null) bloque(0, "Lecture", "montant TTC illisible");
  if (ht != null && tva != null && ttc != null && Math.abs(ht + tva - ttc) > 0.05) bloque(0, "Lecture", `HT + TVA ≠ TTC (${r2(ht + tva)} / ${ttc})`);
  if (l.confiance < 0.8) bloque(0, "Lecture", `lecture peu sûre (confiance ${l.confiance})`);

  // 1. Devise
  if ((l.devise || "EUR").toUpperCase() !== "EUR") bloque(1, "Devise différente de l'euro", `facture en ${l.devise} : conversion à faire à la main`);
  // 5. Pas une facture
  if (l.type_doc === "proforma" || l.type_doc === "devis" || /ORDER CONFIRMATION|QUOTATION| PRO ?FORMA /.test(texte))
    bloque(5, "Document qui n'est pas une facture", l.type_doc === "facture" || l.type_doc === "avoir" ? "mention proforma / devis / confirmation de commande dans le texte" : `document lu comme « ${l.type_doc} »`);
  if (l.type_doc === "autre") bloque(5, "Document qui n'est pas une facture", "ni facture ni avoir");
  // 6. Acompte
  // Le mot seul ne suffit pas : les conditions générales de vente parlent souvent d'acompte (Plast'Embal, 29/09)
  if (l.type_doc === "acompte" || / FACTURE D ACOMPTE | DEMANDE D ACOMPTE | DEPOSIT INVOICE | PREPAYMENT INVOICE | ADVANCE PAYMENT | BALANCE 70 | 30 DEPOSIT /.test(texte))
    bloque(6, "Acompte", "un acompte n'est pas une charge : compte 4091");
  // 9. Destinataire
  const dest = norm(`${l.destinataire_nom ?? ""} ${l.destinataire_tva ?? ""}`);
  const autre = AUTRES_SOCIETES.find((s) => s.mots.some((m) => dest.includes(norm(m))) || (s.siren && dest.includes(s.siren)));
  const estShine = SHINE.noms.some((n) => dest.includes(` ${n} `)) || dest.includes(SHINE.siren) || ident(l.destinataire_tva) === SHINE.tva;
  if (autre && !estShine) bloque(9, "Facture au nom d'une autre société", `adressée à ${autre.nom}`);
  else if (!estShine) bloque(9, "Facture au nom d'une autre société", `destinataire non reconnu : « ${(l.destinataire_nom || "absent").slice(0, 60)} »`);

  // 7. Fournisseur
  const { f, comment } = trouverFournisseur(l, ctx);
  const ventilation: Imputation[] = [];
  let compte: string | null = null;
  if (!f) bloque(7, "Fournisseur inconnu", `« ${l.fournisseur_nom} » : ${comment}`);
  else if (f.statut === "hors") bloque(7, "Fournisseur hors périmètre", `${f.nom} : ${f.motifs.join(" ; ")}`);
  else if (f.statut === "a_valider") bloque(7, "Règle du fournisseur pas encore validée", `${f.nom} : ${f.motifs.join(" ; ")}`);
  else {
    // 2. TVA facturée sur de l'import ou de l'intracommunautaire
    if (f.territoire && f.territoire !== "FR" && (tva ?? 0) > 0.01) bloque(2, "TVA présente sur une facture IMPORT ou INTRA", `${tva} € de TVA alors que ${f.nom} est en ${f.territoire}`);
    if (f.mode === "mono") {
      if (!f.compte) bloque(7, "Compte manquant", `${f.nom} n'a pas de compte (compte à créer ?)`);
      else { compte = f.compte; if (ht != null) ventilation.push({ compte, libelle: f.nature || f.nom, montant_ht: r2(ht), lignes: [] }); }
    } else {
      // 3-4. Éclatement ligne par ligne (8 : ligne non reconnue)
      const lignes = l.lignes.filter((x) => x.montant_ht != null && Math.abs(x.montant_ht) > 0.004);
      if (!lignes.length) bloque(4, "Somme des lignes ≠ total facture", "facture à éclater mais aucune ligne lue");
      for (const x of lignes) {
        const n = naturerLigne(x.designation, f, ctx);
        if (!n) { bloque(8, "Ligne non reconnue par le dictionnaire", `« ${x.designation.slice(0, 70)} » (${x.montant_ht} €)`); continue; }
        if (!n.compte) { bloque(8, "Ligne sans compte", `« ${x.designation.slice(0, 50)} » : ${n.motif}`); continue; }
        const i = ventilation.find((v) => v.compte === n.compte);
        if (i) { i.montant_ht = r2(i.montant_ht + x.montant_ht!); i.lignes.push(x.designation); }
        else ventilation.push({ compte: n.compte, libelle: n.libelle, montant_ht: r2(x.montant_ht!), lignes: [x.designation] });
      }
      const somme = r2(lignes.reduce((s, x) => s + (x.montant_ht || 0), 0));
      if (lignes.length && ht != null && Math.abs(somme - ht) > 0.01) bloque(4, "Somme des lignes ≠ total facture", `lignes ${somme} € / total HT ${ht} €`);
    }
    // 11. Doublon
    const hist = ctx.historique(f);
    if (l.num_facture && hist.some((h) => ident(h.num_facture) === ident(l.num_facture)))
      bloque(11, "Doublon", `${f.nom} n° ${l.num_facture} est déjà rangée`);
    // 12. Scan : lu par Claude seulement si le montant est celui de la facture précédente (règle de Robin, 29/09)
    if (!aTexte) {
      const prec = hist.filter((h) => h.date_facture && h.date_facture < (l.date_facture || "9999")).sort((a, b) => (b.date_facture! < a.date_facture! ? -1 : 1))[0];
      if (prec && prec.montant_ttc != null && ttc != null && Math.abs(prec.montant_ttc - ttc) < 0.01)
        signale(12, "PDF sans couche texte (scan)", `scan lu par Claude, même montant que la facture précédente (${prec.date_facture})`);
      else bloque(12, "PDF sans couche texte (scan)", prec ? `montant différent de la facture précédente (${prec.montant_ttc} €)` : "pas de facture précédente à comparer");
    }
  }
  if (!f && !aTexte) bloque(12, "PDF sans couche texte (scan)", "scan d'un fournisseur inconnu");

  // 3. TTC du nom de fichier (convention SHINE) : un « TTC » à TVA 0 % saisi comme HT
  const ttcNom = ttcDuNom(ctx.fichier);
  if (ttcNom != null && ttc != null && (l.devise || "EUR") === "EUR" && Math.abs(ttcNom - ttc) > Math.max(1, ttc * 0.01)) {
    const facteur = [1.2, 1.1, 1.055].find((k) => Math.abs(ttc * k - ttcNom) < 1 || Math.abs(ttcNom * k - ttc) < 1);
    bloque(3, "Montant TTC saisi comme HT", `nom du fichier ${ttcNom} € / facture ${ttc} €${facteur ? ` (écart ×${facteur})` : ""}`);
  }
  // 10. Facture antérieure à l'exercice en cours (signalement)
  const auj = ctx.aujourdhui ?? new Date();
  const debutExo = `${auj.getMonth() >= 9 ? auj.getFullYear() : auj.getFullYear() - 1}-10-01`;
  if (l.date_facture && l.date_facture < debutExo) signale(10, "Facture antérieure à l'exercice", `datée du ${l.date_facture}, avant le ${debutExo}`);
  if (l.remarque) signale(0, "Remarque de la lecture", l.remarque);

  const bloquants = C.filter((c) => c.effet === "bloquant");
  const statut = bloquants.length ? "a_verifier" : "classee";
  const date = l.date_facture && /^\d{4}-\d{2}-\d{2}$/.test(l.date_facture) ? l.date_facture : null;
  const nom_range = `${date || "SANS-DATE"}_${slug(f?.nom.replace(/\(.*?\)/g, "") || l.fournisseur_nom || "INCONNU", 25)}_${slug(l.num_facture || "SANS-NUM", 25)}_${ttc != null ? ttc.toFixed(2) : "0.00"}${l.type_doc === "avoir" ? "_AVOIR" : ""}.pdf`;
  const dossier = statut === "classee" && date ? `2 - CLASSEES/${exerciceDe(date)}/${date.slice(0, 7)}` : "3 - A VERIFIER";
  return {
    statut, fournisseur: f, territoire: f?.territoire ?? null, regime_tva: f?.regime_tva ?? null, compte,
    ventilation, controles: C, motif: bloquants.map((c) => c.detail).join(" ; ") || null, nom_range, dossier,
  };
}
