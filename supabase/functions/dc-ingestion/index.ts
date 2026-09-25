// DATA CENTER — ingestion Windsor -> Supabase (schéma marketing)
// Appel : POST { sources?: string[], du?: 'YYYY-MM-DD', au?: 'YYYY-MM-DD' } avec l'en-tête x-dc-jeton
// (jeton généré dans le coffre Supabase, lu par marketing.lancer_ingestion ; jamais saisi à la main).
// Par défaut : toutes les sources, 30 derniers jours (les régies réécrivent leur passé).
// Secret : CLE_API_WINDSOR (saisi par Jérémy). SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY injectés par Supabase.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const WINDSOR = "https://connectors.windsor.ai";
const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

type Row = Record<string, any>;
const num = (v: any) => (v === null || v === undefined || v === "" ? null : Number(v));
const ns = (v: any) => (v === undefined || v === null || v === "(not set)" ? "" : String(v));

async function windsor(connector: string, fields: string[], du: string, au: string, accounts?: string[]): Promise<Row[]> {
  const key = Deno.env.get("CLE_API_WINDSOR") ?? Deno.env.get("WINDSOR_API_KEY");
  if (!key) throw new Error("Secret CLE_API_WINDSOR absent");
  const p = new URLSearchParams({ api_key: key, date_from: du, date_to: au, fields: fields.join(",") });
  if (accounts?.length) p.set("select_accounts", accounts.join(","));
  const res = await fetch(`${WINDSOR}/${connector}?${p}`);
  const txt = await res.text();
  if (!res.ok) throw new Error(`${connector} HTTP ${res.status}: ${txt.slice(0, 300).replaceAll(key, "***")}`);
  const j = JSON.parse(txt);
  if (j.error) throw new Error(`${connector}: ${JSON.stringify(j.error).slice(0, 300)}`);
  return (j.data ?? j.result ?? []) as Row[];
}

const SOURCES: Record<string, (du: string, au: string) => Promise<{ cible: string; lignes: Row[] }[]>> = {
  google_ads: async (du, au) => {
    const d = await windsor("google_ads",
      ["date","account_id","campaign_id","campaign","campaign_type","ad_network_type","impressions","clicks","spend","conversions","conversion_value"],
      du, au, ["544-938-9696"]);
    return [{ cible: "google_ads", lignes: d.map(r => ({
      jour: r.date, compte_id: r.account_id, campagne_id: String(r.campaign_id), campagne_nom: r.campaign,
      type_campagne: r.campaign_type, reseau: r.ad_network_type, impressions: num(r.impressions), clics: num(r.clicks),
      depense: num(r.spend), conversions: num(r.conversions), valeur: num(r.conversion_value), fenetre: "google_ads_defaut" })) }];
  },
  meta: async (du, au) => {
    const d = await windsor("facebook",
      ["date","account_id","campaign_id","campaign","objective","publisher_platform","impressions","clicks","link_clicks","spend","actions_purchase","action_values_purchase"],
      du, au, ["168512238364027"]);
    const p = await windsor("facebook",
      ["date","campaign_id","adset_id","adset_name","ad_id","ad_name","impressions","clicks","link_clicks","spend","actions_purchase","action_values_purchase"],
      du, au, ["168512238364027"]);
    return [
      { cible: "meta", lignes: d.map(r => ({
        jour: r.date, compte_id: String(r.account_id), campagne_id: String(r.campaign_id), campagne_nom: r.campaign,
        type_campagne: r.objective, reseau: r.publisher_platform, impressions: num(r.impressions), clics: num(r.clicks),
        clics_lien: num(r.link_clicks), depense: num(r.spend), conversions: num(r.actions_purchase),
        valeur: num(r.action_values_purchase), fenetre: "7d_click,1d_view" })) },
      { cible: "meta_pub", lignes: p.map(r => ({
        jour: r.date, campagne_id: String(r.campaign_id), groupe_id: String(r.adset_id ?? ""), groupe_nom: r.adset_name,
        pub_id: String(r.ad_id), pub_nom: r.ad_name, impressions: num(r.impressions), clics: num(r.clicks),
        clics_lien: num(r.link_clicks), depense: num(r.spend), conversions: num(r.actions_purchase), valeur: num(r.action_values_purchase) })) },
    ];
  },
  // GA4 : UNIQUEMENT des dimensions de session (jamais `campaign` ni `source_medium` sans préfixe)
  ga4: async (du, au) => {
    const d = await windsor("googleanalytics4",
      ["date","session_source_medium","session_default_channel_group","session_campaign_id","session_manual_campaign_name",
       "session_google_ads_campaign_name","session_manual_ad_content","sessions","engaged_sessions","totalusers","newusers",
       "transactions","purchase_revenue"], du, au, ["266731006"]);
    const t = await windsor("googleanalytics4",
      ["date","sessions","engaged_sessions","totalusers","transactions","purchase_revenue"], du, au, ["266731006"]);
    const pg = await windsor("googleanalytics4",
      ["date","landing_page","sessions","engaged_sessions","transactions","purchase_revenue"], du, au, ["266731006"]);
    const sansPage: Record<string, number> = {};
    for (const r of pg) if (!r.landing_page || r.landing_page === "(not set)") sansPage[r.date] = (sansPage[r.date] ?? 0) + Number(r.sessions);
    return [
      { cible: "ga4", lignes: d.map(r => {
        const [source, medium] = String(r.session_source_medium ?? "(not set)").split(" / ");
        const camp = ns(r.session_manual_campaign_name) || ns(r.session_google_ads_campaign_name) || "(not set)";
        return { jour: r.date, source, medium: medium ?? "(not set)", canal: r.session_default_channel_group,
          campagne: camp, campagne_id: ns(r.session_campaign_id), contenu: ns(r.session_manual_ad_content),
          sessions: num(r.sessions), sessions_engagees: num(r.engaged_sessions), utilisateurs: num(r.totalusers),
          nouveaux: num(r.newusers), transactions: num(r.transactions), ca: num(r.purchase_revenue) };
      }) },
      { cible: "ga4_total", lignes: t.map(r => ({ jour: r.date, sessions: num(r.sessions), sessions_engagees: num(r.engaged_sessions),
        utilisateurs: num(r.totalusers), transactions: num(r.transactions), ca: num(r.purchase_revenue), sans_page: sansPage[r.date] ?? 0 })) },
      { cible: "ga4_page", lignes: pg.map(r => ({ jour: r.date, page: r.landing_page, sessions: num(r.sessions),
        sessions_engagees: num(r.engaged_sessions), transactions: num(r.transactions), ca: num(r.purchase_revenue) })) },
    ];
  },
  seo: async (du, au) => {
    const tot = await windsor("searchconsole", ["date","clicks","impressions","ctr","position"], du, au, ["sc-domain:shine-group.fr"]);
    const d = await windsor("searchconsole", ["date","query","clicks","impressions","ctr","position"], du, au, ["sc-domain:shine-group.fr"]);
    return [{ cible: "seo", lignes: [
      ...tot.map(r => ({ jour: r.date, site: "shine-group.fr", requete: "(total)", clics: num(r.clicks), impressions: num(r.impressions), ctr: num(r.ctr), position: num(r.position) })),
      ...d.filter(r => Number(r.impressions) >= 20).map(r => ({ jour: r.date, site: "shine-group.fr", requete: r.query, clics: num(r.clicks), impressions: num(r.impressions), ctr: num(r.ctr), position: num(r.position) })),
    ] }];
  },
};

const iso = (d: Date) => d.toISOString().slice(0, 10);

Deno.serve(async (req) => {
  const jeton = req.headers.get("x-dc-jeton") ?? "";
  const { data: ok } = await sb.rpc("dc_verifier_jeton", { p_jeton: jeton });
  if (!ok) return new Response("Non autorisé", { status: 401 });

  const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};
  const auj = new Date();
  const au = body.au ?? iso(new Date(auj.getTime() - 86400000));
  const du = body.du ?? iso(new Date(auj.getTime() - 30 * 86400000));
  const sources: string[] = body.sources ?? Object.keys(SOURCES);
  const rapport: any[] = [];
  for (const s of sources) {
    try {
      const lots = await SOURCES[s](du, au);
      for (const lot of lots) {
        const { data, error } = await sb.rpc("dc_charger", { p_source: lot.cible, p_du: du, p_au: au, p_lignes: lot.lignes });
        if (error) { rapport.push({ source: lot.cible, erreur: error.message }); await sb.rpc("dc_journaliser", { p_source: lot.cible, p_du: du, p_au: au, p_statut: "erreur", p_message: error.message }); }
        else rapport.push(data);
      }
    } catch (e) {
      rapport.push({ source: s, erreur: String(e) });
      await sb.rpc("dc_journaliser", { p_source: s, p_du: du, p_au: au, p_statut: "erreur", p_message: String(e) });
    }
  }
  const { data: ctrl } = await sb.rpc("dc_controler", { p_du: du, p_au: au });
  return new Response(JSON.stringify({ du, au, rapport, controles: ctrl }), { headers: { "Content-Type": "application/json" } });
});
