// Livre des achats du mois en Excel (comptes 60 à 62, présentation du cabinet), fabriqué depuis le rangeur de factures (V6.1, 07/10/2026).
// Appel (flux n8n « Rangeur de factures · export comptable mensuel », chaque nuit) :
//   POST /functions/v1/livre-achats   en-tête  x-jeton-factures: <FACTURES_TOKEN>   { mois: "AAAA-MM" }
// Réponse : { nom: "AAAA-MM_SHINE_livre_achats_600-620.xlsx", xlsx: <base64>, factures, lignes, debit, credit, a_verifier, cca }
// Secrets Supabase : FACTURES_TOKEN ; lecture avec la clé service fournie par Supabase (fonction factures_livre_donnees).

import ExcelJS from "npm:exceljs@4.4.0";
import { createClient } from "npm:@supabase/supabase-js@2";
import { construireLivre, type Facture } from "./livre.ts";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Méthode non autorisée" }, 405);
  const jeton = Deno.env.get("FACTURES_TOKEN");
  if (!jeton) return json({ error: "Secret FACTURES_TOKEN absent dans Supabase" }, 500);
  if (req.headers.get("x-jeton-factures") !== jeton) return json({ error: "Jeton refusé" }, 401);
  let corps: { mois?: string };
  try { corps = await req.json(); } catch { return json({ error: "Requête illisible" }, 400); }
  const mois = corps.mois || "";
  if (!/^\d{4}-\d{2}$/.test(mois)) return json({ error: "mois attendu au format AAAA-MM" }, 400);
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc("factures_livre_donnees", { p_mois: mois });
  if (error) return json({ error: "Lecture impossible : " + error.message }, 500);
  try {
    const { nom, octets, resume } = await construireLivre(ExcelJS, mois, (data?.factures || []) as Facture[], data?.libelles || {});
    let bin = ""; for (let i = 0; i < octets.length; i += 0x8000) bin += String.fromCharCode(...octets.subarray(i, i + 0x8000));
    return json({ nom, xlsx: btoa(bin), ...resume });
  } catch (e) {
    return json({ error: "Livre impossible : " + (e as Error).message }, 500);
  }
});
