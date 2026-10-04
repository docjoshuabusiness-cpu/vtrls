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
   - `cb_check.py`: eventi della Parte A (prima candela che chiude fuori dal range, k candele dopo, entrata alla
     chiusura) e i 21 esiti SL x RR ricalcolati in Python da zero sui dati M1 esportati (`MDRB_DUMP_M1=1`);
   - `event_check.py`: ritest del livello, meta' range, zona del giorno prima, falsi breakout, MFE e rientro in punti
     ricalcolati in Python dal CSV dei trade;
   - `custom_check.py`: ogni filtro PERSONALIZZATO (giorni, periodo, larghezza, range orario, finestra, time frame)
     restringe davvero l'universo e nient'altro;
   - metro di misura PUNTI / ATR / ENTRAMBI: struttura del report attesa per ciascuno.

Uso: `./run_all.sh` (richiede `g++` e `python3`; crea la cartella `build/`; include `run_mdrb.sh`).

Nota: sui prezzi tondi l'EA reale puo' fallire confronti a soglia esatta per rumore float
(`profitPts >= 150` con 149.9999...); la batteria MDRB usa una griglia di prezzo fine (`GEN_ROUND=1e7`)
per non misurare questo rumore, che nello script e' assorbito da una tolleranza.

Limiti: dati sintetici con tick volume (il percorso a volume reale non e' coperto), nessun
comportamento reale del terminale (sincronizzazione storico, Max barre nel grafico). Un esito OK qui
non sostituisce la compilazione in MetaEditor.
