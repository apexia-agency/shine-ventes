// Rangeur de factures V5 : lecture d'une facture d'achat PDF par Claude, classement par les RÈGLES (moteur.ts).
// Claude ne fait que lire (fournisseur, montants, lignes) ; le compte vient de factures_fournisseurs et du
// dictionnaire produit ; les 12 contrôles de Jérémy décident si la facture est « classée » ou « à vérifier ».
//
// Appel (flux n8n du dossier Drive « Factures SHINE », ou programme du serveur outils/factures/lire-factures.mjs) :
//   POST /functions/v1/lire-facture   en-tête  x-jeton-factures: <FACTURES_TOKEN>
//   { fichier, pdf (base64), empreinte? (sha256, calculée si absente), source?: 'drive'|'serveur', drive_id?, drive_url? }
//   { reclasser: <id> }  rejoue les règles sur une facture déjà lue, sans rappeler Claude (après un changement de règle)
//   { comparer: true, ... } lit et classe sans rien écrire (essai)
// Réponse : { statut: 'classee'|'a_verifier', nom_range, dossier, compte, ventilation, motif, ... } ; { deja: true } si déjà lue.
//
// Secrets Supabase : ANTHROPIC_API_KEY et FACTURES_TOKEN. Écriture avec la clé service fournie par Supabase.

import Anthropic from "npm:@anthropic-ai/sdk";
import { createClient } from "npm:@supabase/supabase-js@2";
import { extractText, getDocumentProxy } from "npm:unpdf";
import { classer, type Contexte, type Lecture } from "./moteur.ts";

// Modèle choisi dans regles.xlsx (paramètre « Modèle Claude » = Sonnet) ; l'essai du 26/09 : Sonnet lit aussi bien qu'Opus
const MODELE = "claude-sonnet-5-5";
const PRIX: Record<string, { entree: number; sortie: number }> = { // $ par jeton
  "claude-sonnet-5-5": { entree: 2 / 1e6, sortie: 10 / 1e6 },
  "claude-opus-5-5": { entree: 4 / 1e6, sortie: 20 / 1e6 },
};
const TAILLE_MAX = 15 * 1024 * 1024;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

const SYSTEME = `Tu lis des factures d'achat reçues par SHINE (SAS SHINE, SIREN 888920071, TVA FR44888920071), marque française de produits de detailing automobile.
Ton seul rôle est de RECOPIER fidèlement ce qui est écrit : tu ne classes pas la dépense, tu ne choisis aucun compte comptable.

- type_doc : « facture », « avoir » (note de crédit, remboursement), « proforma », « devis » (devis, quotation, confirmation de commande), « acompte » (facture d'acompte, deposit, prepayment, demande de 30 %…) ou « autre » (bon de livraison, relevé, échéancier, document illisible).
- fournisseur_nom : la raison sociale de l'ÉMETTEUR telle qu'écrite (jamais SHINE). fournisseur_tva et fournisseur_siren : ceux de l'émetteur s'ils sont écrits, sinon null.
- destinataire_nom : à qui la facture est adressée, recopié tel quel, fautes comprises (« Facturé à », « Client », « Bill to »). destinataire_tva : son n° de TVA s'il est écrit.
- num_facture et date_facture (AAAA-MM-JJ) : ceux de la facture, pas de la commande ni de l'échéance.
- montant_ht, montant_tva, montant_ttc : les TOTAUX écrits, en positif même pour un avoir. Sans TVA (étranger, autoliquidation) : montant_tva = 0 et TTC = HT.
  Montant absent ou illisible : null. N'invente jamais un montant et ne le recalcule pas.
- devise : code ISO de la facture (EUR, USD, CNY…), d'après les symboles et mentions.
- lignes : chaque ligne d'article ou de frais (port, transport, remise…) avec sa désignation complète et son montant HT (négatif pour une remise), 80 au plus ; [] s'il n'y a pas de détail.
- confiance : de 0 à 1, ta certitude sur les montants et les identités lus. Moins de 0,8 si un chiffre est douteux (scan flou, manuscrit, tableau coupé).
- suggestion : en quelques mots, la nature de la dépense pour aider la personne qui vérifiera (ex. « abonnement logiciel », « fret maritime », « bidons plastique ») ; ce n'est qu'une aide, jamais utilisée pour classer.
- remarque : une phrase si quelque chose mérite l'attention d'un humain (acompte, facture partielle, devise étrangère, montant manuscrit, TVA surprenante…), sinon null.`;

const nombre = { type: ["number", "null"] };
const texteOuNull = { type: ["string", "null"] };
const SCHEMA = {
  type: "object", additionalProperties: false,
  required: ["type_doc", "fournisseur_nom", "fournisseur_tva", "fournisseur_siren", "destinataire_nom", "destinataire_tva", "num_facture",
    "date_facture", "devise", "montant_ht", "montant_tva", "montant_ttc", "lignes", "confiance", "suggestion", "remarque"],
  properties: {
    type_doc: { type: "string", enum: ["facture", "avoir", "proforma", "devis", "acompte", "autre"] },
    fournisseur_nom: { type: "string" }, fournisseur_tva: texteOuNull, fournisseur_siren: texteOuNull,
    destinataire_nom: texteOuNull, destinataire_tva: texteOuNull,
    num_facture: texteOuNull, date_facture: { ...texteOuNull, description: "AAAA-MM-JJ" }, devise: { type: "string" },
    montant_ht: nombre, montant_tva: nombre, montant_ttc: nombre,
    lignes: { type: "array", items: { type: "object", additionalProperties: false, required: ["designation", "montant_ht"], properties: { designation: { type: "string" }, montant_ht: nombre } } },
    confiance: { type: "number" }, suggestion: texteOuNull, remarque: texteOuNull,
  },
};

async function texteDuPdf(octets: Uint8Array): Promise<string | null> {
  try {
    const doc = await getDocumentProxy(octets);
    const { text } = await extractText(doc, { mergePages: true });
    return Array.isArray(text) ? text.join("\n") : text;
  } catch { return null; }
}

// Règles et historique, chargés à chaque appel (petites tables) : une règle modifiée s'applique tout de suite
async function contexte(sb: ReturnType<typeof createClient>, fichier: string, texte: string | null, ignorerId?: number): Promise<Contexte> {
  const [{ data: fournisseurs, error: e1 }, { data: dictionnaire, error: e2 }, { data: rangees, error: e3 }] = await Promise.all([
    sb.from("factures_fournisseurs").select("id, nom, alias, tva_intracom, siren, compte, regime_tva, territoire, nature, mode, eclatement, statut, motifs"),
    sb.from("factures_dictionnaire").select("nature, ordre, mots, compte_fr, compte_intra, compte_import"),
    sb.from("factures_achats").select("id, fournisseur_id, num_facture, montant_ttc, date_facture").in("statut", ["classee", "validee"]),
  ]);
  if (e1 || e2 || e3) throw new Error((e1 || e2 || e3)!.message);
  return {
    fichier, texte, fournisseurs: fournisseurs as Contexte["fournisseurs"], dictionnaire: dictionnaire as Contexte["dictionnaire"],
    historique: (f) => (rangees || []).filter((r) => r.fournisseur_id === f.id && r.id !== ignorerId),
  };
}

function ligneDeBase(r: ReturnType<typeof classer>) {
  return {
    statut: r.statut, fournisseur_id: r.fournisseur?.id ?? null, compte: r.compte, territoire: r.territoire, regime_tva: r.regime_tva,
    ventilation: r.ventilation, controles: r.controles, a_verifier: r.statut === "a_verifier", motif: r.motif,
  };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Méthode non autorisée" }, 405);
  const jeton = Deno.env.get("FACTURES_TOKEN");
  if (!jeton) return json({ error: "Secret FACTURES_TOKEN absent dans Supabase" }, 500);
  if (req.headers.get("x-jeton-factures") !== jeton) return json({ error: "Jeton refusé" }, 401);

  let corps: { fichier?: string; empreinte?: string; pdf?: string; source?: string; drive_id?: string; drive_url?: string; comparer?: boolean; reclasser?: number; modele?: string };
  try { corps = await req.json(); } catch { return json({ error: "Requête illisible" }, 400); }
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

  // Rejouer les règles sur une facture déjà lue (aucun appel à Claude)
  const reclasser = async (id: number) => {
    const { data: fa, error } = await sb.from("factures_achats").select("id, fichier, lecture, texte").eq("id", id).single();
    if (error || !fa?.lecture) return json({ error: "Facture inconnue ou lue avant le rangeur V5 (pas de lecture gardée)" }, 404);
    const r = classer(fa.lecture as Lecture, await contexte(sb, fa.fichier, fa.texte, fa.id));
    const { error: e } = await sb.from("factures_achats").update(ligneDeBase(r)).eq("id", fa.id);
    if (e) return json({ error: "Écriture impossible : " + e.message }, 500);
    return json({ id: fa.id, ...r, fournisseur: r.fournisseur?.nom ?? null, montant_ttc: (fa.lecture as Lecture).montant_ttc });
  };
  if (corps.reclasser) return await reclasser(corps.reclasser);

  const { fichier, pdf } = corps;
  const comparer = corps.comparer === true;
  const modele = corps.modele || MODELE;
  if (!PRIX[modele]) return json({ error: "Modèle inconnu : " + modele }, 400);
  if (!fichier || !pdf) return json({ error: "fichier et pdf (base64) sont obligatoires" }, 400);
  if (pdf.length * 0.75 > TAILLE_MAX) return json({ error: "PDF trop lourd (plus de 15 Mo)" }, 413);
  const octets = Uint8Array.from(atob(pdf), (c) => c.charCodeAt(0));
  // Empreinte SHA-256 : envoyée par le programme du serveur, calculée ici pour le flux n8n du Drive
  const empreinte = corps.empreinte || [...new Uint8Array(await crypto.subtle.digest("SHA-256", octets))].map((x) => x.toString(16).padStart(2, "0")).join("");
  if (!/^[0-9a-f]{64}$/.test(empreinte)) return json({ error: "empreinte invalide (sha256 attendu)" }, 400);
  const cle = Deno.env.get("ANTHROPIC_API_KEY");
  if (!cle) return json({ error: "Secret ANTHROPIC_API_KEY absent dans Supabase" }, 500);

  if (!comparer) {
    const { data: existe } = await sb.from("factures_achats").select("id, statut, drive_id").eq("empreinte", empreinte).maybeSingle();
    // Le même fichier Drive qui revient (rangement interrompu) : on rejoue les règles et on le range, ce n'est pas un doublon
    if (existe && corps.drive_id && existe.drive_id === corps.drive_id) return await reclasser(existe.id);
    if (existe) return json({ deja: true, id: existe.id, statut: existe.statut });
  }
  const texte = await texteDuPdf(octets);

  const client = new Anthropic({ apiKey: cle });
  let rep: Anthropic.Message;
  try {
    // Appel simple, sans le « fallback côté serveur » (bêta) : il renvoyait « 503 credential validation failed » le 29/09 à 16 h
    rep = await client.messages.create({
      model: modele,
      max_tokens: 16000,
      system: [{ type: "text", text: SYSTEME, cache_control: { type: "ephemeral" } }],
      thinking: { type: "adaptive" },
      output_config: { effort: "medium", format: { type: "json_schema", schema: SCHEMA } },
      messages: [{
        role: "user",
        content: [
          { type: "document", source: { type: "base64", media_type: "application/pdf", data: pdf } },
          { type: "text", text: `Nom du fichier déposé : ${fichier}` },
        ],
      }],
    } as unknown as Anthropic.MessageCreateParamsNonStreaming) as Anthropic.Message;
  } catch (e) {
    if (e instanceof Anthropic.RateLimitError) return json({ error: "Limite de débit Claude, réessayer plus tard" }, 429);
    if (e instanceof Anthropic.APIError) return json({ error: `Erreur Claude (${e.status ?? "?"}) : ${e.message}` }, 502);
    return json({ error: `Erreur : ${(e as Error).message}` }, 500);
  }
  if (rep.stop_reason === "refusal") return json({ error: "Lecture refusée par le modèle" }, 422);
  const brut = rep.content.filter((b) => b.type === "text").map((b) => (b as { text: string }).text).join("");
  let lu: Lecture;
  try { lu = JSON.parse(brut); } catch { return json({ error: "Réponse illisible du modèle", stop: rep.stop_reason }, 502); }
  lu.confiance = Math.max(0, Math.min(1, lu.confiance));

  let r: ReturnType<typeof classer>;
  try { r = classer(lu, await contexte(sb, fichier, texte)); } catch (e) { return json({ error: "Règles illisibles : " + (e as Error).message }, 500); }

  const u = rep.usage;
  const p = PRIX[rep.model] || PRIX[modele];
  const cout = u.input_tokens * p.entree + (u.cache_creation_input_tokens || 0) * p.entree * 1.25 + (u.cache_read_input_tokens || 0) * p.entree * 0.1 + u.output_tokens * p.sortie;
  const ligne = {
    empreinte, fichier, source: corps.source || null, drive_id: corps.drive_id || null, drive_url: corps.drive_url || null,
    type_doc: lu.type_doc, fournisseur: r.fournisseur?.nom ?? lu.fournisseur_nom, fournisseur_tva: lu.fournisseur_tva, destinataire: lu.destinataire_nom,
    num_facture: lu.num_facture, date_facture: lu.date_facture && /^\d{4}-\d{2}-\d{2}$/.test(lu.date_facture) ? lu.date_facture : null,
    devise: lu.devise, montant_ht: lu.montant_ht, montant_tva: lu.montant_tva, montant_ttc: lu.montant_ttc,
    lignes: lu.lignes, confiance: lu.confiance, categorie: lu.suggestion, texte_pdf: (texte ?? "").trim().length > 50, texte: texte ? texte.slice(0, 20000) : null,
    lecture: lu, ...ligneDeBase(r),
    modele: rep.model, jetons_entree: u.input_tokens + (u.cache_creation_input_tokens || 0) + (u.cache_read_input_tokens || 0),
    jetons_sortie: u.output_tokens, cout_usd: Math.round(cout * 10000) / 10000, traite_le: new Date().toISOString(),
  };
  const reponse = { ...r, fournisseur: r.fournisseur?.nom ?? null, fournisseur_lu: lu.fournisseur_nom, montant_ttc: lu.montant_ttc, suggestion: lu.suggestion, cout_usd: ligne.cout_usd };
  if (comparer) return json({ comparaison: true, ...reponse, lecture: lu });
  const { data, error } = await sb.from("factures_achats").upsert(ligne, { onConflict: "empreinte" }).select("id").single();
  if (error) return json({ error: "Écriture impossible : " + error.message, ...reponse }, 500);
  return json({ id: data.id, ...reponse });
});
