// Lecture d'une facture d'achat PDF par Claude, puis rangement dans la table factures_achats.
//
// Appel (programme du serveur SHINE, outils/factures/lire-factures.mjs) :
//   POST /functions/v1/lire-facture   en-tête  x-jeton-factures: <FACTURES_TOKEN>
//   corps JSON { fichier: 'BILAN 2025-2026/26-08 (AOUT)/…/HA-FOUR-CREE-260814-39120.00 €TTC.pdf', empreinte: '<sha256>', pdf: '<base64>' }
// Réponse : { deja: true } si le fichier a déjà été lu, sinon la facture lue + le coût.
//
// Secrets Supabase : ANTHROPIC_API_KEY (déjà là) et FACTURES_TOKEN (jeton partagé avec le programme du serveur).
// La fonction écrit avec la clé service (fournie par Supabase) : le programme du serveur n'a aucun accès direct à la base.

import Anthropic from "npm:@anthropic-ai/sdk";
import { createClient } from "npm:@supabase/supabase-js@2";

const MODELE = "claude-opus-4-8";
const PRIX = { entree: 5 / 1e6, sortie: 25 / 1e6 }; // $ par jeton (Opus 4.8)
const TAILLE_MAX = 15 * 1024 * 1024; // PDF de 15 Mo au plus

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

const SYSTEME = `Tu lis des factures d'achat de SHINE (marque française de produits de detailing auto, fabrication et vente).
Tu extrais les montants EXACTEMENT comme écrits sur la facture, et tu classes la dépense comme dans le plan de trésorerie de SHINE.

# Extraction
- type_doc : « facture », « avoir » (avoir, note de crédit, remboursement du fournisseur) ou « autre » (devis, bon de livraison, relevé, échéancier, document illisible…).
- fournisseur : la raison sociale de l'émetteur (pas SHINE), courte et lisible (ex. « CREE », « Prodhynet », « DPD France »).
- num_facture et date_facture (AAAA-MM-JJ) : ceux de la facture, pas de la commande ni de l'échéance.
- montant_ht, montant_tva, montant_ttc : les TOTAUX de la facture, en positif même pour un avoir. Pas de TVA (étranger, autoliquidation) : montant_tva = 0 et TTC = HT.
  Montant absent ou illisible : null (n'invente jamais, ne calcule pas un montant qui n'est pas écrit, sauf TTC = HT quand il n'y a clairement pas de TVA).
- devise : code ISO (EUR, USD, CNY…).
- lignes : les lignes d'articles quand elles existent (désignation, quantité, prix unitaire HT, montant HT), 60 au plus ; sinon [].

# Classement (bloc / poste / catégorie du plan de trésorerie)
ACHATS (matières et marchandises revendues), poste « ACHATS », catégorie :
- Chimie : produits chimiques finis ou matières premières (CREE, Prodhynet, Aérochem, Aérolub, Ambrosol, Bio-Sorelia, OQEMA, VéraChimie, Green&Safe, Scholl polish, Azelis, BASF, Brenntag, Univar, Stockmeier, Interchimie, CHT, Spiess, Vidara, Nexus…).
- Accessoires : microfibres, brosses, pads, gants, sacoches, vêtements, stickers (4B, De Witte / Lautus, TonyIn, Deyuan, Kasi Teng, Amio, Billat, Seko, Lamatex, Rubberex, AliExpress / Alibaba…).
- Flacons : flacons, bidons, bouchons, têtes de pulvérisation (CPMO / Caps Packaging / Cosline, Guala, Fidel Fillaud, Saccof, Berlin Packaging…).
- Emballage : cartons, films, sachets, palettes (Plast'Embal, Découpe Stéphanoise, VPK / TNM, Astic, Sequoia…).
- Étiquettes : étiquettes produits (Napack, GMJ…).
CHARGES, poste et catégorie :
- TRANSPORT > Transport : transporteurs et envois (Colissimo / La Poste, DPD, DHL, Dachser, XPO, Fatton, Somaudex, douane à l'import).
- FRAIS GÉNÉRAUX > Logiciels (abonnements, SaaS, hébergement, IA, ERP, leasing informatique) | Déplacements (salons, repas, péages, hôtels, cadeaux clients)
  | Matériel (machines, leasing de machines et de manutention, racks, EPI) | Électricité + Eau + Déchets (EDF, Engie, eau, Citeo, Sermaco, Sarpi)
  | Essence (carburant) | Avocat Comptable (comptable, avocat, huissier, greffe, INPI) | Assurances (locaux, RC pro, bris de machine)
  | Sécurité (extincteurs, APAVE, caméras, plombier, électricien, santé au travail, R&D chimie conseil) | Bureautique (fournitures, informatique, imprimante)
  | Internet + Tél (Orange, Free, SFR) | Frais bancaires (commissions, frais postaux).
- MARKETING > PUB - Réseaux & Comm : publicité, agences, influenceurs, photo et vidéo, goodies, PLV, royalties.
- LOYERS > Loyer + Charges + IF : loyers, charges locatives, taxe foncière, ménage des bureaux, travaux des locaux.
- VÉHICULES > Véhicules (location longue durée, leasing, entretien, réparations) | Assurances VL (assurance des véhicules).
- SPACE UP > Space Up : factures de la holding Space Up (prestations de gestion).
- IMPÔTS ET TAXES > Impôts (CFE, CVAE, douanes, IS, taxes) | TVA.
- AUTRES > Remboursement CLTS : remboursements de clients, litiges.
HORS (poste « HORS ») : ce n'est pas une dépense (facture de vente de SHINE, document interne, relevé sans montant…).
Si tu hésites entre deux classements, choisis le plus probable et baisse la confiance.

- confiance : 0 à 1, ta certitude globale sur les montants ET le classement (moins de 0,8 si un montant est douteux ou si le classement est incertain).
- remarque : une phrase si quelque chose mérite l'attention d'un humain (acompte, facture partielle, devise étrangère, montant manuscrit…), sinon null.`;

const nombre = { type: ["number", "null"] };
const SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["type_doc", "fournisseur", "num_facture", "date_facture", "devise", "montant_ht", "montant_tva", "montant_ttc", "bloc", "poste", "categorie", "lignes", "confiance", "remarque"],
  properties: {
    type_doc: { type: "string", enum: ["facture", "avoir", "autre"] },
    fournisseur: { type: "string" },
    num_facture: { type: ["string", "null"] },
    date_facture: { type: ["string", "null"], description: "AAAA-MM-JJ" },
    devise: { type: "string" },
    montant_ht: nombre, montant_tva: nombre, montant_ttc: nombre,
    bloc: { type: "string", enum: ["ACHATS", "CHARGES", "HORS"] },
    poste: { type: "string", enum: ["ACHATS", "TRANSPORT", "FRAIS GÉNÉRAUX", "MARKETING", "LOYERS", "VÉHICULES", "SPACE UP", "IMPÔTS ET TAXES", "AUTRES", "HORS"] },
    categorie: { type: "string" },
    lignes: {
      type: "array",
      items: {
        type: "object", additionalProperties: false,
        required: ["designation", "quantite", "prix_unitaire_ht", "montant_ht"],
        properties: { designation: { type: "string" }, quantite: nombre, prix_unitaire_ht: nombre, montant_ht: nombre },
      },
    },
    confiance: { type: "number" },
    remarque: { type: ["string", "null"] },
  },
};

type Lu = {
  type_doc: "facture" | "avoir" | "autre"; fournisseur: string; num_facture: string | null; date_facture: string | null; devise: string;
  montant_ht: number | null; montant_tva: number | null; montant_ttc: number | null; bloc: string; poste: string; categorie: string;
  lignes: { designation: string; quantite: number | null; prix_unitaire_ht: number | null; montant_ht: number | null }[];
  confiance: number; remarque: string | null;
};

// Montant TTC écrit dans le nom du fichier (convention SHINE « …-39120.00 €TTC.pdf ») : sert de contrôle
function ttcDuNom(fichier: string): number | null {
  const m = /(\d+(?:[.,]\d+)?)\s*€?\s*TTC/i.exec(fichier.split("/").pop() || "");
  return m ? parseFloat(m[1].replace(",", ".")) : null;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Méthode non autorisée" }, 405);
  const jeton = Deno.env.get("FACTURES_TOKEN");
  if (!jeton) return json({ error: "Secret FACTURES_TOKEN absent dans Supabase" }, 500);
  if (req.headers.get("x-jeton-factures") !== jeton) return json({ error: "Jeton refusé" }, 401);
  const cle = Deno.env.get("ANTHROPIC_API_KEY");
  if (!cle) return json({ error: "Secret ANTHROPIC_API_KEY absent dans Supabase" }, 500);

  let corps: { fichier?: string; empreinte?: string; pdf?: string };
  try { corps = await req.json(); } catch { return json({ error: "Requête illisible" }, 400); }
  const { fichier, empreinte, pdf } = corps;
  if (!fichier || !empreinte || !/^[0-9a-f]{64}$/.test(empreinte) || !pdf) return json({ error: "fichier, empreinte (sha256) et pdf (base64) sont obligatoires" }, 400);
  if (pdf.length * 0.75 > TAILLE_MAX) return json({ error: "PDF trop lourd (plus de 15 Mo)" }, 413);

  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const { data: existe } = await sb.from("factures_achats").select("id").eq("empreinte", empreinte).maybeSingle();
  if (existe) return json({ deja: true, id: existe.id });

  const client = new Anthropic({ apiKey: cle });
  let rep: Anthropic.Message;
  try {
    rep = await client.messages.create({
      model: MODELE,
      max_tokens: 16000,
      system: [{ type: "text", text: SYSTEME, cache_control: { type: "ephemeral" } }],
      messages: [{
        role: "user",
        content: [
          { type: "document", source: { type: "base64", media_type: "application/pdf", data: pdf } },
          { type: "text", text: `Nom et dossier du fichier : ${fichier}\n(Convention SHINE : TYPE-CATÉGORIE-FOURNISSEUR-AAMMJJ-MONTANT TTC ; HA = achat, AV = avoir, FOUR = marchandises ou transport, FG = frais généraux. C'est un indice : la facture fait foi.)` },
        ],
      }],
      thinking: { type: "adaptive" },
      output_config: { effort: "medium", format: { type: "json_schema", schema: SCHEMA } },
    } as unknown as Anthropic.MessageCreateParamsNonStreaming) as Anthropic.Message;
  } catch (e) {
    if (e instanceof Anthropic.RateLimitError) return json({ error: "Limite de débit Claude, réessayer plus tard" }, 429);
    if (e instanceof Anthropic.APIError) return json({ error: `Erreur Claude (${e.status ?? "?"}) : ${e.message}` }, 502);
    return json({ error: `Erreur : ${(e as Error).message}` }, 500);
  }
  if (rep.stop_reason === "refusal") return json({ error: "Lecture refusée par le modèle" }, 422);
  const texte = rep.content.filter((b): b is Anthropic.TextBlock => b.type === "text").map((b) => b.text).join("");
  let lu: Lu;
  try { lu = JSON.parse(texte); } catch { return json({ error: "Réponse illisible du modèle", stop: rep.stop_reason }, 502); }

  // Contrôles : tout ce qui est douteux est mis de côté pour un associé
  const motifs: string[] = [];
  const { montant_ht: ht, montant_tva: tva, montant_ttc: ttc } = lu;
  if (lu.type_doc === "autre") motifs.push("pas une facture");
  if (ttc == null) motifs.push("TTC illisible");
  if (!lu.date_facture || !/^\d{4}-\d{2}-\d{2}$/.test(lu.date_facture)) motifs.push("date illisible");
  if (ht != null && tva != null && ttc != null && Math.abs(ht + tva - ttc) > 0.05) motifs.push(`HT + TVA ≠ TTC (${(ht + tva).toFixed(2)} / ${ttc.toFixed(2)})`);
  const ttcNom = ttcDuNom(fichier);
  if (ttcNom != null && ttc != null && lu.devise === "EUR" && Math.abs(ttcNom - ttc) > Math.max(1, ttc * 0.01)) motifs.push(`TTC différent du nom du fichier (${ttcNom})`);
  if (lu.confiance < 0.8) motifs.push("confiance " + lu.confiance);
  if (lu.devise !== "EUR") motifs.push("devise " + lu.devise);
  // La remarque du modèle est gardée pour information (autoliquidation, gaz…) mais ne bloque pas à elle seule
  const aVerifier = motifs.length > 0;
  if (lu.remarque) motifs.push(lu.remarque);

  const u = rep.usage;
  const entree = u.input_tokens + (u.cache_creation_input_tokens || 0) + (u.cache_read_input_tokens || 0);
  const cout = u.input_tokens * PRIX.entree + (u.cache_creation_input_tokens || 0) * PRIX.entree * 1.25 + (u.cache_read_input_tokens || 0) * PRIX.entree * 0.1 + u.output_tokens * PRIX.sortie;
  const ligne = {
    empreinte, fichier, type_doc: lu.type_doc, fournisseur: lu.fournisseur, num_facture: lu.num_facture,
    date_facture: lu.date_facture && /^\d{4}-\d{2}-\d{2}$/.test(lu.date_facture) ? lu.date_facture : null,
    devise: lu.devise, montant_ht: ht, montant_tva: tva, montant_ttc: ttc,
    bloc: lu.bloc, poste: lu.poste, categorie: lu.categorie, lignes: lu.lignes,
    confiance: Math.max(0, Math.min(1, lu.confiance)), a_verifier: aVerifier, motif: motifs.join(" ; ") || null,
    modele: MODELE, jetons_entree: entree, jetons_sortie: u.output_tokens, cout_usd: Math.round(cout * 10000) / 10000,
  };
  const { data, error } = await sb.from("factures_achats").upsert(ligne, { onConflict: "empreinte" }).select("id").single();
  if (error) return json({ error: "Écriture impossible : " + error.message, lu: ligne }, 500);
  return json({ id: data.id, ...ligne, lignes: lu.lignes.length });
});
