// Moteur de classement du rangeur de factures V6 (V5 : spécification de Jérémy du 28/09/2026 ; V6 : calé le 07/10/2026 sur le
// livre des achats de septembre 2026 validé par Jérémy — règles par contenu, sous-rubriques, écarts automatiques, grand livre).
// Claude a LU la facture (Lecture) ; ici, seules les règles DÉCIDENT : fournisseur → territoire → nature → compte,
// puis les 12 contrôles d'anomalie. Règle d'or : on ne devine jamais, tout ce qui n'est pas sûr part « à vérifier ».
// Aucune dépendance ni accès réseau : testable tel quel (node --experimental-strip-types, ou Deno).

export type Ligne = { designation: string; montant_ht: number | null };
export type Lecture = {
  type_doc: "facture" | "avoir" | "proforma" | "devis" | "acompte" | "ticket" | "echeancier" | "autre";
  fournisseur_nom: string; fournisseur_tva: string | null; fournisseur_siren: string | null;
  destinataire_nom: string | null; destinataire_tva: string | null;
  num_facture: string | null; date_facture: string | null; devise: string;
  montant_ht: number | null; montant_tva: number | null; montant_ttc: number | null;
  lignes: Ligne[]; confiance: number; suggestion: string | null; remarque: string | null;
  immatriculation?: string | null;  // plaque du véhicule si la facture en porte une (V6)
  periode_debut?: string | null; periode_fin?: string | null; // période facturée (loyer, abonnement), AAAA-MM-JJ (V6)
};
// Règle de contenu d'un fournisseur (V6) : la première qui s'applique décide. « ligne » : ligne par ligne (désignation), sinon
// toute la facture (nom du fichier, plaque, suggestion, désignations). Effet : un compte (et sa sous-rubrique), écarter, ou à vérifier.
export type Regle = { si: string[]; ligne?: boolean; compte?: string; sous_rubrique?: string; tva_deductible?: string; ecarter?: string; verifier?: string; note?: string };
export type Fournisseur = {
  id: number; nom: string; alias: string[]; tva_intracom: string[]; siren: string[];
  compte: string | null; regime_tva: string | null; territoire: "FR" | "INTRA" | "IMPORT" | null; nature: string | null;
  mode: "mono" | "eclater"; eclatement: { mots: string[]; compte: string; libelle: string }[] | null;
  statut: "ok" | "a_valider" | "hors"; motifs: string[];
  sous_rubrique?: string | null; tva_deductible?: string | null; regles?: Regle[] | null; // V6
};
export type Nature = { nature: string; ordre: number; mots: string[]; compte_fr: string | null; compte_intra: string | null; compte_import: string | null };
export type Contexte = {
  fichier: string;                 // nom (et dossier) du fichier déposé
  texte: string | null;            // couche texte du PDF ; null ou vide = scan
  fournisseurs: Fournisseur[];
  dictionnaire: Nature[];
  // factures déjà rangées du même fournisseur (pour les doublons et la règle des scans)
  historique: (f: Fournisseur) => { num_facture: string | null; montant_ttc: number | null; date_facture: string | null; statut?: string }[];
  // lignes du grand livre déjà passé par le cabinet (V6) : une facture en retard déjà saisie est écartée
  grandLivre?: { compte: string; date: string; piece: string | null; libelle: string; debit: number }[];
  // dernier mois déjà envoyé au cabinet (AAAA-MM) : une facture plus ancienne est rattachée au mois suivant (V6.1)
  dernierMoisClos?: string | null;
  aujourdhui?: Date;
};
export type Controle = { n: number; controle: string; effet: "bloquant" | "signal"; detail: string };
export type Imputation = { compte: string; sous_rubrique?: string; libelle: string; montant_ht: number; lignes: string[] };
export type Resultat = {
  statut: "classee" | "a_verifier" | "ecartee";
  fournisseur: Fournisseur | null;
  territoire: string | null; regime_tva: string | null;
  tva_deductible: string | null;   // taux propre à la facture (règle de contenu) sinon celui du fournisseur
  compte: string | null;           // compte unique (mono-nature), sinon null
  ventilation: Imputation[];
  controles: Controle[];
  motif: string | null;
  mois_comptable: string | null;   // AAAA-MM du livre où la facture est passée (mois de la facture, ou premier mois ouvert) (V6.1)
  nom_range: string;               // AAAA-MM-JJ_COMPTE_FOURNISSEUR_NUMERO_HT_TTC.pdf (V6.1)
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
  if (texte.includes(m) || texte.includes(m.trimEnd() + "S ")) return true; // pluriel : « étiquettes », « flacons »
  if (!/\d/.test(m)) return false;
  if (texte.replace(/(\d) (?=[A-Z])/g, "$1").includes(m.replace(/(\d) (?=[A-Z])/g, "$1"))) return true;
  // Plaque ou référence écrite sans séparateurs (« GR171EW » pour « GR-171-EW ») : comparaison sans espaces (V6)
  return m.trim().length >= 5 && texte.replace(/ /g, "").includes(m.replace(/ /g, ""));
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

// V6 : facture déjà passée par le cabinet (grand livre), arrivée en retard dans le dossier
export function dejaAuGrandLivre(l: Lecture, f: Fournisseur, ctx: Contexte) {
  if (!ctx.grandLivre?.length) return null;
  const chiffres = (s: string | null | undefined) => ident(s).replace(/\D/g, "");
  const num = chiffres(l.num_facture);
  const jour = (d: string) => Date.parse(d) / 864e5;
  const montants = [l.montant_ht, ...l.lignes.map((x) => x.montant_ht)].filter((x): x is number => x != null && x > 0);
  const noms = [...f.alias, f.nom.replace(/\(.*?\)|\?/g, "")].map((a) => norm(a)).filter((a) => a.trim().length >= 3);
  return ctx.grandLivre.find((g) => (num.length >= 4 && chiffres(g.piece) === num && noms.some((a) => norm(g.libelle).includes(a))) ||
    (l.date_facture && montants.some((m) => Math.abs(g.debit - m) < 0.011) && Math.abs(jour(g.date) - jour(l.date_facture)) <= 10 && noms.some((a) => norm(g.libelle).includes(a)))) || null;
}

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
  // V6 : ticket de caisse (carburant, péage, petites fournitures) et échéancier (assurance, prêt) sont des pièces acceptées
  if (l.type_doc === "ticket") signale(5, "Ticket de caisse", "ticket, pas une facture");
  // 14. Document annuel ou pluriannuel (V6.1, Jérémy 07/10/2026) : à répartir sur les mois, toujours vérifié par un humain
  const jours = l.periode_debut && l.periode_fin ? (Date.parse(l.periode_fin) - Date.parse(l.periode_debut)) / 864e5 : 0;
  const motsAnnuels = / ANNUEL| ANNUAL | ECHEANCIER | 12 MOIS | EXERCICE DU | COTISATION ANNUELLE /.test(norm(`${l.suggestion ?? ""} ${ctx.fichier} ${l.lignes.map((x) => x.designation).join(" ")}`));
  if (jours > 62 || l.type_doc === "echeancier" || motsAnnuels)
    bloque(14, "Document annuel", jours > 62 ? `période du ${l.periode_debut} au ${l.periode_fin} (${Math.round(jours / 30.4)} mois) : à répartir sur les mois concernés` : "échéancier ou document annuel : à répartir sur les mois concernés");
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
  let ecarte: string | null = null;           // V6 : motif d'écart automatique (hors achats SHINE, déjà saisie…)
  let doublon = false;                        // V6.1 : nom du fichier préfixé DOUBLON_
  let tvaDed: string | null = f?.tva_deductible ?? null;
  // Texte de toute la facture pour les règles de contenu : nom du fichier, plaque, suggestion, désignations, période
  const tout = norm([ctx.fichier.split("/").pop(), l.immatriculation, l.suggestion, l.remarque, l.fournisseur_nom, ...l.lignes.map((x) => x.designation)].join(" ") + " " + (ctx.texte ?? "").slice(0, 4000));
  const regleDe = (t: string, ligne: boolean) => (f?.regles || []).find((g) => !!g.ligne === ligne && g.si.some((m) => contientMot(t, m)));
  const ajoute = (cpt: string, sous: string | undefined, libelle: string, montant: number, designation?: string) => {
    const i = ventilation.find((v) => v.compte === cpt && (v.sous_rubrique || "") === (sous || ""));
    if (i) { i.montant_ht = r2(i.montant_ht + montant); if (designation) i.lignes.push(designation); }
    else ventilation.push({ compte: cpt, ...(sous ? { sous_rubrique: sous } : {}), libelle, montant_ht: r2(montant), lignes: designation ? [designation] : [] });
  };
  if (!f) bloque(7, "Fournisseur inconnu", `« ${l.fournisseur_nom} » : ${comment}`);
  else if (f.statut === "hors") bloque(7, "Fournisseur hors périmètre", `${f.nom} : ${f.motifs.join(" ; ")}`);
  else if (f.statut === "a_valider") bloque(7, "Règle du fournisseur pas encore validée", `${f.nom} : ${f.motifs.join(" ; ")}`);
  else {
    // 2. TVA facturée sur de l'import ou de l'intracommunautaire
    if (f.territoire && f.territoire !== "FR" && (tva ?? 0) > 0.01) bloque(2, "TVA présente sur une facture IMPORT ou INTRA", `${tva} € de TVA alors que ${f.nom} est en ${f.territoire}`);
    // V6 : règle de contenu sur toute la facture (plaque, mot du fichier…), puis règles ligne par ligne
    const gf = regleDe(tout, false);
    const reglesLigne = (f.regles || []).some((g) => g.ligne);
    if (gf?.ecarter) ecarte = gf.ecarter;
    else if (gf?.verifier) bloque(7, "Cas à trancher", `${f.nom} : ${gf.verifier}`);
    else if (gf?.compte || (f.mode === "mono" && !reglesLigne)) {
      const cpt = gf?.compte || f.compte, sous = gf ? gf.sous_rubrique : f.sous_rubrique || undefined;
      if (gf?.tva_deductible) tvaDed = gf.tva_deductible;
      if (gf?.note) signale(0, "Règle", gf.note);
      if (!cpt) bloque(7, "Compte manquant", (f.regles || []).length ? `${f.nom} : aucune règle ne reconnaît cette facture (véhicule, nature ?)` : `${f.nom} n'a pas de compte (compte à créer ?)`);
      else { compte = cpt; if (ht != null) ajoute(cpt, sous || undefined, f.nature || f.nom, ht); }
    } else {
      // 3-4. Éclatement ligne par ligne (8 : ligne non reconnue)
      let lignes = l.lignes.filter((x) => x.montant_ht != null && Math.abs(x.montant_ht) > 0.004);
      // Avoir : les totaux sont lus en positif, les lignes souvent en négatif → même sens que le total (Prodhynet, 29/09)
      if (l.type_doc === "avoir" && lignes.reduce((s, x) => s + x.montant_ht!, 0) < 0) lignes = lignes.map((x) => ({ ...x, montant_ht: -x.montant_ht! }));
      // Une facture sans détail de lignes : une seule ligne au total HT, avec le texte de la facture
      if (!lignes.length && reglesLigne && ht != null) lignes = [{ designation: [l.suggestion, ...l.lignes.map((x) => x.designation)].filter(Boolean).join(" ") || f.nom, montant_ht: ht }];
      if (!lignes.length) bloque(4, "Somme des lignes ≠ total facture", "facture à éclater mais aucune ligne lue");
      let ecartees = 0;
      for (const x of lignes) {
        if (reglesLigne) {
          const g = regleDe(norm(x.designation), true);
          if (g?.ecarter) { ecartees += x.montant_ht!; signale(0, "Ligne écartée", `« ${x.designation.slice(0, 50)} » (${x.montant_ht} €) : ${g.ecarter}`); continue; }
          if (g?.verifier) { bloque(8, "Ligne à trancher", `« ${x.designation.slice(0, 50)} » : ${g.verifier}`); continue; }
          const cpt = g?.compte || f.compte;
          if (!cpt) { bloque(8, "Ligne non reconnue", `« ${x.designation.slice(0, 70)} » (${x.montant_ht} €)`); continue; }
          if (g?.tva_deductible) tvaDed = g.tva_deductible;
          ajoute(cpt, g ? g.sous_rubrique : f.sous_rubrique || undefined, f.nature || f.nom, x.montant_ht!, x.designation);
          continue;
        }
        const n = naturerLigne(x.designation, f, ctx);
        if (!n) { bloque(8, "Ligne non reconnue par le dictionnaire", `« ${x.designation.slice(0, 70)} » (${x.montant_ht} €)`); continue; }
        if (!n.compte) { bloque(8, "Ligne sans compte", `« ${x.designation.slice(0, 50)} » : ${n.motif}`); continue; }
        ajoute(n.compte, undefined, n.libelle, x.montant_ht!, x.designation);
      }
      const somme = r2(lignes.reduce((s, x) => s + (x.montant_ht || 0), 0));
      if (lignes.length && ht != null && Math.abs(somme - ht) > 0.01) bloque(4, "Somme des lignes ≠ total facture", `lignes ${somme} € / total HT ${ht} €`);
      if (lignes.length && Math.abs(ecartees - somme) < 0.01) ecarte = "toutes les lignes sont hors achats";
      if (ventilation.length === 1) compte = ventilation[0].compte;
    }
    // V6 : litige client (mot « litige » mis par SHINE dans le libellé ou le nom du fichier) → 61530000 « Entretien litige client »
    if (!ecarte && / LITIGE /.test(norm(`${ctx.fichier} ${l.suggestion ?? ""}`)) && ht != null) {
      ventilation.splice(0, ventilation.length, { compte: "61530000", libelle: "Entretien litige client", montant_ht: r2(ht), lignes: [] }); compte = "61530000";
      signale(0, "Litige client", "facture d'un tiers prise en charge pour un litige client");
    }
    // 11. Doublon (V6.1) : même n° chez le même fournisseur, quel que soit le mois ; ou même TTC à 5 jours près (n° absent ou différent)
    const hist = ctx.historique(f).filter((h) => h.statut !== "ecartee");
    const memeNum = l.num_facture ? hist.find((h) => ident(h.num_facture) === ident(l.num_facture)) : null;
    const memeMontant = !memeNum && ttc != null && l.date_facture ? hist.find((h) => h.montant_ttc != null && Math.abs(h.montant_ttc - ttc) < 0.01 && h.date_facture &&
      Math.abs(Date.parse(h.date_facture) - Date.parse(l.date_facture!)) <= 5 * 864e5) : null;
    if (memeNum) { doublon = true; bloque(11, "Doublon", `${f.nom} n° ${l.num_facture} est déjà dans le rangeur (facture du ${memeNum.date_facture ?? "?"})`); }
    else if (memeMontant) { doublon = true; bloque(11, "Doublon possible", `${f.nom} : même montant TTC (${ttc} €) que la facture du ${memeMontant.date_facture}${memeMontant.num_facture ? " n° " + memeMontant.num_facture : ""}`); }
    // V6 : déjà passée par le cabinet (facture arrivée en retard) : même n° de pièce, ou même fournisseur, même HT, à 10 jours près
    const gl = dejaAuGrandLivre(l, f, ctx);
    if (gl) ecarte = `déjà dans le grand livre (compte ${gl.compte}, pièce ${gl.piece || "–"}, ${gl.date})`;
    // 12. Scan : lu par Claude seulement si le montant est celui de la facture précédente (règle de Robin, 29/09)
    if (!aTexte) {
      const prec = hist.filter((h) => (h.statut === "classee" || h.statut === "validee") && h.date_facture && h.date_facture < (l.date_facture || "9999")).sort((a, b) => (b.date_facture! < a.date_facture! ? -1 : 1))[0];
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
  // V6 : un écart décidé par une règle (hors achats SHINE, déjà saisie) l'emporte : rien à comptabiliser, le motif dit pourquoi
  if (ecarte) C.push({ n: 13, controle: "Écartée par une règle", effet: "signal", detail: ecarte });
  const statut = ecarte ? "ecartee" : bloquants.length ? "a_verifier" : "classee";
  const date = l.date_facture && /^\d{4}-\d{2}-\d{2}$/.test(l.date_facture) ? l.date_facture : null;
  // V6.1 : une facture d'un mois déjà envoyé au cabinet (et absente de son grand livre) passe dans le premier mois ouvert
  let mois_comptable = date ? date.slice(0, 7) : null;
  if (mois_comptable && ctx.dernierMoisClos && mois_comptable <= ctx.dernierMoisClos && statut !== "ecartee") {
    const [a, m] = ctx.dernierMoisClos.split("-").map(Number);
    mois_comptable = m === 12 ? `${a + 1}-01` : `${a}-${String(m + 1).padStart(2, "0")}`;
    C.push({ n: 15, controle: "Mois déjà envoyé au cabinet", effet: "signal", detail: `facture du ${date}, absente du grand livre : rattachée à ${mois_comptable}` });
  }
  // Nom du fichier rangé : date, compte (et sous-rubrique), fournisseur, n°, HT et TTC — l'essentiel lisible sans ouvrir le PDF
  const v0 = [...ventilation].sort((a, b) => Math.abs(b.montant_ht) - Math.abs(a.montant_ht))[0];
  const cpt = statut === "classee" && v0 ? v0.compte + (v0.sous_rubrique ? "-" + slug(v0.sous_rubrique, 24) : "") + (ventilation.length > 1 ? "-ETC" : "") : statut === "ecartee" ? "HORS" : "A-VERIFIER";
  const prefixe = statut === "ecartee" ? "ECARTEE_" : doublon ? "DOUBLON_" : "";
  const euros = (x: number | null) => x == null ? "0.00" : x.toFixed(2);
  const nom_range = `${prefixe}${date || "SANS-DATE"}_${cpt}_${slug(f?.nom.replace(/\(.*?\)/g, "") || l.fournisseur_nom || "INCONNU", 25)}_${slug(l.num_facture || "SANS-NUM", 25)}_${euros(ht)}HT_${euros(ttc)}TTC${l.type_doc === "avoir" ? "_AVOIR" : ""}.pdf`;
  const dossier = statut === "classee" && mois_comptable ? `2 - CLASSEES/${exerciceDe(mois_comptable + "-01")}/${mois_comptable}` : "3 - A VERIFIER"; // écartée : à côté des « à vérifier », nom préfixé
  return {
    statut, fournisseur: f, territoire: f?.territoire ?? null, regime_tva: f?.regime_tva ?? null, tva_deductible: tvaDed, compte,
    ventilation: ecarte ? [] : ventilation, controles: C, motif: ecarte || bloquants.map((c) => c.detail).join(" ; ") || null, mois_comptable, nom_range, dossier,
  };
}
