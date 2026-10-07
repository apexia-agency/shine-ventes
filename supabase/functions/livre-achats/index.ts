// Livre des achats du mois en Excel (comptes 60 à 62, présentation du cabinet), fabriqué depuis le rangeur de factures (V7, 07/10/2026),
// avec l'onglet « Rapprochement banque ». Deux actions, protégées par le jeton du rangeur :
//   POST /functions/v1/livre-achats   en-tête  x-jeton-factures: <FACTURES_TOKEN>
//   { mois: "AAAA-MM" }                  → { nom, xlsx: <base64>, factures, lignes, debit, credit, a_verifier, cca, banque: {…} }
//   { releve: { nom, contenu } }         → charge un relevé (CSV CA, CIC ou PayPal, contenu en base64) dans banque_operations, sans doublon
// Appelé chaque nuit par les flux n8n « Rangeur de factures · export comptable mensuel » et « Rangeur de factures · relevés bancaires ».
// Secrets Supabase : FACTURES_TOKEN ; lecture et écriture avec la clé service fournie par Supabase.

import ExcelJS from "npm:exceljs@4.4.0";
import { createClient } from "npm:@supabase/supabase-js@2";
import { construireLivre, type Facture } from "./livre.ts";
import { classer, lireReleve, rapprocher, type Operation } from "./banque.ts";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

// Le Crédit Agricole et le CIC exportent en Windows-1252, PayPal en UTF-8 (avec BOM)
function decoder(octets: Uint8Array): string {
  const utf8 = new TextDecoder("utf-8", { fatal: false }).decode(octets);
  return utf8.includes("�") ? new TextDecoder("windows-1252").decode(octets) : utf8;
}
async function empreinte(s: string) {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)))].map((x) => x.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Méthode non autorisée" }, 405);
  const jeton = Deno.env.get("FACTURES_TOKEN");
  if (!jeton) return json({ error: "Secret FACTURES_TOKEN absent dans Supabase" }, 500);
  if (req.headers.get("x-jeton-factures") !== jeton) return json({ error: "Jeton refusé" }, 401);
  let corps: { mois?: string; releve?: { nom?: string; contenu?: string } };
  try { corps = await req.json(); } catch { return json({ error: "Requête illisible" }, 400); }
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

  // Chargement d'un relevé bancaire
  if (corps.releve) {
    const { nom = "releve.csv", contenu } = corps.releve;
    if (!contenu) return json({ error: "contenu (base64) obligatoire" }, 400);
    const texte = decoder(Uint8Array.from(atob(contenu), (c) => c.charCodeAt(0)));
    const ops = lireReleve(nom, texte);
    if (!ops.length) return json({ error: `aucune opération reconnue dans « ${nom} » (CSV Crédit Agricole, CIC ou PayPal attendu)` }, 422);
    // Empreinte : deux opérations identiques le même jour restent deux opérations (rang d'apparition), un relevé rechargé ne double rien
    const rang = new Map<string, number>();
    const lignes = [];
    for (const o of ops) {
      const cle = [o.banque, o.date, o.libelle, o.debit, o.credit].join("|");
      const n = (rang.get(cle) || 0) + 1; rang.set(cle, n);
      lignes.push({ empreinte: await empreinte(cle + "|" + n), banque: o.banque, date: o.date, libelle: o.libelle, debit: o.debit, credit: o.credit, fichier: nom });
    }
    const { data, error } = await sb.from("banque_operations").upsert(lignes, { onConflict: "empreinte", ignoreDuplicates: true }).select("id");
    if (error) return json({ error: "Écriture impossible : " + error.message }, 500);
    const dates = ops.map((o) => o.date).sort();
    return json({ fichier: nom, banque: ops[0].banque, lues: ops.length, nouvelles: data?.length ?? 0, du: dates[0], au: dates[dates.length - 1] });
  }

  // Livre du mois
  const mois = corps.mois || "";
  if (!/^\d{4}-\d{2}$/.test(mois)) return json({ error: "mois attendu au format AAAA-MM" }, 400);
  const [{ data, error }, { data: b, error: eb }] = await Promise.all([
    sb.rpc("factures_livre_donnees", { p_mois: mois }),
    sb.rpc("factures_banque_donnees", { p_mois: mois }),
  ]);
  if (error || eb) return json({ error: "Lecture impossible : " + (error || eb)!.message }, 500);
  try {
    let banque = null;
    if (b?.operations?.length) {
      const ops = (b.operations as Operation[]).map((o) => classer({ ...o, debit: +o.debit, credit: +o.credit }, b.regles || []));
      banque = { operations: ops, ...rapprocher(b.factures || [], ops, (b.livre || []).map((g: { date: string; libelle: string; debit: number }) => ({ ...g, debit: +g.debit })), b.correspondances || [],
        (b.anterieures || []).map((o: Operation) => ({ ...o, debit: +o.debit, credit: 0 }))) };
    }
    const { nom, octets, resume } = await construireLivre(ExcelJS, mois, (data?.factures || []) as Facture[], data?.libelles || {}, banque, b?.factures || []);
    let bin = ""; for (let i = 0; i < octets.length; i += 0x8000) bin += String.fromCharCode(...octets.subarray(i, i + 0x8000));
    return json({ nom, xlsx: btoa(bin), ...resume });
  } catch (e) {
    return json({ error: "Livre impossible : " + (e as Error).message }, 500);
  }
});
