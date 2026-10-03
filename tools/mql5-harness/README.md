# Harness di verifica per gli script MQL5

Non e' MetaTrader: e' un header C++ (`mql5_mock.h`) che simula le API MQL5 usate da
`MQL5/Scripts/VP_RR_Study_v1.0.mq5` e da `MQL5/Experts/VolumeProfile_v1.0_EA_*.mq5`, piu' un
preprocessore (`prep.py`) che traduce i costrutti MQL5 non C++ (`input`, array dinamici `T a[]`).
Serve a compilare e far girare il codice su dati sintetici **senza MetaEditor** e a controllare che:

1. `SimFixed`/`SimTrail` diano gli stessi risultati di un'implementazione Python indipendente
   (6000 percorsi casuali, con gap, TP assente, ordine intrabarra pessimista/ottimista);
2. i segnali tecnici dello script coincidano **uno a uno** con quelli dell'EA reale fatto girare
   barra per barra (M5/M15/H1, sessioni/Daily/Weekly/Monthly, DST, filtri, TF profilo diverso);
3. non ci siano accessi fuori indice (AddressSanitizer) in scenari limite;
4. su un random walk senza costi nessuna cella validi in OOS, e con mean-reversion forte il
   fade ai bordi della Value Area risulti significativo (test nullo e test di potenza).

Uso: `./run_all.sh` (richiede `g++` e `python3`; crea la cartella `build/`).

Limiti: dati sintetici con tick volume (il percorso a volume reale non e' coperto), nessun
comportamento reale del terminale (sincronizzazione storico, Max barre nel grafico). Un esito OK qui
non sostituisce la compilazione in MetaEditor.
