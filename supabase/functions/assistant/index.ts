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

const SYSTEME = `Tu es l'assistant du board SHINE (marque française de produits de detailing auto).
Tu réponds aux associés en français, en les tutoyant, directement et sans jargon.
Ce n'est pas de la comptabilité : on regarde le chiffre d'affaires (par famille de clients, canal, produit, zone),
les achats de matières premières et les charges payées.

# Méthode
- Tout chiffre que tu donnes vient d'une requête faite avec tes outils. N'invente jamais un chiffre, ne l'estime pas.
- requete_sql pour lire et raisonner ; tableau quand la personne veut voir une liste, un classement ou un export.
  Un export demandé = un appel à tableau (il s'affiche avec un bouton « Exporter CSV »), pas une liste recopiée dans le texte.
- Réponse courte : le chiffre clé d'abord, puis 1 à 3 phrases de lecture. Format français (1 234 567 €) ;
  ventes en euros HT, achats et charges en montants payés en banque.
- Le board Ventes a des onglets : Particuliers (segment B2C), Pros (segment B2B_PRO), Revendeurs (segment B2B_REVENDEUR), MyClear (canal myclear).
  Il y a aussi les boards Achats et Charges (table tresorerie_mensuel). Si la personne est sur l'un d'eux, c'est le périmètre par défaut de sa question.
- Dis toujours sur quel périmètre tu as compté (exercice ou mois, canaux) quand ce n'est pas évident.
- Si la question est ambiguë, prends l'hypothèse la plus naturelle et dis-la en une phrase.
- Tu lis seulement : tu ne peux rien modifier (segments, validations…). Si on te le demande, renvoie vers le board.
- Mise en forme : paragraphes courts, listes « - », **gras** pour le chiffre clé. Pas de titres ni de tableaux en texte.

# Règles de calcul (les mêmes que le board)
- Exercice : du 1er octobre au 30 septembre. Code '2025-2026' = oct. 2025 → sept. 2026.
- Tous les montants de ventes sont HT.
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

Achats et charges (boards Achats et Charges) :
- tresorerie_mensuel(mois date, bloc, poste, categorie, ligne, montant) : décaissements RÉELS du plan de trésorerie, un mois par ligne.
  bloc = 'ACHATS' (matières premières) ou 'CHARGES'. montant = somme PAYÉE EN BANQUE, positive, TTC quand il y a de la TVA
  (ce n'est donc pas du HT : ne mélange jamais ces montants avec le CA HT sans le dire, et ne calcule pas de marge avec).
  - ACHATS : poste = 'ACHATS' ; categorie = famille (Chimie, Accessoires, Flacons, Emballage, Étiquettes) ; ligne = fournisseur
    (ex. « Chimie - CREE », « Chimie - Prodhynet » ; le texte après « → » dans le libellé est une note du plan, pas le fournisseur).
  - CHARGES : poste = SALAIRES, TRANSPORT, SPACE UP, FRAIS GÉNÉRAUX, MARKETING, IMPÔTS ET TAXES, LOYERS, VÉHICULES, AUTRES ;
    categorie et ligne détaillent (ex. FRAIS GÉNÉRAUX > Logiciels, Déplacements… ; TRANSPORT > transporteurs).
  - SALAIRES n'a que deux lignes : « Salaires - RH » (salaires) et « Charges / Salaires » (charges sociales). Il n'y a jamais de détail par personne.
  - SPACE UP = prestations payées par SHINE à la holding Space Up.
  - La TVA reversée (poste 'IMPÔTS ET TAXES', categorie 'TVA') n'est PAS une charge : exclus-la des totaux de charges et donne-la à part.
  - Seuls les mois constatés en banque sont présents (l'exercice en cours s'arrête au dernier mois réel) :
    compare à N-1 sur les MÊMES mois, et dis jusqu'à quel mois tu as compté. Exercice d'un mois : exercice_de(mois).
  - agg_meta.tresorerie_maj = date de la dernière relecture du plan de trésorerie (chaque lundi).

Codes utiles :
- canal : prestashop_b2c (site particuliers shine-group.fr), prestashop_pro (site pro shine-pro.fr), ebp_revendeur, ebp_pro (EBP = facturation des revendeurs et gros comptes), tiktok_b2c, jokeriders_marketplace, myclear (hors CA SHINE)
- segment : B2C = Particuliers, B2B_PRO = Pros, B2B_REVENDEUR = Revendeurs, MDD = marques de distributeur, MARKETPLACE = Marketplaces, AUTRE = Autres, INTRAGROUPE, HORS_PRODUIT, NON_SEGMENTE
  sous_segment précise la famille (ex. revendeurs : Norauto, Leclerc, Point S, GMS, Distributeurs, Indépendants… ; pros : Garages, Carrosserie, Detailing…). Filtre avec ILIKE, les libellés sont longs.
- famille produit : CHIMIE_CONDITIONNEE, CHIMIE_PF, ACCESSOIRE_PF, CONTENANT, EMBALLAGE, PACK, PLV, NON_DETAILLE (EBP non détaillé), NON_RATTACHE ; hors produits : LOYER, CESSION, INDEMNITE, AUTRE
- zone : FRANCE, UE, DOM-TOM, HORS_UE, INCONNUE

# SQL
- Une seule requête SELECT (ou WITH) par appel, sans point-virgule. PostgreSQL.
- Arrondis les montants (round(x, 2)), nomme les colonnes en français lisible pour les tableaux (as "CA HT"), trie de façon utile.
- Délai maximal 8 secondes : sur v_ventes, filtre par date et agrège.

# Data Center (board marketing des particuliers)
Quand le contexte indique « board Data Center », la question porte d'abord sur le site particuliers shine-group.fr et le marketing :
publicité (Google Ads, Meta, TikTok Ads), trafic GA4, réseaux organiques, e-mail (Omnisend), SEO (Search Console), préconisations, fiabilité des données.
- Ces données ne sont pas lisibles en SQL : utilise l'outil donnees_data_center(du, au), qui renvoie le JSON du board pour la période.
  Clés : commerce (jour, ca_ht, port_ht, commandes : factures PrestaShop des particuliers, la vérité du CA), nouveaux_clients,
  regie_jour (jour, plateforme, depense, clics, conv, valeur), ga4_jour (jour, sessions, sessions_engagees, transactions, ca_mesure),
  campagnes (plateforme, campagne, depense, clics, sessions, transactions, ca_mesure, valeur_rev), reseaux, reseaux_jour, pubs (publicités Meta),
  canaux, sources, pages (pages d'entrée), organique, posts, emails, seo_jour, seo_requetes, preconisations, fiabilite, controles_ko, fraicheur.
- Trois niveaux à ne jamais mélanger ni additionner : revendiqué (ce que la régie s'attribue, valeur_rev), mesuré (GA4, ca_mesure), encaissé (PrestaShop, commerce.ca_ht).
  MER = CA encaissé ÷ dépense totale. ROAS mesuré = ca_mesure ÷ depense.
- Avant de conclure, regarde fiabilite et controles_ko : si la période est touchée, dis-le en une phrase.
- Pour un tableau exportable à partir de ces données, construis-le toi-même avec l'outil tableau_donnees.
- Pour une comparaison, appelle donnees_data_center une fois par période. Si le contexte donne une comparaison active, utilise-la par défaut.
- Le CA du site particuliers est aussi dans les tables ventes (canal prestashop_b2c) : pour l'historique long, le SQL reste possible.`;

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
  {
    name: "donnees_data_center",
    description:
      "Renvoie les données du board Data Center (site particuliers, publicité, trafic GA4, organique, e-mail, SEO, fiabilité) pour une période, en JSON. Le résultat n'est pas montré à la personne.",
    input_schema: {
      type: "object",
      properties: {
        du: { type: "string", description: "Premier jour inclus, AAAA-MM-JJ." },
        au: { type: "string", description: "Dernier jour inclus, AAAA-MM-JJ." },
      },
      required: ["du", "au"],
      additionalProperties: false,
    },
    strict: true,
  },
  {
    name: "tableau_donnees",
    description:
      "Affiche dans le board un tableau que tu as construit toi-même (par exemple à partir de donnees_data_center), avec un bouton d'export CSV.",
    input_schema: {
      type: "object",
      properties: {
        titre: { type: "string", description: "Titre court affiché au-dessus du tableau." },
        colonnes: { type: "array", items: { type: "string" }, description: "Noms des colonnes, en français." },
        lignes: {
          type: "array",
          items: { type: "array", items: { type: ["string", "number", "null"] } },
          description: "Une liste par ligne, dans l'ordre des colonnes. Nombres bruts (pas de symbole €).",
        },
        fichier: { type: "string", description: "Nom du fichier CSV sans extension." },
      },
      required: ["titre", "colonnes", "lignes", "fichier"],
      additionalProperties: false,
    },
  },
];

const JSON_MAX = 60000; // caractères renvoyés à Claude par appel à donnees_data_center
const DATE = /^\d{4}-\d{2}-\d{2}$/;

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
  const entree = bloc.input as {
    sql?: string; titre?: string; fichier?: string; du?: string; au?: string; colonnes?: string[]; lignes?: unknown[][];
  };
  try {
    if (bloc.name === "donnees_data_center") {
      if (!DATE.test(entree.du ?? "") || !DATE.test(entree.au ?? "")) throw new Error("Dates attendues au format AAAA-MM-JJ");
      // Même fonction que le board, avec les droits de la personne connectée
      const { data, error } = await sb.rpc("dc_donnees", { p_du: entree.du, p_au: entree.au });
      if (error) throw new Error(error.message);
      let texte = JSON.stringify(data);
      if (texte.length > JSON_MAX) texte = texte.slice(0, JSON_MAX) + "\n(coupé : demande une période plus courte pour le détail)";
      return { type: "tool_result", tool_use_id: bloc.id, content: texte };
    }
    if (bloc.name === "tableau_donnees") {
      const colonnes = Array.isArray(entree.colonnes) ? entree.colonnes.map(String) : [];
      const lignes = Array.isArray(entree.lignes) ? entree.lignes.filter(Array.isArray).slice(0, LIGNES_TABLEAU) : [];
      if (!colonnes.length) throw new Error("Paramètre colonnes manquant");
      tableaux.push({ titre: entree.titre || "Résultat", colonnes, lignes, fichier: entree.fichier || "export" });
      return { type: "tool_result", tool_use_id: bloc.id, content: `Tableau affiché : ${lignes.length} ligne(s).` };
    }
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
  // Accès au board Ventes (role) ou au seul Data Center (boards.data_center)
  if (!acces?.role && !acces?.boards?.data_center) {
    return json({ error: "Accès refusé : ce compte n'est pas dans la liste des accès du board." }, 403);
  }

  type Periode = { du?: string; au?: string } | null;
  let corps: {
    question?: string; historique?: unknown;
    contexte?: { board?: string; exercice?: string; canal?: string; vue?: string | null; periode?: Periode; comparaison?: Periode };
  };
  try { corps = await req.json(); } catch { return json({ error: "Requête illisible" }, 400); }
  const question = (corps.question ?? "").trim();
  if (!question) return json({ error: "Question vide" }, 400);

  const ctx = corps.contexte ?? {};
  const aujourdhui = new Date().toLocaleDateString("fr-FR", { timeZone: "Europe/Paris", dateStyle: "full" });
  let perimetre: string;
  if (ctx.board === "data_center") {
    const per = ctx.periode?.du ? `période du ${ctx.periode.du} au ${ctx.periode.au}` : "période non précisée";
    const cmp = ctx.comparaison?.du ? `, comparaison active avec le ${ctx.comparaison.du} → ${ctx.comparaison.au}` : "";
    perimetre = `board Data Center (particuliers), page ${ctx.vue ?? "?"}, ${per}${cmp}`;
  } else {
    const canal = ctx.canal === "SHINE" ? "CA SHINE (hors MyClear)" : ctx.canal === "TOUS" ? "tous les canaux" : `canal ${ctx.canal}`;
    // Onglet ou board ouvert : Particuliers, Pros, Revendeurs, MyClear (ventes), Achats, Charges (tresorerie_mensuel)
    const onglet = ctx.vue ? `onglet ${ctx.vue}, ` : "";
    perimetre = `${onglet}exercice ${ctx.exercice ?? "?"}, ${canal}`;
  }
  const messages: Anthropic.MessageParam[] = [
    ...historiqueValide(corps.historique),
    {
      role: "user",
      content:
        `[Contexte : ${perimetre}. Nous sommes le ${aujourdhui}. ` +
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
