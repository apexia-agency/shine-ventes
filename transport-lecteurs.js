// Lecture des fichiers transporteurs (board Transport).
// Utilisé tel quel par le board (navigateur, glisser-déposer) et par outils/transport/charger.mjs (chargement initial).
// On lui donne un contenu déjà extrait : les lignes d'un Excel (tableau de tableaux) ou le texte des pages d'un PDF.
// Il renvoie { fichier, lignes } au format de la fonction SQL transport_importer, ou { erreur }.
//
// Règles (cahier des charges du board Transport) :
// - Coût HT d'un colis = transport + gasoil + taxes + annexes.
//   DPD : « Prix cumulé » ne contient que le transport ; on recompose avec l'indexation gasoil,
//   la participation sûreté + contribution logistique (taxes) et les colonnes « Fact. … » (annexes).
//   Colissimo : transport = port net, gasoil = CAE, taxes = décarbonation + SMIC, annexes = suppléments.
// - DPD : une ligne = un colis ; « Nombre de colis » à 0 = frais ajoutés sur un colis déjà facturé (pas un colis de plus).
//   Plusieurs colis sur une ligne = multi-colis.
// - Colissimo nouveau format (récapitulatif par service, sans détail par colis) : pas de poids ni de code postal.
(function (racine) {
  'use strict';

  const MODES = {
    dpd_dom: 'DPD · Domicile (Predict)', dpd_rel: 'DPD · Relais', dpd_cla: 'DPD · Classic', dpd_multi: 'DPD · Multi-colis',
    coli_dom: 'Colissimo · Domicile', coli_pr: 'Colissimo · Point retrait', coli_aut: 'Colissimo · Retours et autres'
  };
  const COMPTES_DPD = { '10635': 'relais', '10634': 'predict', '10633': 'classic' };

  const REGIONS = {
    'Auvergne-Rhône-Alpes': ['01', '03', '07', '15', '26', '38', '42', '43', '63', '69', '73', '74'],
    'Bourgogne-Franche-Comté': ['21', '25', '39', '58', '70', '71', '89', '90'], 'Bretagne': ['22', '29', '35', '56'],
    'Centre-Val de Loire': ['18', '28', '36', '37', '41', '45'],
    'Grand Est': ['08', '10', '51', '52', '54', '55', '57', '67', '68', '88'], 'Hauts-de-France': ['02', '59', '60', '62', '80'],
    'Île-de-France': ['75', '77', '78', '91', '92', '93', '94', '95'], 'Normandie': ['14', '27', '50', '61', '76'],
    'Nouvelle-Aquitaine': ['16', '17', '19', '23', '24', '33', '40', '47', '64', '79', '86', '87'],
    'Occitanie': ['09', '11', '12', '30', '31', '32', '34', '46', '48', '65', '66', '81', '82'],
    'Pays de la Loire': ['44', '49', '53', '72', '85'], "Provence-Alpes-Côte d'Azur": ['04', '05', '06', '13', '83', '84']
  };
  const DEP_REGION = {};
  for (const [r, ds] of Object.entries(REGIONS)) for (const d of ds) DEP_REGION[d] = r;

  function region(cp, pays) {
    const p = String(pays || 'FR').trim().toUpperCase();
    if (p && p !== 'FR' && p !== 'FRANCE') return 'Export / Europe';
    if (cp == null || cp === '') return 'Inconnue';
    const c = String(cp).trim().replace(/\s/g, '');
    if (c.startsWith('20')) return 'Corse';
    if (c.startsWith('97') || c.startsWith('98')) return 'Outre-mer';
    return DEP_REGION[c.slice(0, 2)] || 'Inconnue';
  }
  function tranche(kg) {
    if (kg == null || !(kg > 0)) return 'inconnue';
    if (kg < 1) return '0-1'; if (kg < 2) return '1-2'; if (kg < 5) return '2-5';
    if (kg < 10) return '5-10'; if (kg < 30) return '10-30'; return '30+';
  }
  const r2 = v => Math.round((+v || 0) * 100) / 100;
  // « 1 234,56 », « 1 234,56€ », 12.5 → nombre
  function num(v) {
    if (v == null || v === '') return 0;
    if (typeof v === 'number') return v;
    const s = String(v).replace(/[\s  €¤%]/g, '').replace(',', '.');
    const n = parseFloat(s);
    return isNaN(n) ? 0 : n;
  }
  const pad2 = n => String(n).padStart(2, '0');
  // Date Excel (numéro de série ou texte) → AAAA-MM-JJ
  function dateExcel(v) {
    if (v == null || v === '') return null;
    if (typeof v === 'number') {
      if (v < 20000 || v > 80000) return null;
      const d = new Date(Date.UTC(1899, 11, 30) + Math.round(v) * 864e5);
      return d.toISOString().slice(0, 10);
    }
    if (v instanceof Date) return `${v.getFullYear()}-${pad2(v.getMonth() + 1)}-${pad2(v.getDate())}`;
    const s = String(v).trim();
    let m = s.match(/^(\d{4})-(\d{2})-(\d{2})/); if (m) return `${m[1]}-${m[2]}-${m[3]}`;
    m = s.match(/^(\d{2})\/(\d{2})\/(\d{4})/); if (m) return `${m[3]}-${m[2]}-${m[1]}`;
    return null;
  }
  // Empreinte courte et stable d'un texte (FNV-1a 64 bits) : clé d'unicité d'une ligne, référence d'envoi anonymisée.
  function empreinte(s) {
    let h1 = 0x811c9dc5, h2 = 0x01000193;
    for (let i = 0; i < s.length; i++) {
      const c = s.charCodeAt(i);
      h1 = Math.imul(h1 ^ c, 16777619) >>> 0;
      h2 = Math.imul(h2 ^ c, 2246822519) >>> 0;
    }
    return h1.toString(36) + h2.toString(36);
  }

  // ---------------------------------------------------------------- DPD (export Excel mensuel)
  const ANNEXES_EXACTES = new Set(['coût de la vd', 'cout de la vd', 'taxe collection request', 'taxe consolidation', 'taxe fixe', 'supplément prédict', 'supplement predict']);
  function libAnnexe(h) {
    return h.replace(/^fac(t)?\.?\s*/i, '').replace(/^statuts?\s+/i, '').replace(/^\s+|\s+$/g, '').replace(/^./, c => c.toUpperCase());
  }

  function lireDPD(rows, nomFichier) {
    if (!rows || !rows.length) return { erreur: 'fichier vide' };
    const iEntete = rows.slice(0, 5).findIndex(r => (r || []).some(x => String(x ?? '').trim().toLowerCase() === 'date expédition'));
    if (iEntete < 0) return { erreur: 'pas un export DPD (colonne « Date expédition » introuvable)' };
    const H = rows[iEntete].map(x => String(x ?? '').trim().toLowerCase());
    const col = (...noms) => { for (const n of noms) { const i = H.indexOf(n); if (i >= 0) return i; } return -1; };
    const C = {
      fac: col('no facture'), dfac: col('date de facture'), date: col('date expédition'), compte: col('no de compte'),
      nb: col('nombre de colis'), colis: col('n° colis'), ref: col('votre référence 1'), cp: col('cp destinataire'),
      pays: col('code pays destinataire'), poids: col('poids'), pt: col('prix transport'), pcum: col('prix cumulé'),
      gas: col('indexation gasoil'), sur: col('participation sureté', 'participation sûreté'),
      clr: col('contribution logistique responsable'), type: col('type dpd')
    };
    const annexes = [];
    H.forEach((h, i) => {
      if (!h || /^(nombre|nb|nbr|nbre)\b/.test(h)) return;
      if (h.startsWith('fac') || ANNEXES_EXACTES.has(h)) annexes.push([i, libAnnexe(rows[iEntete][i] ? String(rows[iEntete][i]).trim() : h)]);
    });
    const lignes = []; const comptes = {}; const factures = new Set();
    let dmin = null, dmax = null, dfacMax = null;
    for (const r of rows.slice(iEntete + 1)) {
      if (!r) continue;
      const numColis = String(r[C.colis] ?? '').trim();
      if (!/^\d{8,}$/.test(numColis)) continue; // lignes de totaux en fin de fichier
      const d = dateExcel(r[C.date]);
      if (!d) continue;
      const compte = String(r[C.compte] ?? '').trim();
      comptes[compte] = (comptes[compte] || 0) + 1;
      const nb = Math.max(0, Math.round(num(r[C.nb])));
      const typeTxt = C.type >= 0 ? String(r[C.type] ?? '').toLowerCase() : '';
      let pt = C.pt >= 0 ? num(r[C.pt]) : 0;
      if (!pt && C.pcum >= 0) pt = num(r[C.pcum]);
      const gas = C.gas >= 0 ? num(r[C.gas]) : 0;
      const tax = (C.sur >= 0 ? num(r[C.sur]) : 0) + (C.clr >= 0 ? num(r[C.clr]) : 0);
      const det = {}; let ann = 0;
      for (const [i, lib] of annexes) { const v = num(r[i]); if (v) { det[lib] = r2((det[lib] || 0) + v); ann += v; } }
      let cp = r[C.cp]; const pays = String(r[C.pays] ?? 'FR').trim().toUpperCase() || 'FR';
      if (typeof cp === 'number' && pays === 'FR') cp = String(cp).padStart(5, '0');
      cp = cp == null ? null : String(cp).trim();
      const kg = C.poids >= 0 ? num(r[C.poids]) : 0;
      const fac = String(r[C.fac] ?? '').trim();
      factures.add(fac);
      const df = C.dfac >= 0 ? dateExcel(r[C.dfac]) : null;
      if (df && (!dfacMax || df > dfacMax)) dfacMax = df;
      if (!dmin || d < dmin) dmin = d; if (!dmax || d > dmax) dmax = d;
      const ref = C.ref >= 0 ? String(r[C.ref] ?? '').trim() : '';
      lignes.push({
        compte, nb, multi: nb > 1 || typeTxt.includes('multi'),
        date_envoi: d, num_facture: fac || null, num_colis: numColis,
        ref_envoi: ref ? empreinte('dpd|' + ref) : null,
        // Multi-colis : le poids est celui de l'envoi ; la tranche se lit au poids moyen d'un colis
        colis: nb, poids_kg: kg > 0 ? r2(kg * 1000) / 1000 : null, cp, pays, region: region(cp, pays), tranche: nb ? tranche(kg / nb) : 'frais',
        transport: r2(pt), gasoil: r2(gas), taxes: r2(tax), annexes: r2(ann), annexes_detail: Object.keys(det).length ? det : null,
        cle: empreinte(['dpd', fac, numColis, d, nb, kg, r2(pt), r2(gas), r2(tax), r2(ann)].join('|'))
      });
    }
    if (!lignes.length) return { erreur: 'aucun colis lu dans cet export DPD' };
    // Service : d'après le n° de compte DPD (le plus fréquent), sinon d'après le nom du fichier
    const compte = Object.entries(comptes).sort((a, b) => b[1] - a[1])[0][0];
    const nom = String(nomFichier || '').toLowerCase();
    const service = COMPTES_DPD[compte] || (nom.includes('relai') ? 'relais' : nom.includes('predict') ? 'predict' : (nom.includes('classic') || nom.includes('multi')) ? 'classic' : null);
    if (!service) return { erreur: `compte DPD ${compte} inconnu (ni Relais, ni Predict, ni Classic)` };
    for (const l of lignes) {
      l.mode = service === 'relais' ? 'dpd_rel' : service === 'predict' ? 'dpd_dom' : (l.multi ? 'dpd_multi' : 'dpd_cla');
      l.code_service = service;
      delete l.compte; delete l.nb; delete l.multi;
    }
    const tot = k => r2(lignes.reduce((a, l) => a + l[k], 0));
    const mois = (dfacMax || dmax).slice(0, 7);
    return {
      fichier: {
        transporteur: 'DPD', format: 'dpd_excel', service, compte, nom_fichier: nomFichier || null,
        num_facture: [...factures].filter(Boolean).join(', ') || null, date_facture: dfacMax, mois,
        periode_du: dmin, periode_au: dmax, colis: lignes.reduce((a, l) => a + l.colis, 0), nb_lignes: lignes.length,
        montant_ht: r2(tot('transport') + tot('gasoil') + tot('taxes') + tot('annexes')),
        details: { transport: tot('transport'), gasoil: tot('gasoil'), taxes: tot('taxes'), annexes: tot('annexes') }
      },
      lignes
    };
  }

  // ---------------------------------------------------------------- Colissimo (facture PDF)
  const CODES_COLI = {
    '6A': 'coli_dom', '6C': 'coli_dom', 'CA': 'coli_dom', 'CB': 'coli_dom', 'DOS': 'coli_dom',
    '9H': 'coli_pr', '9M': 'coli_pr', '6H': 'coli_pr', '6M': 'coli_pr', 'CM': 'coli_pr', 'CI': 'coli_pr', 'CG': 'coli_pr',
    '8R': 'coli_aut', '7R': 'coli_aut'
  };
  function modeColissimo(code, libelle) {
    const l = String(libelle || '').toLowerCase();
    if (l.includes('retour')) return 'coli_aut';
    if (l.includes('domicile')) return 'coli_dom';
    if (/retrait|consigne|poste|\bpu\b/.test(l)) return 'coli_pr';
    return CODES_COLI[code] || 'coli_aut';
  }
  const MONTANT = '-?(?:\\d{1,3}[ \\u00a0\\u202f])*\\d{1,3},\\d{2}';
  const reMontant = new RegExp(MONTANT);
  function recap(txt, libelle) {
    const m = txt.match(new RegExp(libelle + '\\s+(' + MONTANT + ')\\s*[¤€]', 'i'));
    return m ? num(m[1]) : null;
  }

  // Détail par colis (ancien format) :
  // Date | N° colis | Destination (pays pays CP) | Poids | Dim. | Port brut | Tx remise | Remise | Port net | CAE | Décarbonation | SMIC | TOTAL HT
  const E = '(' + MONTANT + ')€';
  const LIGNE_COLIS = new RegExp(
    '(\\d{2})/(\\d{2}) ([0-9A-Z]{2}\\d{9,11}(?:[A-Z]{2})?) ([A-Z]{2}) ([A-Z]{2}) (\\S+) (\\d+,\\d+) (\\S+|non mesuré) ' +
    E + ' (\\d+,\\d+)% ' + E + ' ' + E + ' ' + E + ' ' + E + ' ' + E + ' ' + E, 'g');
  const SUPPLEMENT = /^Supplément\s*:\s*(.+?)\s+(\d+,\d{2})€\s*$/;

  function lireColissimo(pages, nomFichier) {
    const tout = pages.join('\n');
    const plat = tout.replace(/\s+/g, ' ');
    const bas = plat.toLowerCase();
    const mFac = plat.match(/Facture N°\s*(CO\d+)/i);
    if (!mFac || (!bas.includes('colissimo') && !bas.includes('la poste'))) {
      if (bas.includes('dpd')) return { erreur: 'facture ou avoir DPD en PDF : le board lit les exports Excel DPD (détail par colis)' };
      return { erreur: 'pas une facture Colissimo' };
    }
    const numFacture = mFac[1];
    const mPer = plat.match(/du (\d{2})\/(\d{2})\/(\d{4}) au (\d{2})\/(\d{2})\/(\d{4})/i);
    const mDate = plat.match(/Facture N°\s*CO\d+\s+du (\d{2})\/(\d{2})\/(\d{4})/i);
    let du = null, au = null;
    if (mPer) { du = `${mPer[3]}-${mPer[2]}-${mPer[1]}`; au = `${mPer[6]}-${mPer[5]}-${mPer[4]}`; }
    const dateFacture = mDate ? `${mDate[3]}-${mDate[2]}-${mDate[1]}` : au;
    if (!au && dateFacture) { au = dateFacture; du = dateFacture.slice(0, 8) + '01'; }
    if (!au) return { erreur: 'période de la facture introuvable' };
    const mCompte = plat.match(/N° COMPTE CLIENT\s*:?\s*(\d+)/i);
    const compte = mCompte ? mCompte[1] : null;
    const [y0, m0] = du.split('-').map(Number), [y1, m1] = au.split('-').map(Number);
    const annee = mo => mo === m1 ? y1 : mo === m0 ? y0 : (mo <= m1 ? y1 : y0);

    // Libellés de service : « 6A - Colissimo Domicile Sans Sign. F »
    const libs = {};
    for (const m of plat.matchAll(/\b([0-9A-Z]{2}) - (Colissimo [^-]+?) (?:- TVA|EU |France )/g)) if (!libs[m[1]]) libs[m[1]] = m[2].trim();

    const lignes = [];
    // ---- Ancien format : une ligne par colis, suppléments sur les lignes qui suivent
    for (const page of pages) {
      const lignesTexte = page.split('\n').map(s => s.replace(/\s+/g, ' ').trim()).filter(Boolean);
      let dernier = null;
      for (const t of lignesTexte) {
        LIGNE_COLIS.lastIndex = 0;
        const found = [...t.matchAll(LIGNE_COLIS)];
        if (found.length) {
          for (const m of found) {
            const mo = +m[2], jj = +m[1];
            const d = `${annee(mo)}-${pad2(mo)}-${pad2(jj)}`;
            const suivi = m[3], code = suivi.slice(0, 2);
            const kg = num(m[7]);
            const net = num(m[12]), cae = num(m[13]), dec = num(m[14]), smic = num(m[15]), total = num(m[16]);
            const pays = m[5];
            const cp = m[6];
            dernier = {
              mode: modeColissimo(code, libs[code]), code_service: code, date_envoi: d, num_facture: numFacture, num_colis: suivi,
              ref_envoi: null, colis: 1, poids_kg: kg || null, cp, pays, region: region(cp, pays), tranche: tranche(kg),
              transport: r2(net), gasoil: r2(cae), taxes: r2(dec + smic), annexes: 0, annexes_detail: null,
              _total: total, cle: empreinte(['coli', numFacture, suivi, d, r2(total)].join('|'))
            };
            lignes.push(dernier);
          }
          continue;
        }
        const s = t.match(SUPPLEMENT);
        if (s && dernier) {
          const v = num(s[2]);
          const lib = s[1].replace(/^Supp\.\s*/i, '').trim();
          dernier.annexes = r2(dernier.annexes + v);
          dernier.annexes_detail = Object.assign(dernier.annexes_detail || {}, { [lib]: r2(((dernier.annexes_detail || {})[lib] || 0) + v) });
        }
      }
    }
    // Deux colis identiques sur une même facture (même n°, même date, même montant) : on garde les deux
    const vus = {};
    for (const l of lignes) { const k = l.cle; vus[k] = (vus[k] || 0) + 1; if (vus[k] > 1) l.cle = empreinte(k + '#' + vus[k]); delete l._total; }

    let format = 'colissimo_pdf';
    // ---- Nouveau format : récapitulatif par service et par tarif (pas de détail par colis)
    if (!lignes.length) {
      format = 'colissimo_pdf_recap';
      const fin = au;
      const debut = plat.search(/FRAIS DE PORT HORS OPTIONS/i);
      const finPort = plat.search(/Total FRAIS DE PORT/i);
      const zone = debut >= 0 ? plat.slice(debut, finPort > debut ? finPort : undefined) : '';
      const reLigne = new RegExp('(?:^| )(\\d+) ([0-9A-Z]{2}) - (Colissimo .+?) (EU|France métropolitaine) (\\d+) (\\d+,\\d{2}) (' + MONTANT + ') (?:(-' + MONTANT.slice(2) + ') (?:\\S+ )?)?(' + MONTANT + ') 20,00 % S', 'g');
      const base = [];
      for (const m of zone.matchAll(reLigne)) {
        const qte = +m[5], pu = num(m[6]), brut = num(m[7]), net = num(m[9]);
        if (Math.abs(qte * pu - brut) > 0.05 + brut * 0.001) continue; // ligne mal lue : on l'écarte plutôt que d'inventer
        base.push({ no: m[1], code: m[2], lib: m[3].trim(), dest: m[4], qte, pu, brut, net });
      }
      if (!base.length) return { erreur: 'facture Colissimo : ni détail par colis, ni récapitulatif par service lisible' };
      const totalAvec = lib => { const m = plat.match(new RegExp('Total ' + lib + '[^0-9-]*(' + MONTANT + ')(?: (' + MONTANT + '))*', 'i')); if (!m) return 0; const nums = m[0].match(new RegExp(MONTANT, 'g')); return num(nums[nums.length - 1]); };
      const cae = totalAvec('COEFFICIENT AJUSTEMENT ENERGIE');
      const smic = totalAvec('AJUSTEMENT SMIC');
      const supp = totalAvec('SUPPLEMENTS');
      let decarb = 0;
      for (const m of plat.matchAll(new RegExp('décarbonation (?:EU|France métropolitaine) (\\d+) (\\d+,\\d{2}) (' + MONTANT + ')', 'gi'))) decarb += num(m[3]);
      const totNet = base.reduce((a, b) => a + b.net, 0) || 1;
      for (const b of base) {
        const part = b.net / totNet;
        const eu = b.dest === 'EU' || !/france/i.test(b.dest);
        lignes.push({
          mode: modeColissimo(b.code, b.lib), code_service: b.code, date_envoi: fin, num_facture: numFacture, num_colis: null, ref_envoi: null,
          colis: b.qte, poids_kg: null, cp: null, pays: eu ? 'EU' : 'FR', region: eu ? 'Export / Europe' : 'Inconnue', tranche: 'inconnue',
          transport: r2(b.net), gasoil: r2(cae * part), taxes: r2((smic + decarb) * part), annexes: r2((supp - decarb) * part),
          annexes_detail: { 'Tarif unitaire brut': b.pu },
          cle: empreinte(['coli', numFacture, 'recap', b.no, b.code, b.qte, b.brut].join('|'))
        });
      }
    }

    // Récapitulatif de la facture (pour le contrôle et la grille de couverture)
    const tot = k => r2(lignes.reduce((a, l) => a + l[k], 0));
    const rc = {
      port_net: recap(plat, 'Port Net'), cae: recap(plat, 'Coefficient Ajustement Energie'), supplements: recap(plat, 'Supplements'),
      smic: recap(plat, 'Ajustement SMIC'),
      prestations: recap(plat, 'Prestations Complementaires'), indemnisations: recap(plat, 'Indemnisations'),
      avoirs: recap(plat, 'Avoirs'), regularisations: recap(plat, 'Regularisations'), total_ht: recap(plat, 'TOTAL HT')
    };
    // Ancien format : ce que le détail par colis n'explique pas (suppléments non rattachés à un colis, arrondis)
    // devient une ligne « ajustement de facture » par service, au prorata du port net. Le total retombe sur la facture.
    if (format === 'colissimo_pdf' && rc.port_net != null) {
      // Les suppléments du récapitulatif comprennent la décarbonation (déjà dans les taxes de chaque colis) :
      // ce qui manque aux taxes + annexes des colis va en annexes.
      const ecarts = {
        transport: r2(rc.port_net - tot('transport')),
        gasoil: r2((rc.cae || 0) - tot('gasoil')),
        annexes: r2((rc.supplements || 0) + (rc.smic || 0) - tot('taxes') - tot('annexes'))
      };
      if (Object.values(ecarts).some(v => Math.abs(v) >= 0.01)) {
        const parMode = {};
        for (const l of lignes) parMode[l.mode] = (parMode[l.mode] || 0) + l.transport;
        const totT = Object.values(parMode).reduce((a, b) => a + b, 0) || 1;
        const modes = Object.keys(parMode).length ? Object.keys(parMode) : ['coli_aut'];
        const reste = { ...ecarts };
        modes.forEach((mode, i) => {
          const part = (parMode[mode] || totT) / totT, der = i === modes.length - 1;
          const v = k => der ? r2(reste[k]) : r2(ecarts[k] * part);
          const a = { transport: v('transport'), gasoil: v('gasoil'), taxes: 0, annexes: v('annexes') };
          for (const k of ['transport', 'gasoil', 'annexes']) reste[k] = r2(reste[k] - a[k]);
          lignes.push({
            mode, code_service: 'ajustement', date_envoi: au, num_facture: numFacture, num_colis: null, ref_envoi: null,
            colis: 0, poids_kg: null, cp: null, pays: null, region: 'Inconnue', tranche: 'frais', ...a,
            annexes_detail: { 'Ajustement de facture (suppléments non rattachés à un colis, arrondis)': a.annexes },
            cle: empreinte(['coli', numFacture, 'ajustement', mode].join('|'))
          });
        });
      }
    }
    const montant = r2(tot('transport') + tot('gasoil') + tot('taxes') + tot('annexes'));
    if (format === 'colissimo_pdf_recap') {
      const t = (lib) => { const m = plat.match(new RegExp('Total ' + lib + '[^0-9-]*((?:' + MONTANT + ' ?)+)', 'i')); if (!m) return null; const n = m[1].match(new RegExp(MONTANT, 'g')); return num(n[n.length - 1]); };
      rc.port_net = rc.port_net ?? t('FRAIS DE PORT hors options et hors suppléments');
      rc.cae = rc.cae ?? t('COEFFICIENT AJUSTEMENT ENERGIE');
      rc.supplements = rc.supplements ?? t('SUPPLEMENTS');
      rc.prestations = rc.prestations ?? t('PRESTATIONS COMPLEMENTAIRES');
      rc.indemnisations = rc.indemnisations ?? t('INDEMNISATIONS');
      rc.smic = t('AJUSTEMENT SMIC');
    }
    return {
      fichier: {
        transporteur: 'Colissimo', format, service: null, compte, nom_fichier: nomFichier || null, num_facture: numFacture,
        date_facture: dateFacture, mois: au.slice(0, 7), periode_du: du, periode_au: au,
        colis: lignes.reduce((a, l) => a + l.colis, 0), nb_lignes: lignes.length, montant_ht: montant,
        prestations_ht: rc.prestations || 0, indemnites_ht: rc.indemnisations || 0, avoirs_ht: r2((rc.avoirs || 0) + (rc.regularisations || 0)),
        total_facture_ht: rc.total_ht,
        details: { transport: tot('transport'), gasoil: tot('gasoil'), taxes: tot('taxes'), annexes: tot('annexes'), recap: rc }
      },
      lignes
    };
  }

  const api = { lireDPD, lireColissimo, region, tranche, MODES, empreinte };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else racine.TransportLecteurs = api;
})(typeof window !== 'undefined' ? window : globalThis);
