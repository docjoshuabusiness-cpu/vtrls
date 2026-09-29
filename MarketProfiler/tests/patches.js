// Patch di MarketProfiler.mq5: ogni punto di aggancio deve comparire esattamente una volta
var MP_MARK = 'MarketProfilerEdge.mqh - modulo aggiunto';

var MP_PATCHES = [
  { id: 1, name: 'Sezioni del riepilogo: 18 -> 21',
    re: /#define\s+HI_NMOD\s+18\b/,
    rep: function () { return '#define HI_NMOD 21'; } },
  { id: 2, name: 'Nomi delle tre nuove sezioni del riepilogo',
    re: /\(coppia contro tutte le altre candele\)"\s*\}\s*;/,
    rep: function () { return '(coppia contro tutte le altre candele)", "", "", ""};'; } },
  { id: 3, name: 'Inserimento del modulo (prima di Analyze)',
    re: /^\/\/\+-+\+[ \t]*\n\/\/\| Analisi di un simbolo/m,
    rep: function (m, mod) { return mod + '\n\n' + m; } },
  { id: 4, name: 'Azzeramento all\'inizio dell\'analisi',
    re: /^([ \t]*)Comment\("MarketProfiler ", sym, ": costi dei broker \.\.\."\);/m,
    rep: function (m, mod, g1) { return g1 + 'EdgeReset();\n' + m; } },
  { id: 5, name: 'Raccolta dei candidati R/R',
    re: /^([ \t]*)string ctl = \(MathIsValidNumber\(g_ckZh\[c\]\)/m,
    rep: function (m, mod, g1) { return g1 + 'EdgeAddRR(nm, c, id, rs, ok);\n' + m; } },
  { id: 6, name: 'Pulsante Sintesi edge',
    re: /<button data-tab='overview'>Panoramica<\/button>/,
    rep: function (m) { return "<button data-tab='edge'>Sintesi edge</button>" + m; } },
  { id: 7, name: 'Pulsante Bias e impulsi',
    re: /<button data-tab='mtf'>Alto &rarr; basso<\/button>/,
    rep: function (m) { return m + "<button data-tab='bias'>Bias e impulsi</button><button data-tab='cand'>Candele</button>"; } },
  { id: 8, name: 'Pulsante testo Sintesi edge',
    re: /<button data-tab='report'>Rapporto completo<\/button>/,
    rep: function (m) { return m + "<button data-tab='txedge'>Sintesi edge</button>"; } },
  { id: 9, name: 'Pulsante testo Bias e impulsi',
    re: /<button data-tab='txmtf'>Alto &rarr; basso<\/button>/,
    rep: function (m) { return m + "<button data-tab='txbias'>Bias e impulsi</button><button data-tab='txcand'>Candele</button><button data-tab='txcandtf'>Candele: ogni timeframe</button>"; } },
  { id: 10, name: 'Scheda Bias e impulsi',
    re: /(MtfTab\(m5, 300\);\s*W\("<\/div>"\);)/,
    rep: function (m) {
      return m + '\n   Comment("MarketProfiler ", sym, ": bias e impulsi ...");\n   W("<div class=\'tab\' id=\'tab-bias\' hidden>");\n' +
             '   BiasTab(h1, d1);\n   W("</div>");\n' +
             '   Comment("MarketProfiler ", sym, ": candele su tutti i timeframe ...");\n   W("<div class=\'tab\' id=\'tab-cand\' hidden>");\n' +
             '   if(m1.n > 5000)\n      CandTab(m1, 60, clean);\n   else\n      CandTab(m5, 300, clean);\n   W("</div>");';
    } },
  { id: 11, name: 'Scheda Sintesi edge',
    re: /HiTab\(\);(\s*)W\("<\/div><div class='tab' id='tab-report' hidden>"\);/,
    rep: function (m, mod, g1) {
      return 'HiTab();\n   W("</div><div class=\'tab\' id=\'tab-edge\' hidden>");\n   EdgeTab(sym);\n   W("</div><div class=\'tab\' id=\'tab-report\' hidden>");';
    } },
  { id: 12, name: 'Rapporto completo: sezione 0 (Sintesi edge)',
    re: /W\(RepIndex\(\)\);/,
    rep: function (m) {
      return m + '\n   W("\\n=== 0. SINTESI EDGE: verdetto, candidati, test multipli, bias del momento, profilo e bias robusti ===\\n");\n   W(g_repEdge);';
    } },
  { id: 13, name: 'Rapporto completo: sezione 15 (Bias e impulsi)',
    re: /W\(g_repMtf\);/,
    rep: function (m) {
      return m + '\n   W("\\n=== 15. BIAS E IMPULSI: ora, giorno, mese, trimestre, semestre; massimo e minimo della settimana; impulso piu\' forte, massimo e minimo del giorno e cosa li precede ===\\n");\n   W(g_repBias);' +
             '\n   W("\\n=== 16. CANDELE: tutti i 21 timeframe da M1 a MN1, riepilogo, quando si muove di piu\' e confronti robusti (il testo di ogni timeframe e\' nell\'appendice G) ===\\n");\n   W(g_cxTxt);';
    } },
  { id: 14, name: 'Schede di testo da copiare',
    re: /^([ \t]*)TxTab\("txvol",/m,
    rep: function (m, mod, g1) {
      return g1 + 'TxTab("txedge", "Testo: sintesi edge", "Verdetto, candidati con tutti i controlli, test multipli, bias del momento, profilo di ore e giorni e bias robusti.", "SINTESI EDGE - " + sym + "\\n" + g_repEdge);\n' +
             g1 + 'TxTab("txbias", "Testo: bias e impulsi", "Bias di ora, giorno, mese, trimestre e semestre; ora x giorno; massimo e minimo della settimana; impulso piu\' forte del giorno e cosa lo precede.", "BIAS E IMPULSI - " + sym + "\\n" + g_repBias);\n' +
             g1 + 'TxTab("txcand", "Testo: candele", "Riepilogo dei 21 timeframe da M1 a MN1, quando si muove di piu\' timeframe per timeframe e i confronti piu\' solidi. Il testo completo di ogni timeframe e\' nella scheda successiva.", "CANDELE - " + sym + "\\n" + g_cxTxt);\n' +
             g1 + 'TxTab("txcandtf", "Testo: candele, ogni timeframe", "Per ogni timeframe: confronti robusti, dove si muove di piu\', eventi piu\' frequenti, ora/minuto/giorno/settimana del mese/mese/trimestre/anno, forme, pattern, serie, stati, coppie e terne, impulsi e cosa li precede. Molto lungo: copia un timeframe alla volta dalla scheda Candele.", "CANDELE - TESTO DI OGNI TIMEFRAME - " + sym + "\\n" + g_cxTxtTf);\n' + m;
    } },
  { id: 18, name: 'Indice del rapporto: sezioni 0, 15 e 16',
    re: /PARTE PRINCIPALE \(da leggere; per l'analisi in chat basta questa\)\\n"([\s\S]*?)"    14\. Dal timeframe alto al basso: stato della candela H4, D1 e settimanale e comportamento dei timeframe inferiori\\n" \+/,
    rep: function (m, mod, g1) {
      var a = m.replace("basta questa)\\n\"", "basta questa)\\n    0. Sintesi edge: verdetto, candidati strategia, test multipli, bias del momento, profilo di ore e giorni\\n\"");
      return a + '\n        "    15. Bias e impulsi: ora, giorno, mese, trimestre, semestre; massimo e minimo della settimana; impulso piu\' forte del giorno e cosa lo precede\\n" +' +
             '\n        "    16. Candele: tutti i 21 timeframe da M1 a MN1 (riepilogo, quando si muove di piu\', confronti robusti)\\n" +';
    } },
  { id: 19, name: 'Indice del rapporto: appendice G',
    re: /F\. Dal timeframe alto al basso: tutte le coppie di stati\\n\\n"/,
    rep: function () { return 'F. Dal timeframe alto al basso: tutte le coppie di stati\\n    G. Candele: testo completo di ogni timeframe\\n\\n"'; } },
  { id: 20, name: 'Rapporto completo: appendice G (candele)',
    re: /WT\(g_txMtfAll\);(\s*)W\("<\/textarea>"\);/,
    rep: function (m, mod, g1) {
      return 'WT(g_txMtfAll);\n   W("\\n=== APPENDICE G. CANDELE: testo completo di ogni timeframe ===\\n");\n   W(g_cxTxtTf);' + g1 + 'W("</textarea>");';
    } },
  { id: 15, name: 'Scheda iniziale: Sintesi edge (apertura della pagina)',
    re: /\)\)id='overview';/,
    rep: function () { return "))id='edge';"; } },
  { id: 16, name: 'Scheda iniziale: Sintesi edge (indirizzo senza scheda)',
    re: /\|\|'overview'\);/,
    rep: function () { return "||'edge');"; } },
  { id: 17, name: 'Correzione: intestazione del Riepilogo con colonne sfalsate',
    re: /Oltre \|z\| 3\|Attesi per caso\|Tra \|z\| 2 e 3\|Attesi per caso/,
    rep: function () { return 'Oltre z 3|Attesi per caso|Tra z 2 e 3|Attesi per caso'; },
    optional: true }
];

// applica tutte le patch; ritorna { ok, results[], text }
function mpApply(src, moduleSrc) {
  var text = src.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  var results = [];
  if (text.indexOf(MP_MARK) >= 0 || /\bEdgeTab\s*\(\s*sym\s*\)/.test(text)) {
    return { ok: false, already: true, results: results, text: '' };
  }
  var ok = true;
  // prima verifica: ogni aggancio esattamente una volta
  for (var i = 0; i < MP_PATCHES.length; i++) {
    var p = MP_PATCHES[i];
    var g = new RegExp(p.re.source, p.re.flags.replace('g', '') + 'g');
    var found = text.match(g);
    var n = found ? found.length : 0;
    var st = n === 1 ? 'ok' : (n === 0 ? 'manca' : 'multiplo');
    if (p.optional && n === 0) st = 'saltata';
    results.push({ id: p.id, name: p.name, count: n, status: st });
    if (st !== 'ok' && st !== 'saltata') ok = false;
  }
  if (!ok) return { ok: false, results: results, text: '' };
  // seconda fase: applicazione (gli agganci sono indipendenti; il modulo entra per ultimo cosi' le altre patch non lo toccano)
  var mod = '';
  for (var j = 0; j < MP_PATCHES.length; j++) {
    var q = MP_PATCHES[j];
    if (q.id === 3) continue;
    if (results[j].status !== 'ok') continue;
    text = text.replace(q.re, function () {
      var a = Array.prototype.slice.call(arguments);
      var m = a[0];
      var groups = a.slice(1, a.length - 2);
      return q.rep.apply(null, [m, mod].concat(groups));
    });
  }
  var pm = MP_PATCHES[2];
  text = text.replace(pm.re, function (m) { return pm.rep(m, moduleSrc); });
  return { ok: true, results: results, text: text };
}

if (typeof module !== 'undefined') module.exports = { MP_PATCHES: MP_PATCHES, mpApply: mpApply, MP_MARK: MP_MARK };
