# VTRLS_MoveResearch_v1 — motore di ricerca condizioni operative

Script MQL5 (non EA, non fa trading). Legge lo storico di uno o piu' simboli e
produce 6 CSV in `MQL5/Files/<InpOutDir>/`. Separatore `;`, decimale `.`.

## Installazione
Copiare `VTRLS_MoveResearch_v1.mq5` in `MQL5/Scripts/`, compilare (F7),
trascinare sul grafico, impostare gli input, eseguire.
Prima di lanciarlo scaricare lo storico del TF base (Strumenti > Opzioni >
Grafici > barre massime = illimitato; poi aprire il grafico M1 e premere Home
finche' la storia non e' completa).

## Regola anti-bias (fondamentale)
Il **Largest Move** e' noto solo a posteriori: descrive, non predice. Non e'
un'etichetta valida per costruire una strategia, perche' quando parte non sai
che sara' il piu' grande della giornata.

Percio':
- le colonne `pre_*` del file `_daily.csv` usano **solo** le barre che
  precedono la barra di inizio del Largest Move;
- le tabelle delle condizioni **non** usano il Largest Move come target, ma
  la domanda operativa reale, calcolata sulla griglia point-in-time:

  > date queste condizioni all'istante *t*, qual e' la probabilita' che nelle
  > prossime N ore il prezzo faccia +X **prima** di fare -X*AdverseRatio?

  Entrata all'open della barra *t*, esito per **first touch** target/stop.
  Se target e stop cadono nella stessa barra si conta **stop** (ipotesi
  conservativa: senza tick non si conosce l'ordine intrabar).

## Due formati di output
`InpWriteHtml` (default true) produce **`<SYM>_report.html`**: un file autonomo,
doppio clic e si apre nel browser. Nessuna libreria esterna, nessuna
connessione, funziona offline. Contiene sette schede (Riepilogo, Giornaliero,
Largest Move, Orari, Aggregati, Condizioni incrociate, Condizioni marginali) con
ordinamento cliccando sulle intestazioni, filtro testuale e colorazione
automatica delle celle rilevanti.

`InpWriteCsv` (default true) produce i CSV con tutte le colonne, inclusa la
griglia point-in-time grezza, per Excel e Python. L'HTML omette qualche colonna
per restare leggibile: per l'analisi seria usa i CSV.

Puoi disattivare l'uno o l'altro.

## File prodotti

| File | Contenuto |
|---|---|
| `<SYM>_daily.csv` | 1 riga/giorno: blocco D-1, blocco D pre-evento, Largest Move, news |
| `<SYM>_largest.csv` | solo il movimento maggiore: ora inizio/fine, direzione, punti, durata, ATR, sessione, news |
| `<SYM>_timedist.csv` | distribuzione dei Largest Move per bucket H1 e M15 |
| `<SYM>_scan.csv` | griglia point-in-time grezza (feature a *t* + esito forward) |
| `<SYM>_conditions.csv` | condizioni incrociate (range D-1 x dir D-1 x punti pre x net x sessione x news) |
| `<SYM>_conditions_marg.csv` | stesse metriche, una dimensione per volta (piu' campioni, piu' robusto) |
| `<SYM>_aggregate.csv` | giornate raggruppate per giorno della settimana, anno, mese e sessione |
| `<SYM>_dow_hour.csv` | matrici giorno x ora, giorno x 15 minuti e anno x ora |
| `<SYM>_indicatori_tf.csv` | stessi stati RSI/CCI/Z-Score calcolati sui tre timeframe, con delta sul riferimento |
| `<SYM>_orb_finestre.csv` | tutte le finestre di osservazione testate, con % di rottura, win rate, Wilson, valore atteso e le due meta' del periodo |
| `<SYM>_orb_breakout.csv` | una riga per ogni rottura della finestra selezionata: direzione, esito, range, intensita', volatilita', RSI/CCI/Z al momento della rottura, MFE/MAE |
| `<SYM>_report.html` | tutto quanto sopra (tranne lo scan grezzo) in un report navigabile |

## Indicatori: tre timeframe nella stessa passata
`InpIndTF1` / `InpIndTF2` / `InpIndTF3` (default M15, M5, M1) sono i timeframe su
cui vengono calcolati RSI, CCI e Z-Score. Gli istanti osservati e l'esito forward
sono **gli stessi** per tutti e tre: cambia solo la barra su cui l'indicatore
viene letto, sempre l'ultima **chiusa** prima dell'istante.

`InpIndTfMain` (1/2/3) sceglie quale dei tre alimenta condizioni, setup e
classifiche. Gli altri due servono solo al confronto, nella scheda *Indicatori*:
questo evita di mescolare timeframe dentro lo stesso segnale, che a mercato non
sarebbe replicabile.

Come si legge: **non** prendere il timeframe col delta migliore. Scendendo di
timeframe il numero di eventi esplode, ma gli istanti restano gli stessi e
diventano solo piu' correlati: un `n` piu' grande su M1 non e' piu' informazione.
Conta se il **segno del delta** e' lo stesso sui tre, e se le ore buone sono le
stesse. Se cambia segno, non hai tre conferme: hai tre rumori.

`InpIndTfCompare = false` calcola solo il timeframe principale: il confronto su
M1 su periodi storici lunghi allunga sensibilmente il run.

## Range di osservazione e breakout

Due schede del report (`Range e breakout`, `Breakout operativo`) rispondono a una
domanda in due tempi: **dove** si forma l'accumulazione dentro la giornata, e
**cosa** succede quando quel range viene rotto.

**Primo tempo.** Lo script non decide a priori quale sia la fascia buona: prova
ogni combinazione di ora di inizio (`InpOrbFirstHour` -> `InpOrbLastHour`, passo
`InpOrbStartStep`) e durata (`InpOrbDur`), tipicamente qualche centinaio di
finestre. Per ognuna costruisce massimo e minimo **solo con le barre dentro la
finestra**, poi aspetta la rottura di un estremo entro `InpOrbDeadlineMin` minuti.

**Secondo tempo.** Entrata sul livello rotto, target `InpOrbTargetAtr` ATR, stop
`InpAdverseRatio` x target, esito a primo tocco entro `InpScanHorizonMin`.
La barra in cui avviene la rottura viene valutata **solo per lo stop, mai per il
target**: dentro una barra l'ordine dei prezzi non e' noto, e assumere che il
target sia arrivato prima gonfierebbe il win rate a gratis. I numeri veri sono
uguali o migliori, mai peggiori.

Le rotture che toccano **entrambi** i livelli nella stessa barra sono contate a
parte come *ambigue* e non entrano nel win rate: non sono operabili.

### Come si legge senza prendere fischi per fiaschi

La classifica **non** e' ordinata sul win rate. E' ordinata su `score` = ATR
attesi ogni 100 giornate, calcolato sul **limite inferiore di Wilson** invece che
sulla percentuale grezza: cosi' un 70% con dodici operazioni finisce sotto un 56%
con duecento, che e' l'ordine giusto.

Tre controlli, in ordine di importanza:

1. **1a meta' / 2a meta'.** Il win rate nelle due meta' del periodo. Se divergono,
   la finestra non e' un edge: e' rumore finito in cima alla lista.
2. **La matrice inizio x durata.** Un effetto vero forma un *altopiano* di celle
   vicine tutte decenti. Un picco isolato circondato da celle mediocri e' fortuna.
3. **wlow contro il breakeven richiesto.** Con stop meta' del target servono il
   33,3% per non perdere. Se il limite inferiore di Wilson resta sotto, quel
   segnale non ha dimostrato nulla, per quanto bello sia il win rate grezzo.

### Sui filtri, e sul "100% di sicurezza"

Non esiste, e nessun indicatore lo produce. Ogni filtro che alza il win rate lo fa
**riducendo il numero di operazioni**, e oltre un certo punto sta solo selezionando
il rumore che gli e' piaciuto in questo campione. Nella scheda `Breakout operativo`
la colonna che conta e' **delta E** letta insieme a **n**: un filtro serve se
migliora il valore atteso senza ridurre il campione a poche decine di operazioni
in dieci anni. Un segnale filtrato fino al 90% con venti occorrenze non e' forte:
e' morto.

I filtri di intensita' e volatilita' leggono le `InpOrbMomBars` barre **che
precedono** la rottura, mai quella in cui avviene.

### In-sample, dichiarato

Se `InpOrbFixStartMin` resta a -1, la finestra della scheda operativa e' quella
che ha vinto la classifica **sullo stesso campione** su cui viene poi misurata.
E' selezione in-sample e una parte del vantaggio e' fortuna per costruzione: le
colonne sulle due meta' servono a quantificarla. Per un numero onesto, fissa la
finestra con `InpOrbFixStartMin` / `InpOrbFixDurMin` e rilancia su un altro
periodo o un altro simbolo.

`InpDoOrb = false` salta entrambe le schede.

## Normalizzazione cross-simbolo
Le soglie in punti non sono confrontabili tra XAUUSD, US30 ed EURUSD. Ogni
metrica esiste in **punti** e in **multipli di ATR(D-1)**; i bin delle tabelle
condizioni sono in ATR, quindi la stessa condizione ha senso su ogni simbolo.
L'ATR usato per la giornata D e' quello calcolato **fino a D-1** (point-in-time).

## Come leggere le tabelle condizioni
Ogni cella riporta, per ogni soglia:
- `n_<soglia>` numero di successi, `p_<soglia>` probabilita' %,
- `wlow_<soglia>` **limite inferiore di Wilson al 95%**,
- `lift_<soglia>` rapporto con la baseline incondizionata (ultima riga del file).

Nel report HTML questo criterio e' gia' applicato: una cella e' **verde** solo
se `lift > 1.20` **e** Wilson-low sopra la baseline, **rossa** se sotto
baseline, **grigia** in tutti gli altri casi, cioe' quando non e'
distinguibile dal caso. Guarda solo il verde, e verificalo comunque.

Una cella con `p=40%`, baseline 38% e `wlow=31%` non e' un edge: e' rumore.
Si guardano **wlow** e **lift**, mai la probabilita' nuda. Con centinaia di
celle testate il multiple testing e' garantito: alza `InpMinSamples`, pretendi
`lift > 1.20` **e** `wlow > baseline`, e verifica che la stessa cella regga
su un secondo periodo e su un secondo simbolo prima di considerarla reale.

## Input principali
- `InpBaseTF` — TF del percorso intraday, da M1 a H1. M1 = massima precisione
  sull'ora di inizio del movimento; H1 = molto piu' veloce, ora approssimata.
- `InpSymbols` — vuoto = simbolo del grafico, `*` = tutto il Market Watch,
  oppure lista separata da virgola.
- `InpCleanLeg` / `InpMaxRetracePct` — se true il Largest Move e' la gamba
  "pulita" (chiusa quando ritraccia oltre X% del run), invece della massima
  escursione assoluta che al suo interno puo' contenere ore di chop.
- `InpScanStepMin` / `InpScanHorizonMin` / `InpAdverseRatio` — griglia,
  orizzonte forward e rapporto stop/target del first touch.
- `InpThrPoints` / `InpThrATR` — soglie di movimento (max 8 ciascuna).
- `InpUseCalendar` — calendario economico MQL5, filtrato sulle valute del
  simbolo. Se il terminale non lo espone, le colonne news restano a 0.

## Limiti noti
- L'ora di inizio del movimento ha la risoluzione del TF base (M1 -> +/-1 min).
- La decomposizione punti UP/DOWN e' ricostruita dall'OHLC di ogni barra
  (rialzista: open->low->high->close; ribassista: open->high->low->close):
  per costruzione `up - down == close - open`. Su M1 l'errore e' trascurabile,
  su H1 no.
- Il calendario MQL5 copre in genere solo gli anni recenti e non e' identico
  tra broker: le colonne news vanno considerate indicative.
- La giornata e' quella del broker (barra D1 del server), quindi FP Markets =
  GMT+2/+3 con DST. Confrontando simboli o periodi lunghi, tienine conto:
  i bucket M15 slittano di un'ora tra ora solare e ora legale.

## Come si esegue (procedura)
1. Copia lo `.mq5` in `MQL5/Scripts/`, compila con F7 in MetaEditor.
2. Nel terminale, Strumenti > Opzioni > Grafici > **Barre massime nel grafico =
   illimitato**. Apri il grafico del simbolo sul TF base (es. M1) e tieni premuto
   Home finche' la storia non arriva alla data che ti serve.
3. Trascina lo script sul grafico: si apre la finestra **Input** (il TF del
   grafico e' irrilevante, conta solo `InpBaseTF`; il simbolo del grafico conta
   solo se `InpSymbols` e' vuoto).
4. Imposta `InpFrom` / `InpTo` / `InpBaseTF` / `InpSymbols` e conferma.
5. Lo script gira una volta e termina da solo. Segui l'avanzamento nella scheda
   **Esperti**: stampa prima barra disponibile, barre nel periodo, giornate
   analizzate e giornate scartate.
6. Output: File > Apri cartella dati > `MQL5\\Files\\VTRLS_Research\\`.

**Primo run consigliato**: 3 mesi, `InpDoScan=false`. Verifichi che i CSV
abbiano senso, poi rilanci sul periodo pieno con lo scan attivo.

Se la riga "giornate scartate" e' alta, lo storico non e' completo: ripeti il
punto 2 e rilancia (al secondo run i dati sono gia' in cache locale).
