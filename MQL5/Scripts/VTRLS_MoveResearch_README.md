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

## File prodotti

| File | Contenuto |
|---|---|
| `<SYM>_daily.csv` | 1 riga/giorno: blocco D-1, blocco D pre-evento, Largest Move, news |
| `<SYM>_largest.csv` | solo il movimento maggiore: ora inizio/fine, direzione, punti, durata, ATR, sessione, news |
| `<SYM>_timedist.csv` | distribuzione dei Largest Move per bucket H1 e M15 |
| `<SYM>_scan.csv` | griglia point-in-time grezza (feature a *t* + esito forward) |
| `<SYM>_conditions.csv` | condizioni incrociate (range D-1 x dir D-1 x punti pre x net x sessione x news) |
| `<SYM>_conditions_marg.csv` | stesse metriche, una dimensione per volta (piu' campioni, piu' robusto) |

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
