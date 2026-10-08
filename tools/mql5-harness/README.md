# Harness di verifica per gli script MQL5

Non e' MetaTrader: e' un header C++ (`mql5_mock.h`) che simula le API MQL5 usate da
`MQL5/Scripts/VP_RR_Study_v1.0.mq5`, `MQL5/Scripts/MDRB_AutoStudy.mq5` e dai due EA corrispondenti
(`VolumeProfile_v1.0_EA_*.mq5`, `MultiDayRangeBreakout.mq5`), piu' un
preprocessore (`prep.py`) che traduce i costrutti MQL5 non C++ (`input`, array dinamici `T a[]`).
Serve a compilare e far girare il codice su dati sintetici **senza MetaEditor** e a controllare che:

1. `SimFixed`/`SimTrail` diano gli stessi risultati di un'implementazione Python indipendente
   (6000 percorsi casuali, con gap, TP assente, ordine intrabarra pessimista/ottimista);
   il trailing e' inoltre confrontato con la `ProcessTrailing()` **reale** dell'EA (estratta verbatim
   da `extract_trailing.py`) fatta girare tick per tick su un percorso denso (`main_trail_ref.cpp`);
2. i segnali tecnici dello script coincidano **uno a uno** con quelli dell'EA reale fatto girare
   barra per barra (M5/M15/H1, sessioni/Daily/Weekly/Monthly, DST, filtri, TF profilo diverso);
3. non ci siano accessi fuori indice (AddressSanitizer) in scenari limite;
4. su un random walk senza costi nessuna cella validi in OOS, e con mean-reversion forte il
   fade ai bordi della Value Area risulti significativo (test nullo e test di potenza).

5. (MDRB) `./run_mdrb.sh`: l'EA `MultiDayRangeBreakout` **reale** gira su un broker simulato
   (`mock_broker.h`: ordini stop OCO, gap, stops level, SL/TP/BE/trailing tick per tick) sugli stessi dati
   di `MDRB_Study`; piazzamenti e trade (apertura, chiusura, R) devono coincidere in 29 scenari
   (modalita' range, finestre, offset, chase, trailing/BE, TF, ...). Le uniche differenze ammesse sono
   quelle dichiarate nello script (EA occupato -> giorno saltato, ri-piazzamento a meta' finestra).

6. (MDRB, modalita' AUTO) `./run_auto_tests.sh`: l'orizzonte adattivo degli sweep da' una mappa identica byte per byte
   a quella con orizzonte pieno; ogni riga della mappa coincide con l'analisi completa della stessa definizione
   lanciata come configurazione singola (`InpAuto=0`, `auto_consistency.py`, incluso il taglio IS/OOS per data);
   AddressSanitizer pulito; test nullo (random walk a costi zero: i vincitori scelti sull'IS non si confermano
   OOS oltre il ~5%, `auto_null.py`) e test di potenza (il salto giornaliero del livello medio nei dati sintetici
   deve emergere nelle finestre notturne e confermarsi OOS). Controlli aggiunti con la Parte A / modalita' PERSONALIZZATA:
   - `cb_check.py`: eventi della Parte A (prima candela che chiude fuori dal range, k = candele trascorse, entrata alla
     chiusura), i 21 esiti SL x RR, MFE/rientro a 4 ore e la sopravvivenza (escursione avversa prima del bersaglio)
     ricalcolati in Python da zero sui dati M1 esportati (`MDRB_DUMP_M1=1`); con finestra `-2` verifica tutte le
     finestre di un time frame e le statistiche aggregate su eventi distinti (un evento per candela d'ingresso);
     il generatore accetta `GEN_GAPS=p` (barre M1 mancanti a caso) e `GEN_BREAK=1` (pausa giornaliera 22-23), perche'
     con dati densi alcuni difetti (buffer delle candele, k) non si vedono;
   - `event_check.py`: ritest del livello, meta' range, zona del giorno prima, falsi breakout, MFE e rientro in punti
     ricalcolati in Python dal CSV dei trade;
   - `custom_check.py`: ogni filtro PERSONALIZZATO (giorni con separatori/intervalli/nomi, periodo con ultimo giorno incluso,
     larghezza, range orario con ora o durata da sole, finestra, time frame) restringe davvero l'universo e nient'altro, e le
     scelte incoerenti fermano lo script con un messaggio chiaro;
   - metro di misura PUNTI / ATR / ENTRAMBI: struttura del report attesa per ciascuno;
   - `cb2_check.py`: la parte A2 (range = ultime N candele di un time frame) ricalcolata in Python da zero, con eventi
     distinti, istogramma di k e range osservati; `cb_check.py` verifica anche larghezza dei range e fasce (terzili IS);
   - riepilogo di testo da copiare (`*_RIEPILOGO.txt`, oppure `_parte1/_parte2` oltre `g_digLimit` caratteri): nessun HTML
     residuo, sezioni chiave presenti, un file con limite alto e due parti con limite basso (in `custom_check.py`).

   - `bc_check.py` (Parte B, variante a conferma a chiusura di candela, 7 time frame): la candela di conferma (prima candela del TF che chiude oltre
     il livello + offset, dopo il piazzamento ed entro la scadenza), l'ingresso, lo slippage del prezzo pagato, le 19 uscite SL x RR, MFE/rientro/falsi
     breakout e la completezza (nessun evento mancante o in piu', con il piazzamento preso dalle righe al tocco) ricalcolati in Python dai dati M1;
   - `rd_check.py` (Parte B, anatomia del range): ogni giorno con un range valido (range, durata, posizione di chiusura, eta' e lato dell'ultimo estremo,
     contesto rispetto al D1 del giorno prima, compressione, ATR) e gli esiti puri a tre orizzonti (finestra, 4 h, 24 h) ricalcolati in Python;
   - il riepilogo generale in testa al report e al file di testo (`RIEPILOGO GENERALE`, `CONCLUSIONE AUTOMATICA`) e le sezioni `2b` e `4c` sono controllate
     nel riepilogo di testo da `custom_check.py`.

7. (MDRB, EA) `./run_slot_tests.sh`: l'**analisi virtuale** dell'EA (`SlotScan=true`: 12 fasce orarie + range a barre + D1 precedenti, ciascuno con
   le tre modalita' di entrata: ordini stop, chiusura di candela, retest) viene confrontata concorrente per concorrente con l'**EA reale** sul broker
   simulato (stesso range via `RANGE_TIME`/`RANGE_BARS`/`RANGE_PREV_D1`, UNA sola modalita' accesa), sugli stessi tick (`PATHMODE=fixed`, percorso denso
   indipendente dallo stato dell'EA; `EXEC_AT_TICK=1`: stop e SL/TP si eseguono al prezzo del tick, che e' il modello dell'analisi virtuale: con il
   riempimento "al prezzo dell'ordine" del broker semplice la differenza di mezzo tick viene amplificata dal trailing a un intero scalino).
   13 scenari (finestre, filtri, chase, trailing, piu' trade al giorno, scadenza estesa, M5/H1, offset 0, tolleranza del retest, finestra a
   cavallo di mezzanotte...): stesso numero di trade, stessa direzione, stesso minuto di apertura, R entro 0.02 e chiusura entro 2 minuti
   (`slot_check.py`); la classifica e le metriche (E[R], PF, R totale, drawdown, t-stat, prima/dopo la data di separazione, ordine) sono
   ricalcolate in modo indipendente dal CSV dei trade (`slot_rank_check.py`); scansione e EA reale sotto AddressSanitizer + UBSan;
   input non validi rifiutati. `ONLY=n NOTAIL=1 ./run_slot_tests.sh` lancia solo lo scenario n.

Uso: `./run_all.sh` (richiede `g++` e `python3`; crea la cartella `build/`; include `run_mdrb.sh`).

Nota: sui prezzi tondi l'EA reale puo' fallire confronti a soglia esatta per rumore float
(`profitPts >= 150` con 149.9999...); la batteria MDRB usa una griglia di prezzo fine (`GEN_ROUND=1e7`)
per non misurare questo rumore, che nello script e' assorbito da una tolleranza.

Limiti: dati sintetici con tick volume (il percorso a volume reale non e' coperto), nessun
comportamento reale del terminale (sincronizzazione storico, Max barre nel grafico). Un esito OK qui
non sostituisce la compilazione in MetaEditor.
