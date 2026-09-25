// Assistant ventes du board SHINE.
//
// Appel depuis le board : sb.functions.invoke('assistant', { body: { question, historique, contexte } })
// Réponse : { reponse: 'texte', tableaux: [{ titre, colonnes, lignes, fichier }] }
//
// Claude répond en interrogeant la base avec deux outils :
//   - requete_sql : lit des données pour raisonner (200 lignes max, non affichées) ;
//   - tableau     : produit un tableau affiché dans le board et exportable en CSV (5 000 lignes max).
// Les requêtes passent par la fonction SQL assistant_sql, avec le jeton de la personne connectée :
// lecture seule, et uniquement ce que ses droits sur le board lui permettent de voir.
//
// Secret à créer dans Supabase (Edge Functions → Secrets) : ANTHROPIC_API_KEY.

import Anthropic from "npm:@anthropic-ai/sdk";
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

const MODELE = "claude-opus-4-8"; // même modèle que l'app Friday
const MAX_TOURS = 8; // allers-retours outils par question
const LIGNES_LECTURE = 200;
const LIGNES_TABLEAU = 5000;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

const SYSTEME = `Tu es l'assistant ventes du board SHINE (marque française de produits de detailing auto).
Tu réponds aux associés (Robin, Jérémy) en français, en les tutoyant, directement et sans jargon.
Ce n'est pas de la comptabilité : on regarde le chiffre d'affaires par famille de clients, canal, produit, zone.

# Méthode
- Tout chiffre que tu donnes vient d'une requête faite avec tes outils. N'invente jamais un chiffre, ne l'estime pas.
- requete_sql pour lire et raisonner ; tableau quand la personne veut voir une liste, un classement ou un export.
  Un export demandé = un appel à tableau (il s'affiche avec un bouton « Exporter CSV »), pas une liste recopiée dans le texte.
- Réponse courte : le chiffre clé d'abord, puis 1 à 3 phrases de lecture. Montants en euros HT, format français (1 234 567 €).
- Dis toujours sur quel périmètre tu as compté (exercice ou mois, canaux) quand ce n'est pas évident.
- Si la question est ambiguë, prends l'hypothèse la plus naturelle et dis-la en une phrase.
- Tu lis seulement : tu ne peux rien modifier (segments, validations…). Si on te le demande, renvoie vers le board.
- Mise en forme : paragraphes courts, listes « - », **gras** pour le chiffre clé. Pas de titres ni de tableaux en texte.

# Règles de calcul (les mêmes que le board)
- Exercice : du 1er octobre au 30 septembre. Code '2025-2026' = oct. 2025 → sept. 2026.
- Tous les montants sont HT.
- « CA » tout court = CA HT produits : lignes où produit = true
  (les familles LOYER, CESSION, INDEMNITE et AUTRE sont « hors produits » : produit = false).
- « CA SHINE » (choix par défaut du board) = canaux où dans_ca_shine = true, donc sans MyClear.
  « Tous les canaux » ajoute MyClear (canal myclear, une autre marque du groupe).
- Comparaison N-1 : même période un an avant. Pour un exercice en cours, compare jusqu'à la même date (voir agg_meta.derniere_facture).
- Le port facturé n'est pas du CA produit ; il est à part (port_ht).
- Les ventes de packs sont réparties entre leurs produits dans agg_ventes_mensuel et agg_produits (le total ne change pas) ;
  dans v_ventes / v_export_cdc, elles restent au niveau du pack (une ligne par ligne de facture).

# Tables (schéma public)
Préfère les agrégats, rapides et identiques au board :
- agg_ventes_mensuel(mois date, exercice, canal, dans_ca_shine, segment, segment_valide, sous_segment, zone, famille, produit bool, ca_ht, quantite, nb_lignes)
- agg_produits(exercice, canal, segment, sku, libelle, famille, quantite, ca_ht) : par produit et exercice
- agg_clients(exercice, canal, client_id, client_nom, groupe_client, segment, segment_valide, pays, nb_factures, ca_ht, derniere_facture)
- agg_jour(jour date, canal, segment, ca_ht, nb_factures, port_ht, ca_autres) : par jour, ca_ht = CA produits, ca_autres = hors produits
- agg_commandes_mensuel(mois, exercice, canal, dans_ca_shine, segment, zone, nb_factures, nb_avoirs, nb_clients, port_ht, nb_port_offert, ca_factures_ht)
- agg_meta(cle, valeur jsonb) : derniere_maj, derniere_facture (par canal), canaux_agreges, anomalies
Détail, pour ce que les agrégats n'ont pas (numéro de facture, date exacte, client + produit…) :
- v_ventes(canal, dans_ca_shine, source, date_facture, mois, exercice, num_facture, num_commande, avoir bool, client_id, client_nom, segment, groupe_client, pays_livraison, zone, sku, libelle_produit, famille, sous_famille, contenance_l, quantite, pu_ht, remise_ht, total_ligne_ht)
  Une ligne par ligne de facture (≈ 500 000 lignes) : filtre toujours par date ou exercice.
- v_export_cdc : le même détail au format de l'export CSV du board (colonnes date_iso, exercice, total_ligne_ht, frais_port_facture_ht…).
Référentiels :
- canaux(code, libelle, dans_ca_shine) ; produits(sku, ean, libelle, famille, sous_famille, gamme, contenance_l, marque, fabrique_interne)
- clients(client_id, client_nom, canal_origine, segment, sous_segment, segment_valide, groupe_client, pays, tva_intra, siret, actif)
- packs_composition(sku_pack, sku_composant, quantite, prix_ref) ; couts_transport(mois, transporteur, type_envoi, montant_ttc) : payé en banque, TTC
- compta_ca_mensuel(mois, compte, libelle, montant_ht) : CA des comptes 70

Codes utiles :
- canal : prestashop_b2c (site particuliers shine-group.fr), prestashop_pro (site pro shine-pro.fr), ebp_revendeur, ebp_pro (EBP = facturation des revendeurs et gros comptes), tiktok_b2c, jokeriders_marketplace, myclear (hors CA SHINE)
- segment : B2C = Particuliers, B2B_PRO = Pros, B2B_REVENDEUR = Revendeurs, MDD = marques de distributeur, MARKETPLACE = Marketplaces, AUTRE = Autres, INTRAGROUPE, HORS_PRODUIT, NON_SEGMENTE
  sous_segment précise la famille (ex. revendeurs : Norauto, Leclerc, Point S, GMS, Distributeurs, Indépendants… ; pros : Garages, Carrosserie, Detailing…). Filtre avec ILIKE, les libellés sont longs.
- famille produit : CHIMIE_CONDITIONNEE, CHIMIE_PF, ACCESSOIRE_PF, CONTENANT, EMBALLAGE, PACK, PLV, NON_DETAILLE (EBP non détaillé), NON_RATTACHE ; hors produits : LOYER, CESSION, INDEMNITE, AUTRE
- zone : FRANCE, UE, DOM-TOM, HORS_UE, INCONNUE

# SQL
- Une seule requête SELECT (ou WITH) par appel, sans point-virgule. PostgreSQL.
- Arrondis les montants (round(x, 2)), nomme les colonnes en français lisible pour les tableaux (as "CA HT"), trie de façon utile.
- Délai maximal 8 secondes : sur v_ventes, filtre par date et agrège.`;

const OUTILS: Anthropic.Tool[] = [
  {
    name: "requete_sql",
    description:
      "Exécute une requête SELECT PostgreSQL en lecture seule sur la base des ventes et renvoie au plus 200 lignes en JSON. Sert à calculer ou vérifier des chiffres ; le résultat n'est pas montré à la personne.",
    input_schema: {
      type: "object",
      properties: { sql: { type: "string", description: "Une requête SELECT ou WITH, sans point-virgule." } },
      required: ["sql"],
      additionalProperties: false,
    },
    strict: true,
  },
  {
    name: "tableau",
    description:
      "Exécute une requête SELECT et affiche le résultat comme tableau dans le board, avec un bouton d'export CSV (5 000 lignes max). À utiliser pour toute liste, classement ou export demandé. Tu reçois en retour le nombre de lignes et un aperçu.",
    input_schema: {
      type: "object",
      properties: {
        titre: { type: "string", description: "Titre court affiché au-dessus du tableau, ex. « Top 20 revendeurs 2025–2026 »." },
        sql: { type: "string", description: "Une requête SELECT ou WITH, sans point-virgule, colonnes nommées en français." },
        fichier: { type: "string", description: "Nom du fichier CSV sans extension, ex. top_revendeurs_2025_2026." },
      },
      required: ["titre", "sql", "fichier"],
      additionalProperties: false,
    },
    strict: true,
  },
];

type Tableau = { titre: string; colonnes: string[]; lignes: unknown[][]; fichier: string };

async function executerSql(sb: SupabaseClient, sql: string, max: number) {
  const { data, error } = await sb.rpc("assistant_sql", { p_sql: sql, p_max: max });
  if (error) throw new Error(error.message);
  return data as { lignes: Record<string, unknown>[]; tronque: boolean };
}

async function executerOutil(
  sb: SupabaseClient,
  bloc: Anthropic.ToolUseBlock,
  tableaux: Tableau[],
): Promise<Anthropic.ToolResultBlockParam> {
  const entree = bloc.input as { sql?: string; titre?: string; fichier?: string };
  try {
    if (typeof entree.sql !== "string" || !entree.sql.trim()) throw new Error("Paramètre sql manquant");
    if (bloc.name === "requete_sql") {
      const r = await executerSql(sb, entree.sql, LIGNES_LECTURE);
      const note = r.tronque ? `\n(résultat coupé à ${LIGNES_LECTURE} lignes : agrège ou filtre davantage)` : "";
      return { type: "tool_result", tool_use_id: bloc.id, content: JSON.stringify(r.lignes) + note };
    }
    if (bloc.name === "tableau") {
      const r = await executerSql(sb, entree.sql, LIGNES_TABLEAU);
      const colonnes = r.lignes.length ? Object.keys(r.lignes[0]) : [];
      tableaux.push({
        titre: entree.titre || "Résultat",
        colonnes,
        lignes: r.lignes.map((l) => colonnes.map((c) => l[c])),
        fichier: entree.fichier || "export",
      });
      const apercu = JSON.stringify(r.lignes.slice(0, 10));
      return {
        type: "tool_result",
        tool_use_id: bloc.id,
        content:
          `Tableau affiché : ${r.lignes.length} ligne(s)${r.tronque ? `, coupé à ${LIGNES_TABLEAU}` : ""}. ` +
          `Colonnes : ${colonnes.join(", ") || "aucune"}. Aperçu des 10 premières : ${apercu}`,
      };
    }
    throw new Error(`Outil inconnu : ${bloc.name}`);
  } catch (e) {
    return { type: "tool_result", tool_use_id: bloc.id, content: `Erreur : ${(e as Error).message}`, is_error: true };
  }
}

function historiqueValide(h: unknown): Anthropic.MessageParam[] {
  if (!Array.isArray(h)) return [];
  const out: Anthropic.MessageParam[] = [];
  for (const m of h.slice(-12)) {
    const role = m?.role, content = typeof m?.content === "string" ? m.content.trim() : "";
    if ((role !== "user" && role !== "assistant") || !content) continue;
    if (out.length && out[out.length - 1].role === role) continue; // garde l'alternance user / assistant
    if (!out.length && role !== "user") continue;
    out.push({ role, content });
  }
  if (out.length && out[out.length - 1].role === "user") out.pop(); // la nouvelle question suit
  return out;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Méthode non autorisée" }, 405);

  const cle = Deno.env.get("ANTHROPIC_API_KEY");
  if (!cle) return json({ error: "Clé API Claude absente : ajouter le secret ANTHROPIC_API_KEY dans Supabase." }, 500);

  // Client Supabase avec le jeton de la personne connectée : ses droits s'appliquent à chaque requête.
  const sb = createClient(
    Deno.env.get("SUPABASE_URL")!,
    req.headers.get("apikey") ?? Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } }, auth: { persistSession: false } },
  );
  const { data: acces } = await sb.rpc("mon_acces");
  if (!acces?.role) return json({ error: "Accès refusé : ce compte n'est pas dans la liste des accès du board." }, 403);

  let corps: { question?: string; historique?: unknown; contexte?: { exercice?: string; canal?: string } };
  try { corps = await req.json(); } catch { return json({ error: "Requête illisible" }, 400); }
  const question = (corps.question ?? "").trim();
  if (!question) return json({ error: "Question vide" }, 400);

  const ctx = corps.contexte ?? {};
  const canal = ctx.canal === "SHINE" ? "CA SHINE (hors MyClear)" : ctx.canal === "TOUS" ? "tous les canaux" : `canal ${ctx.canal}`;
  const aujourdhui = new Date().toLocaleDateString("fr-FR", { timeZone: "Europe/Paris", dateStyle: "full" });
  const messages: Anthropic.MessageParam[] = [
    ...historiqueValide(corps.historique),
    {
      role: "user",
      content:
        `[Contexte du board : exercice ${ctx.exercice ?? "?"}, ${canal}. Nous sommes le ${aujourdhui}. ` +
        `Utilise ce périmètre sauf si la question en précise un autre.]\n\n${question}`,
    },
  ];

  const client = new Anthropic({ apiKey: cle });
  const tableaux: Tableau[] = [];
  try {
    for (let tour = 0; tour < MAX_TOURS; tour++) {
      // Réflexion adaptative : sur Opus 4.8, elle est coupée si on ne la demande pas.
      const rep = await client.messages.create({
        model: MODELE,
        max_tokens: 16000,
        system: [{ type: "text", text: SYSTEME, cache_control: { type: "ephemeral" } }],
        tools: OUTILS,
        messages,
        thinking: { type: "adaptive" },
        output_config: { effort: "medium" },
      });

      if (rep.stop_reason === "refusal") {
        return json({ reponse: "Je ne peux pas répondre à cette demande. Reformule-la autrement.", tableaux });
      }
      if (rep.stop_reason === "pause_turn") {
        messages.push({ role: "assistant", content: rep.content });
        continue;
      }
      const appels = rep.content.filter((b): b is Anthropic.ToolUseBlock => b.type === "tool_use");
      if (rep.stop_reason !== "tool_use" || !appels.length) {
        const texte = rep.content
          .filter((b): b is Anthropic.TextBlock => b.type === "text")
          .map((b) => b.text).join("\n").trim();
        const coupe = rep.stop_reason === "max_tokens" ? "\n\n(réponse coupée, trop longue)" : "";
        return json({ reponse: (texte || (tableaux.length ? "" : "Pas de réponse.")) + coupe, tableaux });
      }
      messages.push({ role: "assistant", content: rep.content });
      const resultats = await Promise.all(appels.map((b) => executerOutil(sb, b, tableaux)));
      messages.push({ role: "user", content: resultats });
    }
    return json({
      reponse: "Je n'ai pas réussi à conclure en un nombre raisonnable d'étapes. Essaie une question plus précise.",
      tableaux,
    });
  } catch (e) {
    if (e instanceof Anthropic.RateLimitError) return json({ error: "Trop de demandes en même temps, réessaie dans une minute." }, 429);
    if (e instanceof Anthropic.AuthenticationError) return json({ error: "Clé API Claude refusée : vérifier le secret ANTHROPIC_API_KEY." }, 500);
    if (e instanceof Anthropic.APIError) return json({ error: `Erreur du service Claude (${e.status ?? "?"}) : ${e.message}` }, 502);
    return json({ error: `Erreur : ${(e as Error).message}` }, 500);
  }
});
